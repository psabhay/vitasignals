import Foundation
import SwiftData

// MARK: - BP Classification (retained for blood pressure display)

enum BPCategory: String, Codable, Hashable {
    case normal = "Normal"
    case elevated = "Elevated"
    case highStage1 = "High Stage 1"
    case highStage2 = "High Stage 2"
    case crisis = "Hypertensive Crisis"

    var color: String {
        switch self {
        case .normal: return "green"
        case .elevated: return "yellow"
        case .highStage1: return "orange"
        case .highStage2: return "red"
        case .crisis: return "purple"
        }
    }

    static func classify(systolic: Int, diastolic: Int) -> BPCategory {
        if systolic > 180 || diastolic > 120 {
            return .crisis
        } else if systolic >= 140 || diastolic >= 90 {
            return .highStage2
        } else if systolic >= 130 || diastolic >= 80 {
            return .highStage1
        } else if systolic >= 120 {
            return .elevated
        } else {
            return .normal
        }
    }
}

// MARK: - Activity Context (retained for blood pressure)

enum ActivityContext: String, Codable, CaseIterable, Identifiable, Hashable {
    case justWokeUp = "Just Woke Up"
    case beforeBreakfast = "Before Breakfast"
    case afterBreakfast = "After Breakfast"
    case beforeLunch = "Before Lunch"
    case afterLunch = "After Lunch"
    case beforeDinner = "Before Dinner"
    case afterDinner = "After Dinner"
    case afterCoffee = "After Coffee"
    case afterTea = "After Tea"
    case afterWalking = "After Walking"
    case afterRunning = "After Running"
    case afterExercise = "After Exercise"
    case afterMedication = "After Medication"
    case atRest = "At Rest"
    case beforeSleep = "Before Sleep"
    case stressed = "Feeling Stressed"
    case afterAlcohol = "After Alcohol"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .justWokeUp: return "sunrise"
        case .beforeBreakfast, .afterBreakfast: return "fork.knife"
        case .beforeLunch, .afterLunch: return "sun.max"
        case .beforeDinner, .afterDinner: return "moon.stars"
        case .afterCoffee: return "cup.and.saucer"
        case .afterTea: return "leaf"
        case .afterWalking: return "figure.walk"
        case .afterRunning: return "figure.run"
        case .afterExercise: return "dumbbell"
        case .afterMedication: return "pill"
        case .atRest: return "chair.lounge"
        case .beforeSleep: return "bed.double"
        case .stressed: return "brain.head.profile"
        case .afterAlcohol: return "wineglass"
        case .other: return "ellipsis.circle"
        }
    }
}

// MARK: - Universal Health Record

@Model
final class HealthRecord {
    var id: UUID
    var metricType: String
    var timestamp: Date
    var primaryValue: Double
    var secondaryValue: Double?
    var tertiaryValue: Double?
    var stringValue: String?
    var durationSeconds: Double?
    var healthKitUUID: String?
    var source: String
    var isManualEntry: Bool
    var activityContext: String?
    var notes: String

    init(
        metricType: String,
        timestamp: Date = .now,
        primaryValue: Double,
        secondaryValue: Double? = nil,
        tertiaryValue: Double? = nil,
        stringValue: String? = nil,
        durationSeconds: Double? = nil,
        healthKitUUID: String? = nil,
        source: String = "manual",
        isManualEntry: Bool = true,
        activityContext: String? = nil,
        notes: String = ""
    ) {
        self.id = UUID()
        self.metricType = metricType
        self.timestamp = timestamp
        self.primaryValue = primaryValue
        self.secondaryValue = secondaryValue
        self.tertiaryValue = tertiaryValue
        self.stringValue = stringValue
        self.durationSeconds = durationSeconds
        self.healthKitUUID = healthKitUUID
        self.source = source
        self.isManualEntry = isManualEntry
        self.activityContext = activityContext
        self.notes = notes
    }

    var isFromHealthKit: Bool { healthKitUUID != nil }

    // MARK: - Blood Pressure Convenience

    var systolic: Int { Int(primaryValue) }
    var diastolic: Int { Int(secondaryValue ?? 0) }
    var pulseOptional: Int? { tertiaryValue.map { Int($0) } }
    var pulse: Int { pulseOptional ?? 0 }

    var bpCategory: BPCategory {
        BPCategory.classify(systolic: systolic, diastolic: diastolic)
    }

    var bpActivityContext: ActivityContext? {
        guard let activityContext else { return nil }
        return ActivityContext(rawValue: activityContext)
    }

    // MARK: - Display Helpers

    var formattedPrimaryValue: String {
        guard let def = MetricRegistry.definition(for: metricType) else {
            return primaryValue >= 100 ? "\(Int(primaryValue))" : String(format: "%.1f", primaryValue)
        }
        if metricType == MetricType.bloodPressure {
            return "\(systolic)/\(diastolic)"
        }
        if metricType == MetricType.sleepDuration {
            let hours = (durationSeconds ?? primaryValue) / 3600
            return String(format: "%.1fh", hours)
        }
        if metricType == MetricType.workout {
            let mins = Int((durationSeconds ?? 0) / 60)
            return "\(stringValue ?? "Workout") \(mins)m"
        }
        return def.formatValue(primaryValue)
    }

    var formattedDate: String {
        timestamp.formatted(date: .abbreviated, time: .shortened)
    }

    var formattedDateOnly: String {
        timestamp.formatted(date: .abbreviated, time: .omitted)
    }

    var formattedTimeOnly: String {
        timestamp.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - BP-Specific Factory

    static func bloodPressure(
        systolic: Int,
        diastolic: Int,
        pulse: Int,
        timestamp: Date = .now,
        activityContext: ActivityContext = .atRest,
        notes: String = "",
        healthKitUUID: String? = nil,
        source: String = "manual",
        isManualEntry: Bool = true
    ) -> HealthRecord {
        HealthRecord(
            metricType: MetricType.bloodPressure,
            timestamp: timestamp,
            primaryValue: Double(systolic),
            secondaryValue: Double(diastolic),
            tertiaryValue: Double(pulse),
            healthKitUUID: healthKitUUID,
            source: source,
            isManualEntry: isManualEntry,
            activityContext: activityContext.rawValue,
            notes: notes
        )
    }
}

// MARK: - Metric Type Constants

enum MetricType {
    static let bloodPressure = "bloodPressure"
    static let restingHeartRate = "restingHeartRate"
    static let heartRateVariability = "heartRateVariability"
    static let vo2Max = "vo2Max"
    static let walkingHeartRate = "walkingHeartRate"
    static let stepCount = "stepCount"
    static let exerciseMinutes = "exerciseMinutes"
    static let activeEnergy = "activeEnergy"
    static let bodyMass = "bodyMass"
    static let respiratoryRate = "respiratoryRate"
    static let oxygenSaturation = "oxygenSaturation"
    static let sleepDuration = "sleepDuration"
    static let workout = "workout"
}
