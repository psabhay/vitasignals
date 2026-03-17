import SwiftUI
import HealthKit

// MARK: - Metric Categories

enum MetricCategory: String, CaseIterable, Identifiable {
    case vitals = "Vitals"
    case cardioFitness = "Cardio Fitness"
    case activity = "Activity"
    case body = "Body"
    case sleepRecovery = "Sleep & Recovery"
    case respiratory = "Respiratory"
    case nutrition = "Nutrition"
    case mobility = "Mobility"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .vitals: return "heart.text.square"
        case .cardioFitness: return "heart.circle"
        case .activity: return "figure.walk"
        case .body: return "figure.arms.open"
        case .sleepRecovery: return "bed.double"
        case .respiratory: return "lungs"
        case .nutrition: return "fork.knife"
        case .mobility: return "figure.walk.motion"
        case .other: return "ellipsis.circle"
        }
    }

    var color: Color {
        switch self {
        case .vitals: return .red
        case .cardioFitness: return .purple
        case .activity: return .green
        case .body: return .orange
        case .sleepRecovery: return .indigo
        case .respiratory: return .teal
        case .nutrition: return .brown
        case .mobility: return .mint
        case .other: return .gray
        }
    }
}

// MARK: - Chart Style

enum ChartStyle {
    case line
    case bar
    case bpDual
}

// MARK: - Aggregation Type

enum AggregationType {
    case average
    case sum
    case mostRecent
}

// MARK: - Metric Definition

struct MetricDefinition: @unchecked Sendable {
    let type: String
    let name: String
    let unit: String
    let icon: String
    let color: Color
    let category: MetricCategory
    let chartStyle: ChartStyle
    let aggregation: AggregationType
    let referenceMin: Double?
    let referenceMax: Double?
    let inputMin: Double
    let inputMax: Double
    let inputStep: Double
    let hkQuantityType: HKQuantityTypeIdentifier?
    let hkUnit: (() -> HKUnit)?
    let isCumulative: Bool
    var description: String?

    func formatValue(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.0f", value)
        } else if value >= 100 {
            return "\(Int(value))"
        } else if value == value.rounded() && value < 100 {
            return "\(Int(value))"
        } else {
            return String(format: "%.1f", value)
        }
    }
}

// MARK: - Metric Registry

