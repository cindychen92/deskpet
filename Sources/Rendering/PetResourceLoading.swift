import Cocoa

protocol PetResourceLoading {
    func loadImages(
        named names: [String],
        onImage: @escaping (String, NSImage) -> Void
    )
}
