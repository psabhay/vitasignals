import SwiftUI
import SwiftData

@main
struct BPLoggerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: BPReading.self)
    }
}
