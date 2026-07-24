import Foundation

struct PetMetadata: Equatable {
    static let defaultSimba = PetMetadata(
        id: "simba",
        name: "Simba",
        slug: "simba",
        ownerUid: nil,
        storagePath: "resources/simba",
        requiredImagesComplete: true,
        isDefault: true,
        isPublic: true
    )

    let id: String
    let name: String
    let slug: String
    let ownerUid: String?
    let storagePath: String
    let requiredImagesComplete: Bool
    let isDefault: Bool
    let isPublic: Bool

    func renamed(to name: String) -> PetMetadata {
        PetMetadata(
            id: id,
            name: name,
            slug: slug,
            ownerUid: ownerUid,
            storagePath: storagePath,
            requiredImagesComplete: requiredImagesComplete,
            isDefault: isDefault,
            isPublic: isPublic
        )
    }

    func withPublicVisibility(_ isPublic: Bool) -> PetMetadata {
        PetMetadata(
            id: id,
            name: name,
            slug: slug,
            ownerUid: ownerUid,
            storagePath: storagePath,
            requiredImagesComplete: requiredImagesComplete,
            isDefault: isDefault,
            isPublic: isPublic
        )
    }
}

struct PetSelectionState {
    let currentUserId: String
    let pets: [PetMetadata]
    let activePet: PetMetadata
    let accountState: PetAccountState
}

enum PetAccountState: Equatable {
    case unavailable
    case anonymous
    case google(userId: String, displayName: String?, email: String?)

    var canUploadPrivatePets: Bool {
        if case .google = self {
            return true
        }
        return false
    }

    var authenticatedUserId: String? {
        guard case .google(let userId, _, _) = self else { return nil }
        return userId
    }
}
