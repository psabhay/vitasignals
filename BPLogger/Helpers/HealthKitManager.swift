import HealthKit
import SwiftData

struct HealthKitReading: Identifiable {
    let id: String
    let systolic: Int
    let diastolic: Int
    let pulse: Int?
    let timestamp: Date
    let source: String

    var formattedReading: String { "\(systolic)/\(diastolic)" }

    var formattedDate: String {
        timestamp.formatted(date: .abbreviated, time: .shortened)
    }

    var category: BPCategory {
        BPReading.classify(systolic: systolic, diastolic: diastolic)
    }
}

final class HealthKitManager: ObservableObject {
    private let store = HKHealthStore()

    @Published var isAuthorized = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var fetchedReadings: [HealthKitReading] = []

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private var readTypes: Set<HKSampleType> {
        let systolic = HKQuantityType(.bloodPressureSystolic)
        let diastolic = HKQuantityType(.bloodPressureDiastolic)
        let heartRate = HKQuantityType(.heartRate)
        return [systolic, diastolic, heartRate]
    }

    @MainActor
    func requestAuthorization() async {
        guard HealthKitManager.isAvailable else {
            errorMessage = "HealthKit is not available on this device."
            return
        }

        do {
            // Request authorization on background thread to avoid UI hang
            try await store.requestAuthorization(toShare: [], read: readTypes)
            
            // Update UI properties on main thread
            isAuthorized = true
            errorMessage = nil
        } catch {
            errorMessage = "Health access error: \(error.localizedDescription)"
            print("HealthKit auth error: \(error)")
        }
    }

