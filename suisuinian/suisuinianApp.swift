import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct SuisuinianApp: App {
    // Shared container for storing Daily Reports and local Memory Entities temporarily
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            // Add SwiftData models here if you migrate from bare Codable
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    nonisolated init() {}

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    _ = WatchConnectivityManager.shared
                    print("✅ WatchConnectivityManager initialized on iOS")
                }
        }
        // .modelContainer(sharedModelContainer) // Uncomment when SwiftData schema is complete
        .backgroundTask(.appRefresh("com.rollin.suisuinian.audioupload")) {
            // Handle background tasks for audio uploading
            let uploader = BackgroundUploader()
            await uploader.performUpload()
        }
    }
}
