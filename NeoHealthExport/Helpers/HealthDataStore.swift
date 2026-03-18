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
    @Published private(set) var recordsByType: [String: [HealthRecord]] = [:]
    @Published private(set) var availableMetricTypes: Set<String> = []
    @Published private(set) var recordCount: Int = 0

    private var container: ModelContainer?

    /// Lazily derived from recordsByType — avoids storing a second full copy.
    var allRecords: [HealthRecord] {
        recordsByType.values.flatMap { $0 }.sorted { $0.timestamp > $1.timestamp }
    }

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

        var descriptor = FetchDescriptor<HealthRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 5000

        let records = (try? context.fetch(descriptor)) ?? []
        let grouped = Dictionary(grouping: records, by: \.metricType)

        // Batch all updates to trigger a single SwiftUI render pass
        recordsByType = grouped
        availableMetricTypes = Set(grouped.keys)
        recordCount = records.count
    }

    // MARK: - Convenience accessors

    func records(for metricType: String) -> [HealthRecord] {
        recordsByType[metricType] ?? []
    }

    func recentRecords(for metricType: String, days: Int) -> [HealthRecord] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) else { return [] }
        return records(for: metricType).filter { $0.timestamp >= cutoff }
    }

    /// Targeted fetch for report generation — fetches only records in the given date range.
    /// Uses its own context so it doesn't disturb the main cached data.
    func fetchRecords(from startDate: Date, to endDate: Date, metricTypes: Set<String>? = nil) -> [HealthRecord] {
        guard let container else { return [] }
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate)) ?? endDate

        var descriptor = FetchDescriptor<HealthRecord>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 10000

        let records = (try? context.fetch(descriptor)) ?? []
        if let types = metricTypes {
            return records.filter { types.contains($0.metricType) }
        }
        return records
    }
}
