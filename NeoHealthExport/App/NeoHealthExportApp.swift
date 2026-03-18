import SwiftUI
import SwiftData

@main
struct NeoHealthExportApp: App {
    @State private var showDataLossAlert = false

    var sharedModelContainer: ModelContainer? = {
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
            let url = config.url
            #if DEBUG
            print("⚠️ ModelContainer creation failed: \(error). Deleting store at \(url) and retrying.")
            #endif
            try? FileManager.default.removeItem(at: url)
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                #if DEBUG
                print("❌ ModelContainer creation failed after retry: \(error)")
                #endif
                return nil
            }
        }
    }()

    @StateObject private var dataStore = HealthDataStore()

    var body: some Scene {
        WindowGroup {
            if let container = sharedModelContainer {
                ContentView()
                    .environmentObject(dataStore)
                    .onAppear {
                        dataStore.setup(container: container)
                    }
                    .modelContainer(container)
                    .alert("Data Reset Required", isPresented: $showDataLossAlert) {
                        Button("OK") {}
                    } message: {
                        Text("The app's database was incompatible and had to be reset. Your previously stored data has been removed. Health data can be re-imported from Apple Health by syncing again.")
                    }
            } else {
                DatabaseErrorView()
            }
        }
    }
}

/// Shown when the SwiftData store cannot be created or recovered.
private struct DatabaseErrorView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.red)
            Text("Unable to Load Data")
                .font(.title2.bold())
            Text("The app's database could not be initialized. This may be caused by a corrupted data store.\n\nPlease try restarting the app. If the problem persists, reinstall the app.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .padding()
    }
}
