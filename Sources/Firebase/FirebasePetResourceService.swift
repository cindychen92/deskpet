import Foundation
import FirebaseAuth

final class FirebasePetResourceService {
    func configureIfNeeded() {
        FirebaseConfiguration.configureIfNeeded()
    }

    func authenticateAndLoadResources(into presenter: PetResourcePresenting) {
        guard FirebaseConfiguration.isConfigured else {
            NSLog("Firebase is not configured; skipping remote pet resources.")
            return
        }

        if Auth.auth().currentUser != nil {
            presenter.loadRemoteResources()
            return
        }

        Auth.auth().signInAnonymously { [weak presenter] _, error in
            if let error {
                let nsError = error as NSError
                NSLog(
                    "Firebase anonymous sign-in failed: domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription) userInfo=\(nsError.userInfo)"
                )
                DispatchQueue.main.async {
                    presenter?.say("云端资源暂时不可用。")
                }
                return
            }
            DispatchQueue.main.async {
                presenter?.loadRemoteResources()
            }
        }
    }
}
