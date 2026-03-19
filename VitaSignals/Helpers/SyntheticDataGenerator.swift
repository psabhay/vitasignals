#if DEBUG
import Foundation
import SwiftData

struct SyntheticDataGenerator {

    static func generate(into context: ModelContext, days: Int = 90) -> Int {
        let calendar = Calendar.current
        let now = Date.now
        var count = 0

        // ── Blood Pressure: 2-3 readings/day ──
        for dayOffset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let readingsPerDay = Int.random(in: 2...3)
            for r in 0..<readingsPerDay {
                let hour = r == 0 ? Int.random(in: 6...9) : (r == 1 ? Int.random(in: 12...15) : Int.random(in: 19...22))
                guard let ts = calendar.date(bySettingHour: hour, minute: Int.random(in: 0...59), second: 0, of: day) else { continue }

                // Realistic BP with slight daily variation and trend
                let baseSys = 122.0 + Double.random(in: -12...18) + (hour > 17 ? 4 : 0)
                let baseDia = 78.0 + Double.random(in: -8...12) + (hour > 17 ? 2 : 0)
                let basePulse = 72.0 + Double.random(in: -10...15)

                let contexts: [ActivityContext] = [.atRest, .justWokeUp, .afterBreakfast, .afterLunch, .afterDinner, .afterCoffee, .beforeSleep, .afterExercise]
                let ctx = contexts.randomElement()!

                context.insert(HealthRecord.bloodPressure(
                    systolic: Int(baseSys), diastolic: Int(baseDia), pulse: Int(basePulse),
                    timestamp: ts, activityContext: ctx, source: "Synthetic"
                ))
                count += 1
            }
        }

        // ── Heart Rate: 1/day ──
        count += generateDaily(into: context, type: "heartRate", days: days, now: now, calendar: calendar,
                               baseValue: 72, variance: 12, source: "Synthetic")

        // ── Resting Heart Rate: 1/day ──
        count += generateDaily(into: context, type: MetricType.restingHeartRate, days: days, now: now, calendar: calendar,
                               baseValue: 62, variance: 8, source: "Synthetic")

        // ── HRV: 1/day ──
        count += generateDaily(into: context, type: MetricType.heartRateVariability, days: days, now: now, calendar: calendar,
                               baseValue: 42, variance: 18, source: "Synthetic")

        // ── Steps: daily cumulative ──
        count += generateDaily(into: context, type: MetricType.stepCount, days: days, now: now, calendar: calendar,
                               baseValue: 7500, variance: 4000, source: "Synthetic")

        // ── Exercise Minutes: daily cumulative ──
        count += generateDaily(into: context, type: MetricType.exerciseMinutes, days: days, now: now, calendar: calendar,
                               baseValue: 35, variance: 30, source: "Synthetic")

        // ── Active Energy: daily cumulative ──
        count += generateDaily(into: context, type: MetricType.activeEnergy, days: days, now: now, calendar: calendar,
                               baseValue: 450, variance: 250, source: "Synthetic")

        // ── Weight: weekly ──
        for week in 0..<(days / 7) {
            guard let day = calendar.date(byAdding: .day, value: -(week * 7), to: now),
                  let ts = calendar.date(bySettingHour: 7, minute: Int.random(in: 0...30), second: 0, of: day) else { continue }
            let weight = 75.0 + Double.random(in: -2...2) - Double(week) * 0.05
            context.insert(HealthRecord(metricType: MetricType.bodyMass, timestamp: ts,
                                        primaryValue: weight, source: "Synthetic"))
            count += 1
        }

