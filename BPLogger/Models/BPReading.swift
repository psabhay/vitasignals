import Foundation
import SwiftData

enum BPCategory: String, Codable {
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
}

enum ActivityContext: String, Codable, CaseIterable, Identifiable {
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

@Model
final class BPReading {
    var id: UUID
    var systolic: Int
    var diastolic: Int
    var pulse: Int
    var timestamp: Date
    var activityContext: ActivityContext
    var notes: String
    var healthKitID: String?

    init(
        systolic: Int,
        diastolic: Int,
        pulse: Int,
        timestamp: Date = .now,
        activityContext: ActivityContext,
        notes: String = "",
        healthKitID: String? = nil
    ) {
        self.id = UUID()
        self.systolic = systolic
        self.diastolic = diastolic
        self.pulse = pulse
        self.timestamp = timestamp
        self.activityContext = activityContext
        self.notes = notes
        self.healthKitID = healthKitID
    }

    var isFromHealthKit: Bool {
        healthKitID != nil
    }

    var category: BPCategory {
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

    var formattedReading: String {
        "\(systolic)/\(diastolic)"
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
}
