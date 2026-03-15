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

        // Try to fetch old BPReading data from the store using raw queries
        // Since we're replacing the schema entirely, we use a separate container
        // to read old data before the new schema takes over.
        //
        // Because SwiftData doesn't support reading models no longer in the schema,
        // we rely on the app entry point to perform migration BEFORE changing the schema.
        // The actual migration is handled in BPLoggerApp.swift using the old schema first.

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    /// Called from BPLoggerApp when old-schema container is still available.
    /// Reads BPReading objects and creates HealthRecord equivalents.
    static func performMigration(
        oldReadings: [(systolic: Int, diastolic: Int, pulse: Int, timestamp: Date, activityContext: String, notes: String, healthKitID: String?)],
        oldDismissedIDs: [String],
        into context: ModelContext
    ) {
        for r in oldReadings {
            let record = HealthRecord(
                metricType: MetricType.bloodPressure,
                timestamp: r.timestamp,
                primaryValue: Double(r.systolic),
                secondaryValue: Double(r.diastolic),
                tertiaryValue: Double(r.pulse),
                healthKitUUID: r.healthKitID,
                source: r.healthKitID != nil ? "Apple Health" : "manual",
                isManualEntry: r.healthKitID == nil,
                activityContext: r.activityContext,
                notes: r.notes
            )
            context.insert(record)
        }

        for hkID in oldDismissedIDs {
            let dismissed = DismissedHealthKitRecord(
                metricType: MetricType.bloodPressure,
                healthKitUUID: hkID
            )
            context.insert(dismissed)
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }
}
