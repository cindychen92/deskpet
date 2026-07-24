import Cocoa
import Foundation
import FirebaseStorage

final class FirebasePetResourceUploader {
    func upload(
        petName: String,
        ownerUserId: String,
        files: [String: URL],
        completion: @escaping (Result<PetMetadata, Error>) -> Void
    ) {
        guard FirebaseConfiguration.isConfigured else {
            completion(.failure(FirebasePetResourceUploadError.firebaseNotConfigured))
            return
        }

        let validatedName: String
        switch PetResourceManifest.validatedPetName(petName) {
        case .success(let name):
            validatedName = name
        case .failure(let error):
            completion(.failure(error))
            return
        }

        let missingNames = PetResourceManifest.requiredImageNames.filter { files[$0] == nil }
        guard missingNames.isEmpty else {
            completion(.failure(FirebasePetResourceUploadError.missingImages(missingNames)))
            return
        }

        for name in PetResourceManifest.requiredImageNames {
            guard let url = files[name], isValidPNG(at: url) else {
                completion(.failure(FirebasePetResourceUploadError.invalidPNG(name)))
                return
            }
        }

        let petId = UUID().uuidString.lowercased()
        let storagePath = "users/\(ownerUserId)/pets/\(petId)"
        let pet = PetMetadata(
            id: petId,
            name: validatedName,
            slug: petId,
            ownerUid: ownerUserId,
            storagePath: storagePath,
            requiredImagesComplete: true,
            isDefault: false,
            isPublic: false
        )
        let group = DispatchGroup()
        let lock = NSLock()
        var firstError: Error?

        for name in PetResourceManifest.requiredImageNames {
            guard let url = files[name] else { continue }
            group.enter()
            let metadata = StorageMetadata()
            metadata.contentType = "image/png"
            Storage.storage()
                .reference()
                .child("\(storagePath)/\(name).png")
                .putFile(from: url, metadata: metadata) { _, error in
                    if let error {
                        lock.lock()
                        firstError = firstError ?? FirebasePetResourceUploadError.uploadFailed(
                            resourceName: name,
                            underlying: error
                        )
                        lock.unlock()
                    }
                    group.leave()
                }
        }

        group.notify(queue: .main) {
            if let firstError {
                completion(.failure(firstError))
            } else {
                completion(.success(pet))
            }
        }
    }

    func deleteResources(
        for pet: PetMetadata,
        completion: @escaping ([Error]) -> Void
    ) {
        let group = DispatchGroup()
        let lock = NSLock()
        var errors: [Error] = []

        for name in PetResourceManifest.requiredImageNames {
            group.enter()
            Storage.storage()
                .reference()
                .child("\(pet.storagePath)/\(name).png")
                .delete { error in
                    if let error {
                        let nsError = error as NSError
                        if nsError.code != StorageErrorCode.objectNotFound.rawValue {
                            lock.lock()
                            errors.append(error)
                            lock.unlock()
                        }
                    }
                    group.leave()
                }
        }

        group.notify(queue: .main) {
            completion(errors)
        }
    }

    private func isValidPNG(at url: URL) -> Bool {
        guard
            url.isFileURL,
            url.pathExtension.lowercased() == "png",
            FileManager.default.isReadableFile(atPath: url.path)
        else {
            return false
        }
        return NSImage(contentsOf: url) != nil
    }
}

enum FirebasePetResourceUploadError: LocalizedError {
    case firebaseNotConfigured
    case missingImages([String])
    case invalidPNG(String)
    case uploadFailed(resourceName: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .firebaseNotConfigured:
            return L10n.text("error.firebase.not_configured")
        case .missingImages(let names):
            let displayNames = names.map { PetResourceManifest.displayName(for: $0) }
            return L10n.format("error.resource.missing_images", L10n.list(displayNames))
        case .invalidPNG(let name):
            return L10n.format(
                "error.resource.invalid_png",
                PetResourceManifest.displayName(for: name)
            )
        case .uploadFailed(let resourceName, let underlying):
            return L10n.format(
                "error.resource.upload_failed",
                PetResourceManifest.displayName(for: resourceName),
                underlying.localizedDescription
            )
        }
    }
}
