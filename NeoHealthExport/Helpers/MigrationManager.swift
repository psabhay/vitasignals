import Foundation
import SwiftData

struct MigrationManager {
    private static let migrationKey = "v2_migration_complete"

    static var needsMigration: Bool {
        !UserDefaults.standard.bool(forKey: migrationKey)
    }

    @MainActor
    static func migrateIfNeeded(context: ModelContext) {
        guard needsMigration else { return }
        UserDefaults.standard.set(true, forKey: migrationKey)
    }
}