struct MetricRegistry {
    static let all: [MetricDefinition] = [
        // Vitals
        MetricDefinition(
            type: MetricType.bloodPressure,
            name: "Blood Pressure",
            unit: "mmHg",
            icon: "heart.text.square",
            color: .red,
            category: .vitals,
            chartStyle: .bpDual,
            aggregation: .average,
            referenceMin: 90,
            referenceMax: 120,
            inputMin: 60,
            inputMax: 300,
            inputStep: 1,
            hkQuantityType: nil,
            hkUnit: nil,
            isCumulative: false,
            description: "The force of blood against artery walls, measured as systolic over diastolic pressure."
        ),
        // Cardio Fitness
        MetricDefinition(
            type: MetricType.restingHeartRate,
            name: "Resting Heart Rate",
            unit: "bpm",
            icon: "heart.fill",
            color: .pink,
            category: .cardioFitness,
            chartStyle: .line,
            aggregation: .average,
            referenceMin: 60,
            referenceMax: 100,
            inputMin: 30,
            inputMax: 220,
            inputStep: 1,
            hkQuantityType: .restingHeartRate,
            hkUnit: { HKUnit.count().unitDivided(by: .minute()) },
            isCumulative: false,
            description: "Heart rate measured when you've been inactive and calm for at least 10 minutes."
        ),
        MetricDefinition(
            type: MetricType.heartRateVariability,
            name: "Heart Rate Variability",
            unit: "ms",
            icon: "waveform.path.ecg",
            color: .purple,
            category: .cardioFitness,
            chartStyle: .line,
            aggregation: .average,
            referenceMin: 20,
            referenceMax: nil,
            inputMin: 1,
            inputMax: 300,
            inputStep: 1,
            hkQuantityType: .heartRateVariabilitySDNN,
            hkUnit: { HKUnit.secondUnit(with: .milli) },
            isCumulative: false,
            description: "Variation in time between heartbeats (SDNN), indicating autonomic nervous system balance."
        ),
        MetricDefinition(
            type: MetricType.vo2Max,
            name: "VO2 Max",
            unit: "mL/kg/min",
            icon: "lungs.fill",
            color: .orange,
            category: .cardioFitness,
            chartStyle: .line,
            aggregation: .mostRecent,
            referenceMin: 20,
            referenceMax: 60,
            inputMin: 10,
            inputMax: 90,
            inputStep: 0.1,
            hkQuantityType: .vo2Max,
            hkUnit: { HKUnit(from: "ml/kg*min") },
            isCumulative: false,
            description: "Maximum oxygen your body can use during exercise, a key indicator of cardiorespiratory fitness."
        ),
        MetricDefinition(
            type: MetricType.walkingHeartRate,
            name: "Walking Heart Rate",
            unit: "bpm",
            icon: "figure.walk",
            color: .red,
            category: .cardioFitness,
            chartStyle: .line,
            aggregation: .average,
            referenceMin: nil,
            referenceMax: nil,
            inputMin: 40,
            inputMax: 200,
            inputStep: 1,
            hkQuantityType: .walkingHeartRateAverage,
            hkUnit: { HKUnit.count().unitDivided(by: .minute()) },
            isCumulative: false,
            description: "Average heart rate recorded while walking, reflecting cardiovascular efficiency during movement."
        ),
        // Activity
        MetricDefinition(
            type: MetricType.stepCount,
            name: "Steps",
            unit: "steps",
            icon: "shoeprints.fill",
            color: .green,
            category: .activity,
            chartStyle: .bar,
            aggregation: .sum,
            referenceMin: nil,
            referenceMax: nil,
            inputMin: 0,
            inputMax: 100000,
            inputStep: 100,
            hkQuantityType: .stepCount,
            hkUnit: { HKUnit.count() },
            isCumulative: true,
            description: "Total number of steps detected by your device throughout the day."
        ),
        MetricDefinition(
            type: MetricType.exerciseMinutes,
            name: "Exercise Minutes",
            unit: "min",
            icon: "flame.fill",
            color: .mint,
            category: .activity,
            chartStyle: .bar,
            aggregation: .sum,
            referenceMin: nil,
            referenceMax: nil,
            inputMin: 0,
            inputMax: 600,
            inputStep: 1,
            hkQuantityType: .appleExerciseTime,
            hkUnit: { HKUnit.minute() },
            isCumulative: true,
            description: "Minutes spent in activity at or above a brisk walk, as tracked by Apple Watch."
        ),
        MetricDefinition(
            type: MetricType.activeEnergy,
            name: "Active Energy",
            unit: "kcal",
            icon: "bolt.fill",
            color: .yellow,
            category: .activity,
            chartStyle: .bar,
            aggregation: .sum,
            referenceMin: nil,
            referenceMax: nil,
            inputMin: 0,
            inputMax: 5000,
            inputStep: 10,
            hkQuantityType: .activeEnergyBurned,
            hkUnit: { HKUnit.kilocalorie() },
            isCumulative: true,
            description: "Calories burned through movement and exercise above your resting metabolic rate."
        ),
        // Body
        MetricDefinition(
            type: MetricType.bodyMass,
            name: "Weight",
            unit: "kg",
            icon: "scalemass",
            color: .brown,
            category: .body,
            chartStyle: .line,
            aggregation: .mostRecent,
            referenceMin: nil,
            referenceMax: nil,
            inputMin: 20,
            inputMax: 300,
            inputStep: 0.1,
            hkQuantityType: .bodyMass,
            hkUnit: { HKUnit.gramUnit(with: .kilo) },
            isCumulative: false,
            description: "Your body weight as measured or entered manually."
        ),
        // Sleep & Recovery
        MetricDefinition(
            type: MetricType.sleepDuration,
            name: "Sleep Duration",
            unit: "hours",
            icon: "bed.double.fill",
            color: .indigo,
            category: .sleepRecovery,
            chartStyle: .bar,
            aggregation: .sum,
            referenceMin: 7,
            referenceMax: 9,
            inputMin: 0,
            inputMax: 24,
            inputStep: 0.5,
            hkQuantityType: nil,
            hkUnit: nil,
            isCumulative: false,
            description: "Total time spent asleep, including all sleep stages tracked by your device."
        ),
        // Activity - Workout
        MetricDefinition(
            type: MetricType.workout,
            name: "Workout",
            unit: "min",
            icon: "figure.strengthtraining.traditional",
            color: .cyan,
            category: .activity,
            chartStyle: .bar,
            aggregation: .sum,
            referenceMin: nil,
            referenceMax: nil,
            inputMin: 0,
            inputMax: 600,
            inputStep: 1,
            hkQuantityType: nil,
            hkUnit: nil,
            isCumulative: false,
            description: "Duration of recorded workout sessions across all activity types."
        ),
        // Respiratory
        MetricDefinition(
            type: MetricType.respiratoryRate,
            name: "Respiratory Rate",
            unit: "br/min",
            icon: "wind",
            color: .teal,
            category: .respiratory,
            chartStyle: .line,
            aggregation: .average,
            referenceMin: 12,
            referenceMax: 20,
            inputMin: 5,
            inputMax: 60,
            inputStep: 0.1,
            hkQuantityType: .respiratoryRate,
            hkUnit: { HKUnit.count().unitDivided(by: .minute()) },
            isCumulative: false,
            description: "Number of breaths taken per minute, typically measured during sleep by Apple Watch."
        ),
        MetricDefinition(
            type: MetricType.oxygenSaturation,
            name: "Blood Oxygen (SpO2)",
            unit: "%",
            icon: "drop.fill",
            color: .cyan,
            category: .respiratory,
            chartStyle: .line,
            aggregation: .average,
            referenceMin: 95,
            referenceMax: 100,
            inputMin: 70,
            inputMax: 100,
            inputStep: 0.1,
            hkQuantityType: .oxygenSaturation,
            hkUnit: { HKUnit.percent() },
            isCumulative: false,
            description: "Percentage of hemoglobin carrying oxygen in your blood, measured via wrist pulse oximetry."
        ),
    ]