    @MainActor
    func fetchReadings(since: Date, excludedHealthKitIDs: Set<String>) async {
        isLoading = true
        errorMessage = nil
        fetchedReadings = []

        do {
            let bpType = HKCorrelationType(.bloodPressure)
            let endDate = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
            let predicate = HKQuery.predicateForSamples(withStart: since, end: endDate, options: [])
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKCorrelation], Error>) in
                let query = HKSampleQuery(
                    sampleType: bpType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [sortDescriptor]
                ) { _, results, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: results as? [HKCorrelation] ?? [])
                    }
                }
                store.execute(query)
            }

            let heartRates = await fetchHeartRates(since: since)

            var readings: [HealthKitReading] = []
            for sample in samples {
                let hkID = sample.uuid.uuidString
                if excludedHealthKitIDs.contains(hkID) { continue }

                guard let sysSample = sample.objects(for: HKQuantityType(.bloodPressureSystolic)).first as? HKQuantitySample,
                      let diaSample = sample.objects(for: HKQuantityType(.bloodPressureDiastolic)).first as? HKQuantitySample else {
                    continue
                }

                let mmHg = HKUnit.millimeterOfMercury()
                let systolic = Int(sysSample.quantity.doubleValue(for: mmHg))
                let diastolic = Int(diaSample.quantity.doubleValue(for: mmHg))

                let pulse = findClosestHeartRate(to: sample.startDate, in: heartRates)

                let source = sample.sourceRevision.source.name

                readings.append(HealthKitReading(
                    id: hkID,
                    systolic: systolic,
                    diastolic: diastolic,
                    pulse: pulse,
                    timestamp: sample.startDate,
                    source: source
                ))
            }

            fetchedReadings = readings
        } catch {
            errorMessage = "Failed to fetch readings: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func fetchHeartRates(since: Date) async -> [(Date, Int)] {
        let hrType = HKQuantityType(.heartRate)
        let endDate = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let predicate = HKQuery.predicateForSamples(withStart: since, end: endDate, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { (continuation: CheckedContinuation<[(Date, Int)], Never>) in
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
            self.store.execute(query)
        }
    }

    private func findClosestHeartRate(to date: Date, in rates: [(Date, Int)]) -> Int? {
        let maxInterval: TimeInterval = 5 * 60 // within 5 minutes
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

    // MARK: - Expanded Health Context

    private var allReadTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        // BP types (from existing readTypes)
        types.insert(HKQuantityType(.bloodPressureSystolic))
        types.insert(HKQuantityType(.bloodPressureDiastolic))
        types.insert(HKQuantityType(.heartRate))
        // Cardio fitness
        types.insert(HKQuantityType(.restingHeartRate))
        types.insert(HKQuantityType(.heartRateVariabilitySDNN))
        types.insert(HKQuantityType(.vo2Max))
        types.insert(HKQuantityType(.walkingHeartRateAverage))
        // Activity & body
        types.insert(HKQuantityType(.stepCount))
        types.insert(HKQuantityType(.appleExerciseTime))
        types.insert(HKQuantityType(.activeEnergyBurned))
        types.insert(HKQuantityType(.bodyMass))
        // Respiratory & SpO2
        types.insert(HKQuantityType(.respiratoryRate))
        types.insert(HKQuantityType(.oxygenSaturation))
        // Sleep
        types.insert(HKCategoryType(.sleepAnalysis))
        // Workouts
        types.insert(HKSampleType.workoutType())
        return types
    }

    @MainActor
    func requestExpandedAuthorization() async {
        guard HealthKitManager.isAvailable else {
            errorMessage = "HealthKit is not available on this device."
            return
        }

        do {
            try await store.requestAuthorization(toShare: [], read: allReadTypes)
            isAuthorized = true
            errorMessage = nil
        } catch {
            errorMessage = "Health access error: \(error.localizedDescription)"
            print("HealthKit expanded auth error: \(error)")
        }
    }

    func fetchHealthContext(from startDate: Date, to endDate: Date) async -> HealthContext {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let ms = HKUnit.secondUnit(with: .milli)
        let mlkgmin = HKUnit(from: "ml/kg*min")
        let kg = HKUnit.gramUnit(with: .kilo)
        let count = HKUnit.count()
        let min = HKUnit.minute()
        let kcal = HKUnit.kilocalorie()
        let breathsPerMin = HKUnit.count().unitDivided(by: .minute())
        let percent = HKUnit.percent()

        async let restingHR = fetchDailyQuantity(.restingHeartRate, unit: bpm, from: startDate, to: endDate)
        async let hrv = fetchDailyQuantity(.heartRateVariabilitySDNN, unit: ms, from: startDate, to: endDate)
        async let vo2 = fetchDailyQuantity(.vo2Max, unit: mlkgmin, from: startDate, to: endDate)
        async let walkingHR = fetchDailyQuantity(.walkingHeartRateAverage, unit: bpm, from: startDate, to: endDate)
        async let bodyMass = fetchDailyQuantity(.bodyMass, unit: kg, from: startDate, to: endDate)
        async let respRate = fetchDailyQuantity(.respiratoryRate, unit: breathsPerMin, from: startDate, to: endDate)
        async let spo2Raw = fetchDailyQuantity(.oxygenSaturation, unit: percent, from: startDate, to: endDate)

        async let steps = fetchDailyStatistics(.stepCount, unit: count, from: startDate, to: endDate)
        async let exercise = fetchDailyStatistics(.appleExerciseTime, unit: min, from: startDate, to: endDate)
        async let energy = fetchDailyStatistics(.activeEnergyBurned, unit: kcal, from: startDate, to: endDate)

        async let sleep = fetchSleep(from: startDate, to: endDate)
        async let workoutEntries = fetchWorkouts(from: startDate, to: endDate)

        var context = HealthContext()
        context.restingHeartRates = await restingHR
        context.hrvValues = await hrv
        context.vo2MaxValues = await vo2
        context.walkingHeartRates = await walkingHR
        context.bodyMassValues = await bodyMass
        context.respiratoryRates = await respRate
        // Convert SpO2 from 0-1 fraction to 0-100 percentage
        context.oxygenSaturation = await spo2Raw.map {
            HealthContext.DailyValue(date: $0.date, value: $0.value * 100)
        }
        context.stepCounts = await steps
        context.exerciseMinutes = await exercise
        context.activeEnergy = await energy
        context.sleepEntries = await sleep
        context.workouts = await workoutEntries

        return context
    }

    // MARK: - Private Health Context Helpers

    /// Fetches discrete quantity samples, groups by calendar day, and returns the daily average.
    private func fetchDailyQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from startDate: Date,
        to endDate: Date
    ) async -> [HealthContext.DailyValue] {
        let quantityType = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error {
                    print("HealthKit query error for \(identifier.rawValue): \(error.localizedDescription)")
                }
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }

        // Group by calendar day and compute average
        let calendar = Calendar.current
        var dayBuckets: [DateComponents: [Double]] = [:]

        for sample in samples {
            let components = calendar.dateComponents([.year, .month, .day], from: sample.startDate)
            let value = sample.quantity.doubleValue(for: unit)
            dayBuckets[components, default: []].append(value)
        }

        return dayBuckets.compactMap { (components, values) -> HealthContext.DailyValue? in
            guard let date = calendar.date(from: components) else { return nil }
            let avg = values.reduce(0, +) / Double(values.count)
            return HealthContext.DailyValue(date: date, value: avg)
        }
        .sorted { $0.date < $1.date }
    }

    /// Fetches cumulative quantity data using HKStatisticsCollectionQuery for daily sums.
    private func fetchDailyStatistics(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from startDate: Date,
        to endDate: Date
    ) async -> [HealthContext.DailyValue] {
        let quantityType = HKQuantityType(identifier)
        let calendar = Calendar.current

        // Anchor to start of the startDate day
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

            query.initialResultsHandler = { _, results, error in
                if let error {
                    print("HealthKit statistics error for \(identifier.rawValue): \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }

                guard let statsCollection = results else {
                    continuation.resume(returning: [])
                    return
                }

                var values: [HealthContext.DailyValue] = []
                statsCollection.enumerateStatistics(from: anchorDate, to: endDate) { statistics, _ in
                    if let sum = statistics.sumQuantity() {
                        let value = sum.doubleValue(for: unit)
                        values.append(HealthContext.DailyValue(date: statistics.startDate, value: value))
                    }
                }
                continuation.resume(returning: values)
            }

            store.execute(query)
        }
    }

    /// Fetches sleep analysis entries and groups by calendar night, summing asleep durations.
    private func fetchSleep(from startDate: Date, to endDate: Date) async -> [HealthContext.SleepEntry] {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error {
                    print("HealthKit sleep query error: \(error.localizedDescription)")
                }
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        let calendar = Calendar.current

        // Filter to only "asleep" values (iOS 16+)
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        ]

        // Group by calendar day (using the start date of the sleep sample)
        var dayDurations: [DateComponents: TimeInterval] = [:]

        for sample in samples {
            guard asleepValues.contains(sample.value) else { continue }
            let duration = sample.endDate.timeIntervalSince(sample.startDate)
            let components = calendar.dateComponents([.year, .month, .day], from: sample.startDate)
            dayDurations[components, default: 0] += duration
        }

        return dayDurations.compactMap { (components, duration) -> HealthContext.SleepEntry? in
            guard let date = calendar.date(from: components) else { return nil }
            return HealthContext.SleepEntry(date: date, duration: duration)
        }
        .sorted { $0.date < $1.date }
    }

    /// Fetches workouts and extracts activity type name and duration.
    private func fetchWorkouts(from startDate: Date, to endDate: Date) async -> [HealthContext.WorkoutEntry] {
        let workoutType = HKSampleType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error {
                    print("HealthKit workout query error: \(error.localizedDescription)")
                }
                continuation.resume(returning: (results as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }

        return samples.map { workout in
            HealthContext.WorkoutEntry(
                date: workout.startDate,
                type: workout.workoutActivityType.displayName,
                duration: workout.duration
            )
        }
    }
}

