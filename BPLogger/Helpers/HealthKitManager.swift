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
        if systolic > 180 || diastolic > 120 { return .crisis }
        else if systolic >= 140 || diastolic >= 90 { return .highStage2 }
        else if systolic >= 130 || diastolic >= 80 { return .highStage1 }
        else if systolic >= 120 { return .elevated }
        else { return .normal }
    }
}

@MainActor
final class HealthKitManager: ObservableObject {
    private let store = HKHealthStore()

    @Published var isAuthorized = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var fetchedReadings: [HealthKitReading] = []

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private var readTypes: Set<HKObjectType> {
        let bp = HKCorrelationType(.bloodPressure)
        let systolic = HKQuantityType(.bloodPressureSystolic)
        let diastolic = HKQuantityType(.bloodPressureDiastolic)
        let heartRate = HKQuantityType(.heartRate)
        return [bp, systolic, diastolic, heartRate]
    }

    func requestAuthorization() async {
        guard HealthKitManager.isAvailable else {
            errorMessage = "HealthKit is not available on this device."
            return
        }

        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
        } catch {
            errorMessage = "Health access denied: \(error.localizedDescription)"
        }
    }

    func fetchReadings(since: Date, existingHealthKitIDs: Set<String>) async {
        isLoading = true
        errorMessage = nil
        fetchedReadings = []

        do {
            let bpType = HKCorrelationType(.bloodPressure)
            let predicate = HKQuery.predicateForSamples(withStart: since, end: .now, options: .strictStartDate)
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
                if existingHealthKitIDs.contains(hkID) { continue }

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
        let predicate = HKQuery.predicateForSamples(withStart: since, end: .now, options: .strictStartDate)
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
}
