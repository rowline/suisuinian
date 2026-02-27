import Foundation
import WatchConnectivity
import Combine

// Posted by iOS when it successfully saves a file from the Watch
extension Notification.Name {
    static let newWatchRecordingArrived = Notification.Name("newWatchRecordingArrived")
}

/// Handles connecting the iOS and watchOS apps together to pass data locally
class WatchConnectivityManager: NSObject, WCSessionDelegate, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var isSupported: Bool = WCSession.isSupported()
    @Published var isReachable: Bool = false

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Sends a local file URL from watchOS to iOS directly
    func transferAudioFile(file: URL, metadata: [String: Any]?) {
        guard WCSession.default.activationState == .activated else {
            print("WCSession not activated — cannot transfer file.")
            return
        }
        print("Transferring \(file.lastPathComponent) to companion app...")
        WCSession.default.transferFile(file, metadata: metadata)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            print("WCSession activated: \(activationState.rawValue), reachable: \(session.isReachable)")
        }
        #if os(iOS)
        // Copy any files the WCSession already queued while the iOS app was inactive
        scanWCInboxAndCopy()
        #endif
    }

    #if os(iOS)
    /// Check if WCSession has already delivered files into the app's Documents/Inbox and move them.
    private func scanWCInboxAndCopy() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let inbox = docs.appendingPathComponent("Inbox")
        guard let inboxFiles = try? FileManager.default.contentsOfDirectory(
            at: inbox, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return }

        let m4aFiles = inboxFiles.filter { $0.pathExtension.lowercased() == "m4a" }
        guard !m4aFiles.isEmpty else { return }
        print("📦 WC Inbox has \(m4aFiles.count) pending file(s) — copying to Documents...")

        for fileURL in m4aFiles {
            let dest = docs.appendingPathComponent(fileURL.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: fileURL, to: dest)
                print("✅ Moved inbox file: \(fileURL.lastPathComponent)")
            } catch {
                print("❌ Failed to move inbox file: \(error)")
            }
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .newWatchRecordingArrived, object: nil)
        }
    }
    #endif

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if let error = error {
            print("File transfer failed: \(error.localizedDescription)")
        } else {
            print("File transfer completed: \(fileTransfer.file.fileURL.lastPathComponent)")
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    #endif

    /// Triggered on the iPhone when it receives a file from the Apple Watch
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = docs.appendingPathComponent(file.fileURL.lastPathComponent)

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: file.fileURL, to: destinationURL)
            print("✅ Received file from Watch: \(destinationURL.lastPathComponent)")

            // Tell the UI to refresh the list
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .newWatchRecordingArrived, object: destinationURL)
            }

            // Background upload
            Task {
                _ = try? await NetworkManager.shared.uploadAudioFile(at: destinationURL)
            }
        } catch {
            print("❌ Failed to save received file: \(error)")
        }
    }
}
