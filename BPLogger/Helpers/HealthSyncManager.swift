import Foundation
import HealthKit
import SwiftData
import Combine

@MainActor
final class HealthSyncManager: ObservableObject {
    @Published var isSyncing = false
    @Published var syncProgress: String = ""
    @Published var availableMetrics: Set<String> = []
    @Published var lastSyncDate: Date?

    private let store = HKHealthStore()
    private let overlapInterval: TimeInterval = 3600 // 1 hour overlap for dedup

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Authorization

    private var allReadTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        types.insert(HKQuantityType(.bloodPressureSystolic))
        types.insert(HKQuantityType(.bloodPressureDiastolic))
        types.insert(HKQuantityType(.heartRate))
        types.insert(HKQuantityType(.restingHeartRate))
        types.insert(HKQuantityType(.heartRateVariabilitySDNN))
        types.insert(HKQuantityType(.vo2Max))
        types.insert(HKQuantityType(.walkingHeartRateAverage))
        types.insert(HKQuantityType(.stepCount))
        types.insert(HKQuantityType(.appleExerciseTime))
        types.insert(HKQuantityType(.activeEnergyBurned))
        types.insert(HKQuantityType(.bodyMass))
        types.insert(HKQuantityType(.respiratoryRate))
        types.insert(HKQuantityType(.oxygenSaturation))
        types.insert(HKCategoryType(.sleepAnalysis))
        types.insert(HKSampleType.workoutType())
        return types
    }

    func requestAuthorization() async {
        guard Self.isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: allReadTypes)
        } catch {
            print("HealthKit auth error: \(error)")
        }
    }

    // MARK: - Discovery + Sync

    func syncAll(context: ModelContext) async {
        guard Self.isAvailable else { return }
        isSyncing = true
        syncProgress = "Checking available data..."

        await requestAuthorization()

        // Discovery: check which metrics have data
        await discoverAvailableMetrics()

        // Incremental sync for each available metric
        let metricsToSync = MetricRegistry.syncableMetrics.filter { availableMetrics.contains($0.type) }

        for (index, def) in metricsToSync.enumerated() {
            syncProgress = "Syncing \(def.name)... (\(index + 1)/\(metricsToSync.count))"
            await syncMetric(def, context: context)
        }

        // Also sync blood pressure (special case - correlation query)
        if availableMetrics.contains(MetricType.bloodPressure) {
            syncProgress = "Syncing Blood Pressure..."
            await syncBloodPressure(context: context)
        }

        lastSyncDate = .now
        syncProgress = ""
        isSyncing = false
    }

    // MARK: - Discovery

    private func discoverAvailableMetrics() async {
        var available = Set<String>()

        // Check quantity types
        for def in MetricRegistry.syncableMetrics {
            guard let hkType = def.hkQuantityType else { continue }
            let quantityType = HKQuantityType(hkType)
            if await hasData(for: quantityType) {
                available.insert(def.type)
            }
        }

        // Check BP
        let bpType = HKCorrelationType(.bloodPressure)
        if await hasCorrelationData(for: bpType) {
            available.insert(MetricType.bloodPressure)
        }

        // Check sleep
        let sleepType = HKCategoryType(.sleepAnalysis)
        if await hasCategoryData(for: sleepType) {
            available.insert(MetricType.sleepDuration)
        }

        availableMetrics = available
    }

    private func hasData(for sampleType: HKSampleType) async -> Bool {
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

    private func hasCorrelationData(for type: HKCorrelationType) async -> Bool {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, results, _ in
                continuation.resume(returning: (results?.count ?? 0) > 0)
            }
            store.execute(query)
        }
    }

    private func hasCategoryData(for type: HKCategoryType) async -> Bool {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, results, _ in
                continuation.resume(returning: (results?.count ?? 0) > 0)
            }
            store.execute(query)
        }
    }

    // MARK: - Incremental Sync for Quantity Metrics

    private func syncMetric(_ def: MetricDefinition, context: ModelContext) async {
        guard let hkType = def.hkQuantityType, let hkUnit = def.hkUnit?() else { return }

        // Get last sync date for this metric
        let syncState = getOrCreateSyncState(for: def.type, context: context)
        let startDate = syncState.lastSyncDate.map {
            $0.addingTimeInterval(-overlapInterval)
        } ?? Calendar.current.date(byAdding: .year, value: -1, to: .now)!
        let endDate = Date.now

        // Get existing UUIDs + dismissed UUIDs for dedup
        let existingUUIDs = existingHealthKitUUIDs(for: def.type, context: context)
        let dismissedUUIDs = dismissedHealthKitUUIDs(for: def.type, context: context)
        let excludedUUIDs = existingUUIDs.union(dismissedUUIDs)

        if def.isCumulative {
            // Cumulative metrics: daily sums
            let dailyValues = await fetchDailyStatistics(hkType, unit: hkUnit, from: startDate, to: endDate)
            for dv in dailyValues {
                // Check if we already have a record for this day
                let dayStart = Calendar.current.startOfDay(for: dv.date)
                let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
                let existing = existingRecords(for: def.type, from: dayStart, to: dayEnd, context: context)
                if existing.isEmpty {
                    let record = HealthRecord(
                        metricType: def.type,
                        timestamp: dv.date,
                        primaryValue: dv.value,
                        source: "Apple Health",
                        isManualEntry: false
                    )
                    context.insert(record)
                }
            }
        } else {
            // Discrete metrics: individual samples
            let samples = await fetchQuantitySamples(hkType, unit: hkUnit, from: startDate, to: endDate)
            for sample in samples {
                let uuid = sample.uuid
                guard !excludedUUIDs.contains(uuid) else { continue }

                var value = sample.value
                // SpO2 comes as 0-1, convert to 0-100
                if def.type == MetricType.oxygenSaturation {
                    value *= 100
                }

                let record = HealthRecord(
                    metricType: def.type,
                    timestamp: sample.date,
                    primaryValue: value,
                    healthKitUUID: uuid,
                    source: sample.source,
                    isManualEntry: false
                )
                context.insert(record)
            }
        }

        // Update sync state
        syncState.lastSyncDate = endDate
        syncState.isAvailable = true
    }

    // MARK: - Blood Pressure Sync (Special Case)

    private func syncBloodPressure(context: ModelContext) async {
        let syncState = getOrCreateSyncState(for: MetricType.bloodPressure, context: context)
        let startDate = syncState.lastSyncDate.map {
            $0.addingTimeInterval(-overlapInterval)
        } ?? Calendar.current.date(byAdding: .year, value: -1, to: .now)!
        let endDate = Date.now

        let existingUUIDs = existingHealthKitUUIDs(for: MetricType.bloodPressure, context: context)
        let dismissedUUIDs = dismissedHealthKitUUIDs(for: MetricType.bloodPressure, context: context)
        let excludedUUIDs = existingUUIDs.union(dismissedUUIDs)

        let bpType = HKCorrelationType(.bloodPressure)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples: [HKCorrelation] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bpType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKCorrelation]) ?? [])
            }
            store.execute(query)
        }

        let heartRates = await fetchHeartRates(since: startDate)

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
            let pulse = findClosestHeartRate(to: sample.startDate, in: heartRates)
            let source = sample.sourceRevision.source.name

            let record = HealthRecord(
                metricType: MetricType.bloodPressure,
                timestamp: sample.startDate,
                primaryValue: systolic,
                secondaryValue: diastolic,
                tertiaryValue: pulse.map { Double($0) },
                healthKitUUID: uuid,
                source: source,
                isManualEntry: false,
                activityContext: ActivityContext.atRest.rawValue,
                notes: "Imported from Apple Health (via \(source))"
            )
            context.insert(record)
        }

        syncState.lastSyncDate = endDate
        syncState.isAvailable = true
    }

    // MARK: - Sleep Sync

    private func syncSleep(context: ModelContext) async {
        let syncState = getOrCreateSyncState(for: MetricType.sleepDuration, context: context)
        let startDate = syncState.lastSyncDate.map {
            $0.addingTimeInterval(-overlapInterval)
        } ?? Calendar.current.date(byAdding: .year, value: -1, to: .now)!
        let endDate = Date.now

        let sleepType = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
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
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            let existing = existingRecords(for: MetricType.sleepDuration, from: dayStart, to: dayEnd, context: context)
            if existing.isEmpty {
                let hours = duration / 3600
                let record = HealthRecord(
                    metricType: MetricType.sleepDuration,
                    timestamp: date,
                    primaryValue: hours,
                    durationSeconds: duration,
                    source: "Apple Health",
                    isManualEntry: false
                )
                context.insert(record)
            }
        }

        syncState.lastSyncDate = endDate
        syncState.isAvailable = true
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

    private func fetchQuantitySamples(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from startDate: Date,
        to endDate: Date
    ) async -> [SampleResult] {
        let quantityType = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
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

    private func fetchDailyStatistics(
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

    private func fetchHeartRates(since: Date) async -> [(Date, Int)] {
        let hrType = HKQuantityType(.heartRate)
        let endDate = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let predicate = HKQuery.predicateForSamples(withStart: since, end: endDate, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
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

    private func findClosestHeartRate(to date: Date, in rates: [(Date, Int)]) -> Int? {
        let maxInterval: TimeInterval = 5 * 60
        var closest: (TimeInterval, Int)?
        for (rateDate, bpm) in rates {
            let interval = abs(rateDate.timeIntervalSince(date))
            if interval <= maxInterval {
                if closest == nil || interval < closest!.0 {
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

    private func existingHealthKitUUIDs(for metricType: String, context: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<HealthRecord>(
            predicate: #Predicate { $0.metricType == metricType && $0.healthKitUUID != nil }
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
