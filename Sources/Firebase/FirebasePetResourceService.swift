import Foundation
import FirebaseAuth

final class FirebasePetResourceService {
    private var repository: FirestorePetRepository?
    private let uploader: FirebasePetResourceUploader
    private var currentUserId: String?

    init(
        repository: FirestorePetRepository? = nil,
        uploader: FirebasePetResourceUploader = FirebasePetResourceUploader()
    ) {
        self.repository = repository
        self.uploader = uploader
    }

    func configureIfNeeded() {
        FirebaseConfiguration.configureIfNeeded()
    }

    func authenticateAndLoadPets(
        onLoaded: @escaping (PetSelectionState) -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard FirebaseConfiguration.isConfigured else {
            NSLog("Firebase is not configured; skipping remote pet resources.")
            onLoaded(
                PetSelectionState(
                    currentUserId: "",
                    pets: [.defaultSimba],
                    activePet: .defaultSimba
                )
            )
            return
        }

        if let userId = Auth.auth().currentUser?.uid {
            currentUserId = userId
            loadPets(forUserId: userId, onLoaded: onLoaded, onError: onError)
            return
        }

        Auth.auth().signInAnonymously { [weak self] result, error in
            if let error {
                let nsError = error as NSError
                NSLog(
                    "Firebase anonymous sign-in failed: domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription) userInfo=\(nsError.userInfo)"
                )
                DispatchQueue.main.async {
                    onError(L10n.text("error.pet_list.unavailable"))
                    onLoaded(
                        PetSelectionState(
                            currentUserId: "",
                            pets: [.defaultSimba],
                            activePet: .defaultSimba
                        )
                    )
                }
                return
            }
            guard let self, let userId = result?.user.uid else {
                DispatchQueue.main.async {
                    onError(L10n.text("error.pet_list.unavailable"))
                    onLoaded(
                        PetSelectionState(
                            currentUserId: "",
                            pets: [.defaultSimba],
                            activePet: .defaultSimba
                        )
                    )
                }
                return
            }
            self.currentUserId = userId
            DispatchQueue.main.async {
                self.loadPets(forUserId: userId, onLoaded: onLoaded, onError: onError)
            }
        }
    }

    func selectPet(
        _ pet: PetMetadata,
        completion: @escaping (Result<PetMetadata, Error>) -> Void
    ) {
        guard !currentUserId.isNilOrEmpty else {
            completion(.success(pet))
            return
        }

        petRepository.saveActivePetId(pet.id, forUserId: currentUserId!) { result in
            switch result {
            case .success:
                completion(.success(pet))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func saveUploadedPetMetadata(
        _ pet: PetMetadata,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let currentUserId, !currentUserId.isEmpty else {
            completion(.failure(FirebasePetResourceServiceError.missingCurrentUser))
            return
        }
        petRepository.saveUploadedPet(pet, forUserId: currentUserId, completion: completion)
    }

    func uploadPet(
        named name: String,
        files: [String: URL],
        completion: @escaping (Result<PetMetadata, Error>) -> Void
    ) {
        guard let currentUserId, !currentUserId.isEmpty else {
            completion(.failure(FirebasePetResourceServiceError.missingCurrentUser))
            return
        }

        uploader.upload(
            petName: name,
            ownerUserId: currentUserId,
            files: files
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let pet):
                self.saveUploadedPetMetadata(pet) { metadataResult in
                    switch metadataResult {
                    case .success:
                        completion(.success(pet))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func loadPets(
        forUserId userId: String,
        onLoaded: @escaping (PetSelectionState) -> Void,
        onError: @escaping (String) -> Void
    ) {
        petRepository.loadPets(forUserId: userId) { result in
            switch result {
            case .success(let (pets, activePetId)):
                let normalizedPets = self.normalizedPets(pets)
                guard let activePet = self.resolveActivePet(
                    in: normalizedPets,
                    preferredPetId: activePetId
                ) else {
                    onError(L10n.text("error.pet_list.incomplete"))
                    onLoaded(
                        PetSelectionState(
                            currentUserId: userId,
                            pets: [.defaultSimba],
                            activePet: .defaultSimba
                        )
                    )
                    return
                }

                onLoaded(
                    PetSelectionState(
                        currentUserId: userId,
                        pets: normalizedPets,
                        activePet: activePet
                    )
                )

                if activePet.id != activePetId {
                    self.petRepository.saveActivePetId(activePet.id, forUserId: userId) { _ in }
                }

            case .failure(let error):
                NSLog("Unable to load Firestore pet metadata: \(error.localizedDescription)")
                onError(L10n.text("error.pet_list.unavailable"))
                onLoaded(
                    PetSelectionState(
                        currentUserId: userId,
                        pets: [.defaultSimba],
                        activePet: .defaultSimba
                    )
                )
            }
        }
    }

    private func normalizedPets(_ pets: [PetMetadata]) -> [PetMetadata] {
        var petsById = Dictionary(
            uniqueKeysWithValues: pets
                .filter(\.requiredImagesComplete)
                .map { ($0.id, $0) }
        )
        petsById[PetMetadata.defaultSimba.id] = petsById[PetMetadata.defaultSimba.id] ?? .defaultSimba
        return petsById.values.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var petRepository: FirestorePetRepository {
        if let repository {
            return repository
        }

        let repository = FirestorePetRepository()
        self.repository = repository
        return repository
    }

    private func resolveActivePet(
        in pets: [PetMetadata],
        preferredPetId: String?
    ) -> PetMetadata? {
        if
            let preferredPetId,
            let pet = pets.first(where: { $0.id == preferredPetId }),
            pet.requiredImagesComplete
        {
            return pet
        }

        if let defaultPet = pets.first(where: { $0.isDefault && $0.requiredImagesComplete }) {
            return defaultPet
        }

        return pets.first(where: \.requiredImagesComplete)
    }
}

enum FirebasePetResourceServiceError: LocalizedError {
    case missingCurrentUser

    var errorDescription: String? {
        switch self {
        case .missingCurrentUser:
            return L10n.text("error.firebase.missing_user")
        }
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}
