import Cocoa

protocol PetResourceLoading {
    var activePet: PetMetadata { get }

    func setActivePet(_ pet: PetMetadata)

    func loadImages(
        named names: [String],
        onImage: @escaping (String, NSImage) -> Void
    )
}
