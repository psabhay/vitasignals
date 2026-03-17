import Foundation
import SwiftUI
import SwiftData
import Combine

// MARK: - HealthDataStore
//
// Single shared data layer for all views. Instead of 5+ @Query instances
// each independently loading ALL HealthRecords (causing massive memory
// duplication and cascading re-renders on every save), this observable
// class loads records once and provides pre-computed groupings.
//
// Uses its own ModelContext (main thread) so records are proper managed
// objects. refresh() re-fetches from the persistent store, picking up
// changes made by the background SyncWorker.

@MainActor
final class HealthDataStore: ObservableObject {
    @Published private(set) var allRecords: [HealthRecord] = []
    @Published private(set) var recordsByType: [String: [HealthRecord]] = [:]
    @Published private(set) var availableMetricTypes: Set<String> = []
    @Published private(set) var recordCount: Int = 0

    private var container: ModelContainer?

    func setup(container: ModelContainer) {
        self.container = container
        refresh()
    }

    /// Re-fetch from the persistent store. Call after sync, add, edit, or delete.
    func refresh() {
        guard let container else { return }

        // Create a fresh context each time to pick up background changes
        // (ModelContext.reset() is iOS 18+, so we recreate instead)
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let descriptor = FetchDescriptor<HealthRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let records = (try? context.fetch(descriptor)) ?? []
        let grouped = Dictionary(grouping: records, by: \.metricType)
        let types = Set(grouped.keys)
        let count = records.count

        // Batch all updates to trigger a single SwiftUI render pass
        allRecords = records
        recordsByType = grouped
        availableMetricTypes = types
        recordCount = count
    }

    // MARK: - Convenience accessors

    func records(for metricType: String) -> [HealthRecord] {
        recordsByType[metricType] ?? []
    }

    func recentRecords(for metricType: String, days: Int) -> [HealthRecord] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) else { return [] }
        return records(for: metricType).filter { $0.timestamp >= cutoff }
    }
}
