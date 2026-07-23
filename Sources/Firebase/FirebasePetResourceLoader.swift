import Cocoa
import Foundation
import Network
import FirebaseStorage

final class FirebasePetResourceLoader: PetResourceLoading {
    private final class NetworkAvailability {
        static let shared = NetworkAvailability()

        private let monitor = NWPathMonitor()
        private let queue = DispatchQueue(label: "scrapps.deskpet.network")
        private let lock = NSLock()
        private var status: NWPath.Status?

        var isOffline: Bool {
            lock.lock()
            defer { lock.unlock() }
            return status == .unsatisfied
        }

        private init() {
            monitor.pathUpdateHandler = { [weak self] path in
                self?.lock.lock()
                self?.status = path.status
                self?.lock.unlock()
            }
            monitor.start(queue: queue)
        }
    }

    private let cacheDirectory: URL
    private let remoteDirectory = "resources/simba"
    private let networkAvailability: NetworkAvailability
    private let logLock = NSLock()
    private var lastNetworkFailureLogTime: TimeInterval = 0
    private let networkFailureLogInterval: TimeInterval = 60

    init(fileManager: FileManager = .default) {
        networkAvailability = .shared
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = cachesDirectory.appendingPathComponent("DeskPet/PetResources", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func loadImages(
        named names: [String],
        onImage: @escaping (String, NSImage) -> Void
    ) {
        for name in names {
            loadCachedImage(named: name, onImage: onImage)
        }

        guard !networkAvailability.isOffline else {
            logNetworkFailureIfNeeded("Network is offline; using cached pet resources only.")
            return
        }

        for name in names {
            downloadImage(named: name, onImage: onImage)
        }
    }

    private func loadCachedImage(named name: String, onImage: @escaping (String, NSImage) -> Void) {
        let cacheURL = imageURL(for: name)
        guard let image = NSImage(contentsOf: cacheURL) else { return }
        deliver(image, named: name, onImage: onImage)
    }

    private func downloadImage(named name: String, onImage: @escaping (String, NSImage) -> Void) {
        guard FirebaseConfiguration.isConfigured else {
            NSLog("Firebase is not configured; skipping remote pet resource \(name).")
            return
        }

        let cacheURL = imageURL(for: name)
        let temporaryURL = cacheDirectory.appendingPathComponent("\(name).download.png")
        try? FileManager.default.removeItem(at: temporaryURL)

        Storage.storage()
            .reference()
            .child("\(remoteDirectory)/\(name).png")
            .write(toFile: temporaryURL) { [weak self] url, error in
                guard let self else { return }
                guard error == nil, let url, let image = NSImage(contentsOf: url) else {
                    if let error {
                        if self.isNetworkFailure(error) {
                            self.logNetworkFailureIfNeeded(
                                "Network is unavailable; remote pet resources will retry after connectivity returns."
                            )
                        } else {
                            NSLog("Unable to load remote pet resource \(name): \(error.localizedDescription)")
                        }
                    }
                    return
                }

                do {
                    try self.replaceCachedImage(at: cacheURL, with: url)
                } catch {
                    NSLog("Unable to cache remote pet resource \(name): \(error.localizedDescription)")
                }
                self.deliver(image, named: name, onImage: onImage)
            }
    }

    private func replaceCachedImage(at destinationURL: URL, with temporaryURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }

    private func imageURL(for name: String) -> URL {
        cacheDirectory.appendingPathComponent("\(name).png")
    }

    private func isNetworkFailure(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return [
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorDNSLookupFailed,
                NSURLErrorInternationalRoamingOff,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorTimedOut
            ].contains(nsError.code)
        }

        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isNetworkFailure(underlyingError)
        }

        return false
    }

    private func logNetworkFailureIfNeeded(_ message: String) {
        logLock.lock()
        defer { logLock.unlock() }

        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastNetworkFailureLogTime >= networkFailureLogInterval else { return }
        lastNetworkFailureLogTime = now
        NSLog(message)
    }

    private func deliver(_ image: NSImage, named name: String, onImage: @escaping (String, NSImage) -> Void) {
        DispatchQueue.main.async {
            onImage(name, image)
        }
    }
}
