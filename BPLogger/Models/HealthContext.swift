import Foundation

struct HealthContext {
    struct DailyValue: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        var dateLabel: String { date.formatted(.dateTime.month(.abbreviated).day()) }
    }

    struct SleepEntry: Identifiable {
        let id = UUID()
        let date: Date
        let duration: TimeInterval // seconds
        var hours: Double { duration / 3600 }
        var formatted: String { String(format: "%.1fh", hours) }
    }

    struct WorkoutEntry: Identifiable {
        let id = UUID()
        let date: Date
        let type: String
        let duration: TimeInterval
        var durationMinutes: Int { Int(duration / 60) }
    }

    var restingHeartRates: [DailyValue] = []
    var hrvValues: [DailyValue] = []           // SDNN in ms
    var vo2MaxValues: [DailyValue] = []        // mL/kg/min
    var walkingHeartRates: [DailyValue] = []
    var bodyMassValues: [DailyValue] = []      // kg
    var stepCounts: [DailyValue] = []          // daily totals
    var exerciseMinutes: [DailyValue] = []     // daily totals
    var activeEnergy: [DailyValue] = []        // kcal daily totals
    var sleepEntries: [SleepEntry] = []
    var respiratoryRates: [DailyValue] = []    // breaths/min
    var oxygenSaturation: [DailyValue] = []    // percentage 0-100
    var workouts: [WorkoutEntry] = []

    var hasCardioFitnessData: Bool {
        !restingHeartRates.isEmpty || !hrvValues.isEmpty || !vo2MaxValues.isEmpty
    }

    var hasLifestyleData: Bool {
        !stepCounts.isEmpty || !exerciseMinutes.isEmpty || !bodyMassValues.isEmpty
    }

    var hasSleepData: Bool {
        !sleepEntries.isEmpty
    }

    var hasAnyData: Bool {
        hasCardioFitnessData || hasLifestyleData || hasSleepData || !oxygenSaturation.isEmpty || !workouts.isEmpty
    }
}
