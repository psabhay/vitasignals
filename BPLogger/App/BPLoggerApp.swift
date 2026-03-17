import SwiftUI
import SwiftData

@main
struct BPLoggerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            HealthRecord.self,
            DismissedHealthKitRecord.self,
            UserProfile.self,
            SyncState.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // If migration fails, delete the store and retry
            let url = config.url
            print("⚠️ ModelContainer creation failed: \(error). Deleting store at \(url) and retrying.")
            try? FileManager.default.removeItem(at: url)
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    @StateObject private var dataStore = HealthDataStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataStore)
                .onAppear {
                    dataStore.setup(container: sharedModelContainer)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
