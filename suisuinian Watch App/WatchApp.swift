import SwiftUI

@main
struct WatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .task {
                    // .task runs on @MainActor — safe to access the shared singleton here
                    _ = WatchConnectivityManager.shared
                    print("✅ WatchConnectivityManager initialized on Watch")
                }
        }
    }
}
