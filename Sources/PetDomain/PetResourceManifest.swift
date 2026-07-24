import Foundation

enum PetResourceManifest {
    static let requiredImages = [
        PetResourceRequirement(fileName: "pet-idle", displayNameKey: "resource.image.idle"),
        PetResourceRequirement(fileName: "pet-walk-1", displayNameKey: "resource.image.walk.1"),
        PetResourceRequirement(fileName: "pet-walk-2", displayNameKey: "resource.image.walk.2"),
        PetResourceRequirement(fileName: "pet-walk-3", displayNameKey: "resource.image.walk.3"),
        PetResourceRequirement(fileName: "pet-walk-4", displayNameKey: "resource.image.walk.4"),
        PetResourceRequirement(fileName: "pet-lie", displayNameKey: "resource.image.lie"),
        PetResourceRequirement(fileName: "pet-sleep", displayNameKey: "resource.image.sleep"),
        PetResourceRequirement(fileName: "pet-eat", displayNameKey: "resource.image.eat"),
        PetResourceRequirement(fileName: "pet-cuddle", displayNameKey: "resource.image.cuddle")
    ]
    static let requiredImageNames = requiredImages.map(\.fileName)

    static func displayName(for fileName: String) -> String {
        requiredImages.first(where: { $0.fileName == fileName })?.displayName ?? fileName
    }

    static func validatedPetName(_ name: String) -> Result<String, PetNameValidationError> {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.empty)
        }
        guard !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return .failure(.containsControlCharacter)
        }
        return .success(name)
    }
}

struct PetResourceRequirement {
    let fileName: String
    let displayNameKey: String

    var displayName: String {
        L10n.text(displayNameKey)
    }
}

enum PetNameValidationError: LocalizedError {
    case empty
    case containsControlCharacter

    var errorDescription: String? {
        switch self {
        case .empty:
            return L10n.text("error.pet_name.empty")
        case .containsControlCharacter:
            return L10n.text("error.pet_name.control_character")
        }
    }
}
