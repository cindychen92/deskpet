import Foundation
import FirebaseFirestore

final class FirestorePetRepository {
    private let database: Firestore

    init(database: Firestore = Firestore.firestore()) {
        self.database = database
    }

    func loadPets(
        forUserId userId: String,
        completion: @escaping (Result<([PetMetadata], String?), Error>) -> Void
    ) {
        var loadedPets: [PetMetadata]?
        var activePetId: String?
        var firstError: Error?
        let lock = NSLock()
        let group = DispatchGroup()

        group.enter()
        database.collection("pets")
            .getDocuments { snapshot, error in
                defer { group.leave() }
                if let error {
                    lock.lock()
                    firstError = firstError ?? error
                    lock.unlock()
                    return
                }
                let pets = snapshot?.documents.compactMap(Self.makePetMetadata) ?? []
                lock.lock()
                loadedPets = pets
                lock.unlock()
            }

        group.enter()
        database.collection("users").document(userId).getDocument { snapshot, error in
            defer { group.leave() }
            if let error {
                lock.lock()
                firstError = firstError ?? error
                lock.unlock()
                return
            }
            lock.lock()
            activePetId = snapshot?.data()?["activePetId"] as? String
            lock.unlock()
        }

        group.notify(queue: .main) {
            let pets = Self.deduplicate(loadedPets ?? [])
            if let firstError, pets.isEmpty {
                completion(.failure(firstError))
                return
            }
            completion(.success((pets, activePetId)))
        }
    }

    func saveActivePetId(
        _ petId: String,
        forUserId userId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        database.collection("users").document(userId).setData(
            [
                "activePetId": petId,
                "updatedAt": FieldValue.serverTimestamp()
            ],
            merge: true
        ) { error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    func saveUploadedPet(
        _ pet: PetMetadata,
        forUserId userId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard pet.ownerUid == userId, !pet.isDefault, pet.requiredImagesComplete else {
            completion(.failure(FirestorePetRepositoryError.invalidUploadedPetMetadata))
            return
        }

        let document = database.collection("pets").document(pet.id)
        document.getDocument { snapshot, error in
            if let error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            var data: [String: Any] = [
                "name": pet.name,
                "slug": pet.slug,
                "ownerUid": userId,
                "storagePath": pet.storagePath,
                "requiredImagesComplete": true,
                "isDefault": false,
                "updatedAt": FieldValue.serverTimestamp()
            ]

            if snapshot?.exists != true {
                data["createdAt"] = FieldValue.serverTimestamp()
            }

            document.setData(data, merge: true) { error in
                DispatchQueue.main.async {
                    if let error {
                        completion(.failure(error))
                    } else {
                        completion(.success(()))
                    }
                }
            }
        }
    }

    private static func makePetMetadata(from document: QueryDocumentSnapshot) -> PetMetadata? {
        makePetMetadata(id: document.documentID, data: document.data())
    }

    private static func makePetMetadata(id: String, data: [String: Any]) -> PetMetadata? {
        guard
            let name = data["name"] as? String,
            let slug = data["slug"] as? String,
            let storagePath = data["storagePath"] as? String
        else {
            return nil
        }

        return PetMetadata(
            id: id,
            name: name,
            slug: slug,
            ownerUid: data["ownerUid"] as? String,
            storagePath: storagePath,
            requiredImagesComplete: data["requiredImagesComplete"] as? Bool ?? false,
            isDefault: data["isDefault"] as? Bool ?? false
        )
    }

    private static func deduplicate(_ pets: [PetMetadata]) -> [PetMetadata] {
        var seen: Set<String> = []
        return pets
            .filter { pet in
                guard !seen.contains(pet.id) else { return false }
                seen.insert(pet.id)
                return true
            }
            .sorted { lhs, rhs in
                if lhs.isDefault != rhs.isDefault {
                    return lhs.isDefault
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }
}

enum FirestorePetRepositoryError: LocalizedError {
    case invalidUploadedPetMetadata

    var errorDescription: String? {
        switch self {
        case .invalidUploadedPetMetadata:
            return "Uploaded pet metadata must belong to the current user and have a complete resource set."
        }
    }
}
