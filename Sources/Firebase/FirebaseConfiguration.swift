import Foundation
import FirebaseCore

enum FirebaseConfiguration {
    private static var didConfigure = false

    static var isConfigured: Bool {
        didConfigure
    }

    @discardableResult
    static func configureIfNeeded() -> Bool {
        guard !didConfigure else { return true }
        guard let configurationURL = Bundle.main.url(
            forResource: "GoogleService-Info",
            withExtension: "plist"
        ) else {
            NSLog("Firebase configuration is missing; remote pet resources are disabled.")
            return false
        }
        guard let options = FirebaseOptions(contentsOfFile: configurationURL.path) else {
            NSLog("Firebase configuration could not be read; remote pet resources are disabled.")
            return false
        }
        FirebaseApp.configure(options: options)
        didConfigure = true
        return true
    }
}
