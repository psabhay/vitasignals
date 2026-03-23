import Foundation
import HealthKit
import SwiftData
import Combine

// MARK: - HealthSyncManager (UI layer — @MainActor)
//
// Only @Published properties and the public API live here.
// All heavy work (HealthKit queries, SwiftData inserts) runs on
// a background ModelContext via SyncWorker to keep the UI responsive.

@MainActor
final class HealthSyncManager: ObservableObject {
    @Published var isSyncing = false
    @Published var syncProgress: String = ""
    @Published var availableMetrics: Set<String> = []
    @Published var lastSyncDate: Date?
    @Published var permissionDenied = false

    private let store = HKHealthStore()
    private let worker = SyncWorker()

    private static let lastSyncKey = "lastSyncDate"

    init() {
        let stored = UserDefaults.standard.double(forKey: Self.lastSyncKey)
        if stored > 0 {
            lastSyncDate = Date(timeIntervalSince1970: stored)
        }
    }

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Authorization

    private static let allReadTypes: Set<HKObjectType> = {
        var types = Set<HKObjectType>()
        for identifier in HealthKitCatalog.allIdentifiers {
            types.insert(HKQuantityType(identifier))
        }
        types.insert(HKQuantityType(.bloodPressureSystolic))
        types.insert(HKQuantityType(.bloodPressureDiastolic))
        types.insert(HKQuantityType(.heartRate))
        types.insert(HKCategoryType(.sleepAnalysis))
        types.insert(HKSampleType.workoutType())
        return types
    }()

    func requestAuthorization() async {
        guard Self.isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: Self.allReadTypes)
        } catch {
            #if DEBUG
            print("HealthKit auth error: \(error)")
            #endif
        }
    }

    // MARK: - Discovery + Sync

    func syncAll(container: ModelContainer, dataStore: HealthDataStore) async {
        guard Self.isAvailable, !isSyncing else { return }
        isSyncing = true
        syncProgress = "Requesting authorization..."

        await requestAuthorization()

        syncProgress = "Discovering metrics..."
        let discovered = await worker.discoverAvailableMetrics(store: store)
        availableMetrics = discovered

        // Check actual authorization status — empty discovery may just mean no data
        let authStatus = store.authorizationStatus(for: HKQuantityType(.heartRate))
        if discovered.isEmpty && authStatus == .sharingDenied {
            permissionDenied = true
            syncProgress = ""
            isSyncing = false
            return
        }
        permissionDenied = (authStatus == .sharingDenied)

        if discovered.isEmpty {
            syncProgress = ""
            isSyncing = false
            lastSyncDate = .now
            return
        }

        // Build list of quantity defs to sync
        let quantityDefs = discovered.compactMap { type -> MetricDefinition? in
            guard type != MetricType.bloodPressure && type != MetricType.sleepDuration else { return nil }
            return MetricRegistry.definition(for: type)
        }.filter { $0.hkQuantityType != nil }

        let total = quantityDefs.count
            + (discovered.contains(MetricType.bloodPressure) ? 1 : 0)
            + (discovered.contains(MetricType.sleepDuration) ? 1 : 0)

        syncProgress = "Syncing \(total) metrics..."

        // Sync everything in parallel — quantity metrics, BP, and sleep all at once
        let hasBP = discovered.contains(MetricType.bloodPressure)
        let hasSleep = discovered.contains(MetricType.sleepDuration)

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.worker.syncMetricsBatched(quantityDefs, store: self.store, container: container)
            }
            if hasBP {
                group.addTask {
                    await self.worker.syncBloodPressure(store: self.store, container: container)
                }
            }
            if hasSleep {
                group.addTask {
                    await self.worker.syncSleep(store: self.store, container: container)
                }
            }
            await group.waitForAll()
        }

        // Refresh the shared data store once — all views update from this single source
        syncProgress = "Updating..."
        dataStore.refresh()

        lastSyncDate = .now
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: Self.lastSyncKey)
        syncProgress = ""
        isSyncing = false
    }
}

// MARK: - SyncWorker (background — NOT @MainActor)
//
// All HealthKit fetching and SwiftData operations happen here,
// on a background ModelContext that does NOT trigger SwiftUI @Query updates
// until saved. Each method creates its own context so work is fully off main thread.

private final class SyncWorker: Sendable {
    private let overlapInterval: TimeInterval = 3600

    // MARK: - Discovery

