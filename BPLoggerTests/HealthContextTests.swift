import XCTest
@testable import BPLogger

final class HealthContextTests: XCTestCase {

    func testEmptyContext() {
        let ctx = HealthContext()
        XCTAssertFalse(ctx.hasCardioFitnessData)
        XCTAssertFalse(ctx.hasLifestyleData)
        XCTAssertFalse(ctx.hasSleepData)
        XCTAssertFalse(ctx.hasAnyData)
    }

    func testCardioFitnessData() {
        var ctx = HealthContext()
        ctx.restingHeartRates = [HealthContext.DailyValue(date: .now, value: 65)]
        XCTAssertTrue(ctx.hasCardioFitnessData)
        XCTAssertTrue(ctx.hasAnyData)
        XCTAssertFalse(ctx.hasLifestyleData)
        XCTAssertFalse(ctx.hasSleepData)
    }

    func testHRVTriggersCardioFitness() {
        var ctx = HealthContext()
        ctx.hrvValues = [HealthContext.DailyValue(date: .now, value: 45)]
        XCTAssertTrue(ctx.hasCardioFitnessData)
    }

    func testVO2MaxTriggersCardioFitness() {
        var ctx = HealthContext()
        ctx.vo2MaxValues = [HealthContext.DailyValue(date: .now, value: 35)]
        XCTAssertTrue(ctx.hasCardioFitnessData)
    }

    func testLifestyleData() {
        var ctx = HealthContext()
        ctx.stepCounts = [HealthContext.DailyValue(date: .now, value: 8000)]
        XCTAssertTrue(ctx.hasLifestyleData)
        XCTAssertTrue(ctx.hasAnyData)
        XCTAssertFalse(ctx.hasCardioFitnessData)
    }

    func testExerciseMinutesTriggersLifestyle() {
        var ctx = HealthContext()
        ctx.exerciseMinutes = [HealthContext.DailyValue(date: .now, value: 30)]
        XCTAssertTrue(ctx.hasLifestyleData)
    }

    func testBodyMassTriggersLifestyle() {
        var ctx = HealthContext()
        ctx.bodyMassValues = [HealthContext.DailyValue(date: .now, value: 75)]
        XCTAssertTrue(ctx.hasLifestyleData)
    }

    func testSleepData() {
        var ctx = HealthContext()
        ctx.sleepEntries = [HealthContext.SleepEntry(date: .now, duration: 7 * 3600)]
        XCTAssertTrue(ctx.hasSleepData)
        XCTAssertTrue(ctx.hasAnyData)
    }

    func testSleepEntryHours() {
        let entry = HealthContext.SleepEntry(date: .now, duration: 7.5 * 3600)
        XCTAssertEqual(entry.hours, 7.5, accuracy: 0.01)
        XCTAssertEqual(entry.formatted, "7.5h")
    }

    func testWorkoutEntry() {
        let entry = HealthContext.WorkoutEntry(date: .now, type: "Running", duration: 1800)
        XCTAssertEqual(entry.durationMinutes, 30)
        XCTAssertEqual(entry.type, "Running")
    }

    func testDailyValueDateLabel() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.date(from: "2026-03-15")!
        let value = HealthContext.DailyValue(date: date, value: 100)
        // dateLabel uses .abbreviated which gives something like "Mar 15"
        XCTAssertFalse(value.dateLabel.isEmpty)
    }

    func testOxygenSaturationTriggersAnyData() {
        var ctx = HealthContext()
        ctx.oxygenSaturation = [HealthContext.DailyValue(date: .now, value: 97)]
        XCTAssertTrue(ctx.hasAnyData)
        XCTAssertFalse(ctx.hasCardioFitnessData)
        XCTAssertFalse(ctx.hasLifestyleData)
        XCTAssertFalse(ctx.hasSleepData)
    }

    func testWorkoutsTriggersAnyData() {
        var ctx = HealthContext()
        ctx.workouts = [HealthContext.WorkoutEntry(date: .now, type: "Walking", duration: 600)]
        XCTAssertTrue(ctx.hasAnyData)
    }
}
