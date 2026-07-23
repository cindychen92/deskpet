import Foundation

struct PetMetadata: Equatable {
    static let defaultSimba = PetMetadata(
        id: "simba",
        name: "Simba",
        slug: "simba",
        ownerUid: nil,
        storagePath: "resources/simba",
        requiredImagesComplete: true,
        isDefault: true
    )

    let id: String
    let name: String
    let slug: String
    let ownerUid: String?
    let storagePath: String
    let requiredImagesComplete: Bool
    let isDefault: Bool
}

struct PetSelectionState {
    let currentUserId: String
    let pets: [PetMetadata]
    let activePet: PetMetadata
}