    func discoverAvailableMetrics(store: HKHealthStore) async -> Set<String> {
        await withTaskGroup(of: String?.self) { group in
            for entry in HealthKitCatalog.entries {
                let identifier = entry.identifier
                let metricType = entry.metricType
                group.addTask {
                    let has = await Self.hasData(store: store, sampleType: HKQuantityType(identifier))
                    return has ? metricType : nil
                }
            }

            group.addTask {
                let has = await Self.hasData(store: store, sampleType: HKCorrelationType(.bloodPressure))
                return has ? MetricType.bloodPressure : nil
            }

            group.addTask {
                let has = await Self.hasData(store: store, sampleType: HKCategoryType(.sleepAnalysis))
                return has ? MetricType.sleepDuration : nil
            }

            var results = Set<String>()
            for await metricType in group {
                if let type = metricType { results.insert(type) }
            }
            return results
        }
    }

    private static func hasData(store: HKHealthStore, sampleType: HKSampleType) async -> Bool {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, results, _ in
                continuation.resume(returning: (results?.count ?? 0) > 0)
            }
            store.execute(query)
        }
    }

    // MARK: - Quantity Metric Sync

    /// Maximum samples to fetch per metric type per sync
    private let sampleFetchLimit = 500

    /// Sync multiple metrics in parallel with controlled concurrency
    func syncMetricsBatched(_ defs: [MetricDefinition], store: HKHealthStore, container: ModelContainer) async {
        // Process metrics in parallel with concurrency limit of 6
        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0
            let maxConcurrency = 10

            for def in defs {
                // Wait if we've hit concurrency limit
                if inFlight >= maxConcurrency {
                    await group.next()
                    inFlight -= 1
                }

                group.addTask {
                    // Each task gets its own context for thread safety
                    let context = ModelContext(container)
                    context.autosaveEnabled = false
                    await self.syncMetric(def, store: store, context: context)
                    try? context.save()
                }
                inFlight += 1
            }

            // Wait for remaining tasks
            await group.waitForAll()
        }
    }

    func syncMetric(_ def: MetricDefinition, store: HKHealthStore, context: ModelContext) async {
        guard let hkType = def.hkQuantityType, let hkUnit = def.hkUnit?() else { return }

        let syncState = getOrCreateSyncState(for: def.type, context: context)
        let lastSync = syncState.lastSyncDate
        let endDate = Date.now

        // First sync: fetch 1 year, no overlap check needed
        // Incremental sync: fetch from lastSync - overlap, check UUIDs only in overlap window
        let isFirstSync = lastSync == nil
        let startDate = lastSync.map {
            $0.addingTimeInterval(-overlapInterval)
        } ?? Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now

        if def.isCumulative {
            // Cumulative metrics: check by day, no UUID needed
            let dailyValues = await Self.fetchDailyStatistics(store: store, hkType, unit: hkUnit, from: startDate, to: endDate)
            for dv in dailyValues {
                let dayStart = Calendar.current.startOfDay(for: dv.date)
                let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
                let existing = existingRecords(for: def.type, from: dayStart, to: dayEnd, context: context)
                if let existingRecord = existing.first(where: { !$0.isManualEntry }) {
                    if existingRecord.primaryValue != dv.value {
                        existingRecord.primaryValue = dv.value
                    }
                } else if existing.isEmpty {
                    context.insert(HealthRecord(
                        metricType: def.type, timestamp: dv.date,
                        primaryValue: dv.value, source: "Apple Health", isManualEntry: false
                    ))
                }
            }
        } else {
            let samples = await Self.fetchQuantitySamples(store: store, hkType, unit: hkUnit, from: startDate, to: endDate, limit: sampleFetchLimit)

            // Only fetch existing UUIDs if we have an overlap window to check
            let excludedUUIDs: Set<String>
            if isFirstSync {
                // First sync: only check dismissed records (user explicitly rejected)
                excludedUUIDs = dismissedHealthKitUUIDs(for: def.type, context: context)
            } else {
                // Incremental: only check UUIDs in the overlap window (lastSync - 1hr to lastSync)
                guard let syncDate = lastSync else { return }
                excludedUUIDs = existingHealthKitUUIDs(for: def.type, from: startDate, to: syncDate, context: context)
                    .union(dismissedHealthKitUUIDs(for: def.type, context: context))
            }

            for sample in samples {
                // Skip if already imported or dismissed
                guard !excludedUUIDs.contains(sample.uuid) else { continue }
                var value = sample.value
                if hkUnit == HKUnit.percent() { value *= 100 }
                context.insert(HealthRecord(
                    metricType: def.type, timestamp: sample.date,
                    primaryValue: value, healthKitUUID: sample.uuid,
                    source: sample.source, isManualEntry: false
                ))
            }
        }

        syncState.lastSyncDate = endDate
        syncState.isAvailable = true
    }

    // MARK: - Blood Pressure Sync

    func syncBloodPressure(store: HKHealthStore, container: ModelContainer) async {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let syncState = getOrCreateSyncState(for: MetricType.bloodPressure, context: context)
        let lastSync = syncState.lastSyncDate
        let endDate = Date.now
        let isFirstSync = lastSync == nil
        let startDate = lastSync.map {
            $0.addingTimeInterval(-overlapInterval)
        } ?? Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now

        let bpType = HKCorrelationType(.bloodPressure)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples: [HKCorrelation] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bpType, predicate: predicate,
                limit: sampleFetchLimit, sortDescriptors: [sortDescriptor]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKCorrelation]) ?? [])
            }
            store.execute(query)
        }

        guard !samples.isEmpty else {
            syncState.lastSyncDate = endDate
            syncState.isAvailable = true
            try? context.save()
            return
        }

        // Only check UUIDs in overlap window (not all records)
        let excludedUUIDs: Set<String>
        if isFirstSync {
            excludedUUIDs = dismissedHealthKitUUIDs(for: MetricType.bloodPressure, context: context)
        } else {
            guard let syncDate = lastSync else { return }
            excludedUUIDs = existingHealthKitUUIDs(for: MetricType.bloodPressure, from: startDate, to: syncDate, context: context)
                .union(dismissedHealthKitUUIDs(for: MetricType.bloodPressure, context: context))
        }

        // Fetch heart rates only for the actual BP sample time window
        let bpDates = samples.map(\.startDate)
        let hrStart = bpDates.min() ?? startDate
        let hrEnd = bpDates.max() ?? endDate
        let heartRates = await Self.fetchHeartRates(store: store, since: hrStart, until: hrEnd, limit: samples.count * 2)

        for sample in samples {
            let uuid = sample.uuid.uuidString
            guard !excludedUUIDs.contains(uuid) else { continue }

            guard let sysSample = sample.objects(for: HKQuantityType(.bloodPressureSystolic)).first as? HKQuantitySample,
                  let diaSample = sample.objects(for: HKQuantityType(.bloodPressureDiastolic)).first as? HKQuantitySample else {
                continue
            }

            let mmHg = HKUnit.millimeterOfMercury()
            let systolic = sysSample.quantity.doubleValue(for: mmHg)
            let diastolic = diaSample.quantity.doubleValue(for: mmHg)
            let pulse = Self.findClosestHeartRate(to: sample.startDate, in: heartRates)
            let source = sample.sourceRevision.source.name

            context.insert(HealthRecord(
                metricType: MetricType.bloodPressure,
                timestamp: sample.startDate,
                primaryValue: systolic, secondaryValue: diastolic,
                tertiaryValue: pulse.map { Double($0) },
                healthKitUUID: uuid, source: source, isManualEntry: false,
                activityContext: ActivityContext.atRest.rawValue,
                notes: "Imported from Apple Health (via \(source))"
            ))
        }

        syncState.lastSyncDate = endDate
        syncState.isAvailable = true
        try? context.save()
    }

    // MARK: - Sleep Sync

    func syncSleep(store: HKHealthStore, container: ModelContainer) async {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let syncState = getOrCreateSyncState(for: MetricType.sleepDuration, context: context)
        let startDate = syncState.lastSyncDate.map {
            $0.addingTimeInterval(-overlapInterval)
        } ?? Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now
        let endDate = Date.now

        let sleepType = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        // Sleep samples are aggregated per day, so we can fetch more
        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType, predicate: predicate,
                limit: 2000, sortDescriptors: [sortDescriptor]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        let calendar = Calendar.current
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        ]

        var dayDurations: [DateComponents: TimeInterval] = [:]
        for sample in samples {
            guard asleepValues.contains(sample.value) else { continue }
            let duration = sample.endDate.timeIntervalSince(sample.startDate)
            let components = calendar.dateComponents([.year, .month, .day], from: sample.startDate)
            dayDurations[components, default: 0] += duration
        }

        for (components, duration) in dayDurations {
            guard let date = calendar.date(from: components) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let existing = existingRecords(for: MetricType.sleepDuration, from: dayStart, to: dayEnd, context: context)
            if let existingRecord = existing.first(where: { !$0.isManualEntry }) {
                let newHours = duration / 3600
                if abs(existingRecord.primaryValue - newHours) > 0.01 {
                    existingRecord.primaryValue = newHours
                    existingRecord.durationSeconds = duration
                }
            } else if existing.isEmpty {
                context.insert(HealthRecord(
                    metricType: MetricType.sleepDuration,
                    timestamp: date, primaryValue: duration / 3600,
                    durationSeconds: duration, source: "Apple Health", isManualEntry: false
                ))
            }
        }

        syncState.lastSyncDate = endDate
        syncState.isAvailable = true
        try? context.save()
    }

    // MARK: - HealthKit Query Helpers

    private struct SampleResult {
        let date: Date
        let value: Double
        let source: String
        let uuid: String
    }

    private struct DailyValue {
        let date: Date
        let value: Double
    }

    private static func fetchQuantitySamples(
        store: HKHealthStore,
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from startDate: Date,
        to endDate: Date,
        limit: Int
    ) async -> [SampleResult] {
        let quantityType = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType, predicate: predicate,
                limit: limit, sortDescriptors: [sortDescriptor]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }

        return samples.map { sample in
            SampleResult(
                date: sample.startDate,
                value: sample.quantity.doubleValue(for: unit),
                source: sample.sourceRevision.source.name,
                uuid: sample.uuid.uuidString
            )
        }
    }

    private static func fetchDailyStatistics(
        store: HKHealthStore,
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from startDate: Date,
        to endDate: Date
    ) async -> [DailyValue] {
        let quantityType = HKQuantityType(identifier)
        let calendar = Calendar.current
        let anchorDate = calendar.startOfDay(for: startDate)
        let interval = DateComponents(day: 1)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, _ in
                guard let statsCollection = results else {
                    continuation.resume(returning: [])
                    return
                }
                var values: [DailyValue] = []
                statsCollection.enumerateStatistics(from: anchorDate, to: endDate) { statistics, _ in
                    if let sum = statistics.sumQuantity() {
                        values.append(DailyValue(date: statistics.startDate, value: sum.doubleValue(for: unit)))
                    }
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    private static func fetchHeartRates(store: HKHealthStore, since startDate: Date, until endDate: Date, limit: Int) async -> [(Date, Int)] {
        let hrType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrType, predicate: predicate,
                limit: limit, sortDescriptors: [sortDescriptor]
            ) { _, results, _ in
                let rates: [(Date, Int)] = (results as? [HKQuantitySample])?.map { sample in
                    let bpm = Int(sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
                    return (sample.startDate, bpm)
                } ?? []
                continuation.resume(returning: rates)
            }
            store.execute(query)
        }
    }

    private static func findClosestHeartRate(to date: Date, in rates: [(Date, Int)]) -> Int? {
        let maxInterval: TimeInterval = 5 * 60
        var closest: (TimeInterval, Int)?
        for (rateDate, bpm) in rates {
            let interval = abs(rateDate.timeIntervalSince(date))
            if interval <= maxInterval {
                if closest == nil || interval < (closest?.0 ?? .infinity) {
                    closest = (interval, bpm)
                }
            }
        }
        return closest?.1
    }

    // MARK: - SwiftData Helpers

    private func getOrCreateSyncState(for metricType: String, context: ModelContext) -> SyncState {
        let descriptor = FetchDescriptor<SyncState>(
            predicate: #Predicate { $0.metricType == metricType }
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let state = SyncState(metricType: metricType)
        context.insert(state)
        return state
    }

    /// Fetch UUIDs only within a specific time window (for overlap checking)
    private func existingHealthKitUUIDs(for metricType: String, from startDate: Date, to endDate: Date, context: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<HealthRecord>(
            predicate: #Predicate {
                $0.metricType == metricType &&
                $0.healthKitUUID != nil &&
                $0.timestamp >= startDate &&
                $0.timestamp < endDate
            }
        )
        let records = (try? context.fetch(descriptor)) ?? []
        return Set(records.compactMap(\.healthKitUUID))
    }

    private func dismissedHealthKitUUIDs(for metricType: String, context: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<DismissedHealthKitRecord>(
            predicate: #Predicate { $0.metricType == metricType }
        )
        let records = (try? context.fetch(descriptor)) ?? []
        return Set(records.map(\.healthKitUUID))
    }

    private func existingRecords(for metricType: String, from startDate: Date, to endDate: Date, context: ModelContext) -> [HealthRecord] {
        let descriptor = FetchDescriptor<HealthRecord>(
            predicate: #Predicate {
                $0.metricType == metricType && $0.timestamp >= startDate && $0.timestamp < endDate
            }
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
