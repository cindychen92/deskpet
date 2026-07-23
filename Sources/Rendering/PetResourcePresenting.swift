protocol PetResourcePresenting: AnyObject {
    func loadRemoteResources(for pet: PetMetadata)
    func say(_ text: String)
}
