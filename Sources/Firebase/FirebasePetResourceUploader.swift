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
        let storagePath = "resources/\(petId)"
        let pet = PetMetadata(
            id: petId,
            name: validatedName,
            slug: petId,
            ownerUid: ownerUserId,
            storagePath: storagePath,
            requiredImagesComplete: true,
            isDefault: false
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
            return "Firebase 尚未配置，无法上传宠物图片。"
        case .missingImages(let names):
            return "仍缺少图片：\(names.map { PetResourceManifest.displayName(for: $0) }.joined(separator: "、"))"
        case .invalidPNG(let name):
            return "“\(PetResourceManifest.displayName(for: name))”不是可读取的 PNG 图片。"
        case .uploadFailed(let resourceName, let underlying):
            return "“\(PetResourceManifest.displayName(for: resourceName))”上传失败：\(underlying.localizedDescription)"
        }
    }
}
