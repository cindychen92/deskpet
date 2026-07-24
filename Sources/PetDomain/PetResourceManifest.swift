import Foundation

enum PetResourceManifest {
    static let requiredImages = [
        PetResourceRequirement(fileName: "pet-idle", displayName: "平常的样子"),
        PetResourceRequirement(fileName: "pet-walk-1", displayName: "走路 1"),
        PetResourceRequirement(fileName: "pet-walk-2", displayName: "走路 2"),
        PetResourceRequirement(fileName: "pet-walk-3", displayName: "走路 3"),
        PetResourceRequirement(fileName: "pet-walk-4", displayName: "走路 4"),
        PetResourceRequirement(fileName: "pet-lie", displayName: "趴下"),
        PetResourceRequirement(fileName: "pet-sleep", displayName: "睡觉"),
        PetResourceRequirement(fileName: "pet-eat", displayName: "吃饭"),
        PetResourceRequirement(fileName: "pet-cuddle", displayName: "撒娇")
    ]
    static let requiredImageNames = requiredImages.map(\.fileName)

    static func displayName(for fileName: String) -> String {
        requiredImages.first(where: { $0.fileName == fileName })?.displayName ?? fileName
    }

    static func validatedPetName(_ name: String) -> Result<String, PetNameValidationError> {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.empty)
        }
        guard name != ".", name != ".." else {
            return .failure(.reservedPathComponent)
        }
        guard name != PetMetadata.defaultSimba.slug else {
            return .failure(.reservedDefaultPet)
        }
        guard !name.contains("/"), !name.contains("\\") else {
            return .failure(.containsPathSeparator)
        }
        guard !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return .failure(.containsControlCharacter)
        }
        return .success(name)
    }
}

struct PetResourceRequirement {
    let fileName: String
    let displayName: String
}

enum PetNameValidationError: LocalizedError {
    case empty
    case reservedPathComponent
    case reservedDefaultPet
    case containsPathSeparator
    case containsControlCharacter

    var errorDescription: String? {
        switch self {
        case .empty:
            return "请输入宠物名称。"
        case .reservedPathComponent:
            return "宠物名称不能是“.”或“..”。"
        case .reservedDefaultPet:
            return "“simba”是默认宠物名称，请使用其他名称。"
        case .containsPathSeparator:
            return "宠物名称不能包含“/”或“\\”。"
        case .containsControlCharacter:
            return "宠物名称不能包含换行符或其他控制字符。"
        }
    }
}