    private static let _definitionsByCategory: [MetricCategory: [MetricDefinition]] = {
        var result: [MetricCategory: [MetricDefinition]] = [:]
        for category in MetricCategory.allCases {
            var defs = all.filter { $0.category == category }
            let curatedTypes = Set(defs.map(\.type))
            let catalogDefs = HealthKitCatalog.entries
                .filter { $0.category == category && !curatedTypes.contains($0.metricType) }
                .map { $0.toMetricDefinition() }
            defs.append(contentsOf: catalogDefs)
            result[category] = defs
        }
        return result
    }()

    static func definitions(for category: MetricCategory) -> [MetricDefinition] {
        _definitionsByCategory[category] ?? []
    }

    private static let _definitionsByType: [String: MetricDefinition] = {
        var result: [String: MetricDefinition] = [:]
        // Curated first (higher priority)
        for def in all {
            result[def.type] = def
        }
        // Catalog for anything not curated
        for entry in HealthKitCatalog.entries where result[entry.metricType] == nil {
            result[entry.metricType] = entry.toMetricDefinition()
        }
        return result
    }()

    static func definition(for metricType: String) -> MetricDefinition? {
        _definitionsByType[metricType]
    }

    static var allKnownTypes: Set<String> {
        Set(_definitionsByType.keys)
    }

    static var syncableMetrics: [MetricDefinition] {
        all.filter { $0.hkQuantityType != nil || $0.type == MetricType.sleepDuration }
    }
}