        // ── Sleep: daily ──
        for dayOffset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: now),
                  let ts = calendar.date(bySettingHour: 7, minute: Int.random(in: 0...45), second: 0, of: day) else { continue }
            let hours = Double.random(in: 5.5...9.0)
            context.insert(HealthRecord(metricType: MetricType.sleepDuration, timestamp: ts,
                                        primaryValue: hours, durationSeconds: hours * 3600, source: "Synthetic"))
            count += 1
        }

        // ── SpO2: daily ──
        count += generateDaily(into: context, type: MetricType.oxygenSaturation, days: days, now: now, calendar: calendar,
                               baseValue: 97.5, variance: 2, source: "Synthetic")

        // ── Respiratory Rate: daily ──
        count += generateDaily(into: context, type: MetricType.respiratoryRate, days: days, now: now, calendar: calendar,
                               baseValue: 15, variance: 3, source: "Synthetic")

        // ── VO2 Max: weekly ──
        for week in 0..<(days / 7) {
            guard let day = calendar.date(byAdding: .day, value: -(week * 7 + Int.random(in: 0...2)), to: now),
                  let ts = calendar.date(bySettingHour: Int.random(in: 8...18), minute: 0, second: 0, of: day) else { continue }
            let vo2 = 38.0 + Double.random(in: -4...4) + Double(week) * 0.1
            context.insert(HealthRecord(metricType: MetricType.vo2Max, timestamp: ts,
                                        primaryValue: vo2, source: "Synthetic"))
            count += 1
        }

        // ── Walking Heart Rate: daily ──
        count += generateDaily(into: context, type: MetricType.walkingHeartRate, days: min(days, 60), now: now, calendar: calendar,
                               baseValue: 105, variance: 15, source: "Synthetic")

        // ── Body Temperature: occasional ──
        for i in stride(from: 0, to: days, by: Int.random(in: 5...10)) {
            guard let day = calendar.date(byAdding: .day, value: -i, to: now),
                  let ts = calendar.date(bySettingHour: Int.random(in: 8...20), minute: 0, second: 0, of: day) else { continue }
            let temp = 36.6 + Double.random(in: -0.4...0.6)
            context.insert(HealthRecord(metricType: "bodyTemperature", timestamp: ts,
                                        primaryValue: temp, source: "Synthetic"))
            count += 1
        }

        // ── Blood Glucose: occasional ──
        for i in stride(from: 0, to: days, by: Int.random(in: 3...7)) {
            guard let day = calendar.date(byAdding: .day, value: -i, to: now),
                  let ts = calendar.date(bySettingHour: Int.random(in: 7...21), minute: 0, second: 0, of: day) else { continue }
            let glucose = 95.0 + Double.random(in: -15...25)
            context.insert(HealthRecord(metricType: "bloodGlucose", timestamp: ts,
                                        primaryValue: glucose, source: "Synthetic"))
            count += 1
        }

        // ── Water Intake: daily ──
        count += generateDaily(into: context, type: "dietaryWater", days: min(days, 60), now: now, calendar: calendar,
                               baseValue: 2200, variance: 800, source: "Synthetic")

        // ── Caffeine: daily ──
        count += generateDaily(into: context, type: "dietaryCaffeine", days: min(days, 45), now: now, calendar: calendar,
                               baseValue: 180, variance: 120, source: "Synthetic")

        // ── Walking Speed: daily ──
        count += generateDaily(into: context, type: "walkingSpeed", days: min(days, 60), now: now, calendar: calendar,
                               baseValue: 1.3, variance: 0.3, source: "Synthetic")

        // ── Flights Climbed: daily ──
        count += generateDaily(into: context, type: "flightsClimbed", days: days, now: now, calendar: calendar,
                               baseValue: 8, variance: 7, source: "Synthetic")

        try? context.save()
        return count
    }

    // MARK: - Helper

    private static func generateDaily(
        into context: ModelContext,
        type: String, days: Int, now: Date, calendar: Calendar,
        baseValue: Double, variance: Double, source: String
    ) -> Int {
        var count = 0
        for dayOffset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: now),
                  let ts = calendar.date(bySettingHour: Int.random(in: 7...21), minute: Int.random(in: 0...59), second: 0, of: day) else { continue }
            let value = max(0, baseValue + Double.random(in: -variance...variance))
            context.insert(HealthRecord(metricType: type, timestamp: ts,
                                        primaryValue: value, source: source))
            count += 1
        }
        return count
    }
}
#endif
