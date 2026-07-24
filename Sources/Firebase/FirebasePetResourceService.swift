import Cocoa
import FirebaseAuth
import FirebaseCore
import GoogleSignIn

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
                    activePet: .defaultSimba,
                    accountState: .unavailable
                )
            )
            return
        }

        if let userId = Auth.auth().currentUser?.uid {
            currentUserId = userId
            loadPets(
                forUserId: userId,
                accountState: Self.accountState(for: Auth.auth().currentUser),
                onLoaded: onLoaded,
                onError: onError
            )
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
                            activePet: .defaultSimba,
                            accountState: .unavailable
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
                            activePet: .defaultSimba,
                            accountState: .unavailable
                        )
                    )
                }
                return
            }
            self.currentUserId = userId
            DispatchQueue.main.async {
                self.loadPets(
                    forUserId: userId,
                    accountState: .anonymous,
                    onLoaded: onLoaded,
                    onError: onError
                )
            }
        }
    }

    func signInWithGoogle(
        presenting window: NSWindow,
        completion: @escaping (Result<Void, FirebasePetAuthenticationError>) -> Void
    ) {
        guard
            FirebaseConfiguration.isConfigured,
            let clientID = FirebaseApp.app()?.options.clientID,
            !clientID.isEmpty
        else {
            completion(.failure(.notConfigured))
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.signIn(withPresenting: window) { [weak self] result, error in
            if let error {
                let nsError = error as NSError
                if nsError.domain == "com.google.GIDSignIn", nsError.code == -5 {
                    completion(.failure(.cancelled))
                } else {
                    NSLog("Google sign-in failed: \(nsError.localizedDescription)")
                    completion(.failure(.googleSignInFailed))
                }
                return
            }

            guard
                let self,
                let googleUser = result?.user,
                let idToken = googleUser.idToken?.tokenString
            else {
                completion(.failure(.missingGoogleCredential))
                return
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: googleUser.accessToken.tokenString
            )
            self.authenticate(with: credential, completion: completion)
        }
    }

    func signOut(
        completion: @escaping (Result<Void, FirebasePetAuthenticationError>) -> Void
    ) {
        guard FirebaseConfiguration.isConfigured else {
            completion(.failure(.notConfigured))
            return
        }

        do {
            GIDSignIn.sharedInstance.signOut()
            try Auth.auth().signOut()
        } catch {
            NSLog("Firebase sign-out failed: \(error.localizedDescription)")
            completion(.failure(.signOutFailed))
            return
        }

        Auth.auth().signInAnonymously { [weak self] result, error in
            guard let self, let userId = result?.user.uid, error == nil else {
                if let error {
                    NSLog("Anonymous sign-in after sign-out failed: \(error.localizedDescription)")
                }
                completion(.failure(.anonymousSignInFailed))
                return
            }
            self.currentUserId = userId
            DispatchQueue.main.async {
                completion(.success(()))
            }
        }
    }

    func selectPet(
        _ pet: PetMetadata,
        completion: @escaping (Result<PetMetadata, Error>) -> Void
    ) {
        guard isAccessible(pet) else {
            completion(.failure(FirebasePetResourceServiceError.petNotAccessible))
            return
        }
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
        guard
            let currentUserId,
            !currentUserId.isEmpty,
            Self.accountState(for: Auth.auth().currentUser).canUploadPrivatePets
        else {
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

    func renamePet(
        _ pet: PetMetadata,
        to proposedName: String,
        completion: @escaping (Result<PetMetadata, Error>) -> Void
    ) {
        guard let userId = ownerUserId(for: pet) else {
            completion(.failure(FirebasePetResourceServiceError.petNotManageable))
            return
        }

        let name: String
        switch PetResourceManifest.validatedPetName(proposedName) {
        case .success(let validatedName):
            name = validatedName
        case .failure(let error):
            completion(.failure(error))
            return
        }

        petRepository.renamePet(pet.id, to: name, forUserId: userId) { result in
            switch result {
            case .success:
                completion(.success(pet.renamed(to: name)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func deletePet(
        _ pet: PetMetadata,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let userId = ownerUserId(for: pet) else {
            completion(.failure(FirebasePetResourceServiceError.petNotManageable))
            return
        }

        petRepository.deletePet(pet.id, forUserId: userId) { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                guard let self else {
                    completion(.success(()))
                    return
                }
                self.uploader.deleteResources(for: pet) { errors in
                    if !errors.isEmpty {
                        NSLog(
                            "Deleted pet metadata but could not remove all storage objects for \(pet.id): \(errors)"
                        )
                    }
                    completion(.success(()))
                }
            }
        }
    }

    private func loadPets(
        forUserId userId: String,
        accountState: PetAccountState,
        onLoaded: @escaping (PetSelectionState) -> Void,
        onError: @escaping (String) -> Void
    ) {
        petRepository.loadPets(
            forUserId: userId,
            includeOwnedPets: accountState.canUploadPrivatePets
        ) { result in
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
                            activePet: .defaultSimba,
                            accountState: accountState
                        )
                    )
                    return
                }

                onLoaded(
                    PetSelectionState(
                        currentUserId: userId,
                        pets: normalizedPets,
                        activePet: activePet,
                        accountState: accountState
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
                        activePet: .defaultSimba,
                        accountState: accountState
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

    private func authenticate(
        with credential: AuthCredential,
        completion: @escaping (Result<Void, FirebasePetAuthenticationError>) -> Void
    ) {
        guard let user = Auth.auth().currentUser else {
            completion(.failure(.missingAnonymousUser))
            return
        }

        let finish: (AuthDataResult?, Error?) -> Void = { [weak self] result, error in
            if let error {
                NSLog("Firebase Google authentication failed: \(error.localizedDescription)")
                completion(.failure(.firebaseSignInFailed))
                return
            }
            guard let self, let userId = result?.user.uid else {
                completion(.failure(.firebaseSignInFailed))
                return
            }
            self.currentUserId = userId
            DispatchQueue.main.async {
                completion(.success(()))
            }
        }

        guard user.isAnonymous else {
            Auth.auth().signIn(with: credential, completion: finish)
            return
        }

        user.link(with: credential) { result, error in
            guard let error else {
                finish(result, nil)
                return
            }

            let code = (error as NSError).code
            let canUseExistingAccount = code == AuthErrorCode.credentialAlreadyInUse.rawValue
                || code == AuthErrorCode.emailAlreadyInUse.rawValue
            if canUseExistingAccount {
                Auth.auth().signIn(with: credential, completion: finish)
            } else {
                finish(nil, error)
            }
        }
    }

    private func isAccessible(_ pet: PetMetadata) -> Bool {
        if pet.isPublic || pet.isDefault {
            return true
        }
        guard
            let currentUserId,
            Self.accountState(for: Auth.auth().currentUser).canUploadPrivatePets
        else {
            return false
        }
        return pet.ownerUid == currentUserId
    }

    private func ownerUserId(for pet: PetMetadata) -> String? {
        guard
            !pet.isDefault,
            !pet.isPublic,
            let currentUserId,
            pet.ownerUid == currentUserId,
            Self.accountState(for: Auth.auth().currentUser).canUploadPrivatePets
        else {
            return nil
        }
        return currentUserId
    }

    private static func accountState(for user: User?) -> PetAccountState {
        guard let user else { return .unavailable }
        guard !user.isAnonymous else { return .anonymous }
        guard user.providerData.contains(where: { $0.providerID == "google.com" }) else {
            return .anonymous
        }
        return .google(displayName: user.displayName, email: user.email)
    }
}

enum FirebasePetResourceServiceError: LocalizedError {
    case missingCurrentUser
    case petNotAccessible
    case petNotManageable

    var errorDescription: String? {
        switch self {
        case .missingCurrentUser:
            return L10n.text("error.firebase.google_required")
        case .petNotAccessible:
            return L10n.text("error.pet.not_accessible")
        case .petNotManageable:
            return L10n.text("error.pet.not_manageable")
        }
    }
}

enum FirebasePetAuthenticationError: LocalizedError {
    case notConfigured
    case cancelled
    case googleSignInFailed
    case missingGoogleCredential
    case missingAnonymousUser
    case firebaseSignInFailed
    case signOutFailed
    case anonymousSignInFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return L10n.text("error.firebase.not_configured")
        case .cancelled:
            return L10n.text("auth.sign_in.cancelled")
        case .googleSignInFailed, .missingGoogleCredential, .missingAnonymousUser,
             .firebaseSignInFailed:
            return L10n.text("auth.sign_in.failed")
        case .signOutFailed, .anonymousSignInFailed:
            return L10n.text("auth.sign_out.failed")
        }
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}