// MARK: - HKWorkoutActivityType Display Names

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .walking: return "Walking"
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength Training"
        case .traditionalStrengthTraining: return "Strength Training"
        case .coreTraining: return "Core Training"
        case .highIntensityIntervalTraining: return "HIIT"
        case .elliptical: return "Elliptical"
        case .stairClimbing: return "Stair Climbing"
        case .rowing: return "Rowing"
        case .pilates: return "Pilates"
        case .dance: return "Dance"
        case .cooldown: return "Cooldown"
        case .crossTraining: return "Cross Training"
        case .mixedCardio: return "Mixed Cardio"
        case .jumpRope: return "Jump Rope"
        case .kickboxing: return "Kickboxing"
        case .flexibility: return "Flexibility"
        case .mindAndBody: return "Mind & Body"
        case .tennis: return "Tennis"
        case .tableTennis: return "Table Tennis"
        case .badminton: return "Badminton"
        case .basketball: return "Basketball"
        case .soccer: return "Soccer"
        case .golf: return "Golf"
        case .baseball: return "Baseball"
        case .volleyball: return "Volleyball"
        case .softball: return "Softball"
        case .wrestling: return "Wrestling"
        case .boxing: return "Boxing"
        case .martialArts: return "Martial Arts"
        case .skatingSports: return "Skating"
        case .snowSports: return "Snow Sports"
        case .surfingSports: return "Surfing"
        case .waterSports: return "Water Sports"
        case .other: return "Other"
        default: return "Workout"
        }
    }
}
