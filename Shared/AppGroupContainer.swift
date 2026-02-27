import Foundation

/// Single source of truth for where recordings are stored.
/// - In the Simulator: uses a shared /tmp path accessible by both iPhone and Watch simulator processes.
/// - On a real device: uses the App Group shared container (requires `group.rollin.suisuinian` entitlement).
enum AppGroupContainer {
    static let groupIdentifier = "group.rollin.suisuinian"

    static var recordingsURL: URL {
        #if targetEnvironment(simulator)
        // Both iPhone Simulator and Watch Simulator can read/write /tmp on the Mac host.
        let shared = URL(fileURLWithPath: "/tmp/suisuinian-recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        return shared
        #else
        // Real device: use the App Group shared container.
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) {
            let recordings = groupURL.appendingPathComponent("Recordings", isDirectory: true)
            try? FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
            return recordings
        }
        // Fallback
        print("⚠️ App Group container unavailable — using app Documents")
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #endif
    }
}
