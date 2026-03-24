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
    private(set) var recordsByType: [String: [HealthRecord]] = [:]
    private(set) var availableMetricTypes: Set<String> = []
    private(set) var recordCount: Int = 0
    private(set) var allRecords: [HealthRecord] = []

    private var container: ModelContainer?
    private var context: ModelContext?

    func setup(container: ModelContainer) {
        self.container = container
        self.context = ModelContext(container)
        self.context?.autosaveEnabled = false
        loadCustomMetrics()
        refresh()
    }

    /// Re-fetch from the persistent store. Call after sync, add, edit, or delete.
    func refresh() {
        guard let container else { return }

        // Recreate context to pick up background changes
        // (ModelContext.reset() is iOS 18+, so we recreate instead)
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        self.context = ctx

        var descriptor = FetchDescriptor<HealthRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 5000

        let records = (try? ctx.fetch(descriptor)) ?? []
        let grouped = Dictionary(grouping: records, by: \.metricType)

        // Single objectWillChange to batch all property updates into one render pass
        objectWillChange.send()
        recordsByType = grouped
        availableMetricTypes = Set(grouped.keys)
        recordCount = records.count
        allRecords = records
    }

    // MARK: - Convenience accessors

    func records(for metricType: String) -> [HealthRecord] {
        recordsByType[metricType] ?? []
    }

    func recentRecords(for metricType: String, days: Int) -> [HealthRecord] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) else { return [] }
        return records(for: metricType).filter { $0.timestamp >= cutoff }
    }

    // MARK: - Custom Metrics

    private func loadCustomMetrics() {
        guard let context else { return }
        let customs = (try? context.fetch(FetchDescriptor<CustomMetric>())) ?? []
        for custom in customs {
            MetricRegistry.registerCustomMetric(custom.toMetricDefinition())
        }
    }

    /// Count-only query for a date range — avoids loading full objects.
    func fetchRecordCount(from startDate: Date, to endDate: Date) -> Int {
        guard let context else { return 0 }
        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate)) ?? endDate
        var descriptor = FetchDescriptor<HealthRecord>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end }
        )
        descriptor.fetchLimit = 10000
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Targeted fetch for report generation — fetches only records in the given date range.
    func fetchRecords(from startDate: Date, to endDate: Date, metricTypes: Set<String>? = nil) -> [HealthRecord] {
        guard let context else { return [] }

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
