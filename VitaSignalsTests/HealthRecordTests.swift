import XCTest
@testable import VitaSignals

final class HealthRecordTests: XCTestCase {

    // MARK: - BP Classification

    func testClassifyNormal() {
        XCTAssertEqual(BPCategory.classify(systolic: 115, diastolic: 75), .normal)
        XCTAssertEqual(BPCategory.classify(systolic: 90, diastolic: 60), .normal)
        XCTAssertEqual(BPCategory.classify(systolic: 119, diastolic: 79), .normal)
    }

    func testClassifyElevated() {
        XCTAssertEqual(BPCategory.classify(systolic: 120, diastolic: 75), .elevated)
        XCTAssertEqual(BPCategory.classify(systolic: 129, diastolic: 79), .elevated)
    }

    func testClassifyHighStage1() {
        XCTAssertEqual(BPCategory.classify(systolic: 130, diastolic: 80), .highStage1)
        XCTAssertEqual(BPCategory.classify(systolic: 139, diastolic: 89), .highStage1)
        XCTAssertEqual(BPCategory.classify(systolic: 115, diastolic: 85), .highStage1)
    }

    func testClassifyHighStage2() {
        XCTAssertEqual(BPCategory.classify(systolic: 140, diastolic: 90), .highStage2)
        XCTAssertEqual(BPCategory.classify(systolic: 160, diastolic: 100), .highStage2)
        XCTAssertEqual(BPCategory.classify(systolic: 180, diastolic: 120), .highStage2)
    }

    func testClassifyCrisis() {
        XCTAssertEqual(BPCategory.classify(systolic: 181, diastolic: 100), .crisis)
        XCTAssertEqual(BPCategory.classify(systolic: 150, diastolic: 121), .crisis)
        XCTAssertEqual(BPCategory.classify(systolic: 200, diastolic: 130), .crisis)
    }

    func testClassifyHigherCategoryWins() {
        XCTAssertEqual(BPCategory.classify(systolic: 125, diastolic: 85), .highStage1)
        XCTAssertEqual(BPCategory.classify(systolic: 145, diastolic: 70), .highStage2)
    }

    // MARK: - HealthRecord Model

    func testBPRecordCreation() {
        let record = HealthRecord.bloodPressure(systolic: 120, diastolic: 80, pulse: 72, activityContext: .atRest)
        XCTAssertEqual(record.systolic, 120)
        XCTAssertEqual(record.diastolic, 80)
        XCTAssertEqual(record.pulse, 72)
        XCTAssertEqual(record.metricType, MetricType.bloodPressure)
        XCTAssertEqual(record.bpActivityContext, .atRest)
        XCTAssertEqual(record.notes, "")
        XCTAssertNil(record.healthKitUUID)
        XCTAssertFalse(record.isFromHealthKit)
        XCTAssertTrue(record.isManualEntry)
    }

    func testBPRecordWithHealthKitUUID() {
        let record = HealthRecord.bloodPressure(
            systolic: 130, diastolic: 85, pulse: 68,
            activityContext: .afterMedication, healthKitUUID: "test-hk-id"
        )
        XCTAssertTrue(record.isFromHealthKit)
        XCTAssertEqual(record.healthKitUUID, "test-hk-id")
    }

    func testFormattedPrimaryValue() {
        let record = HealthRecord.bloodPressure(systolic: 135, diastolic: 88, pulse: 75)
        XCTAssertEqual(record.formattedPrimaryValue, "135/88")
    }

    func testBPCategory() {
        let normal = HealthRecord.bloodPressure(systolic: 115, diastolic: 75, pulse: 72)
        XCTAssertEqual(normal.bpCategory, .normal)

        let high = HealthRecord.bloodPressure(systolic: 150, diastolic: 95, pulse: 80, activityContext: .stressed)
        XCTAssertEqual(high.bpCategory, .highStage2)
    }

    func testGenericRecordCreation() {
        let record = HealthRecord(
            metricType: MetricType.restingHeartRate,
            primaryValue: 65,
            source: "Apple Watch",
            isManualEntry: false
        )
        XCTAssertEqual(record.metricType, MetricType.restingHeartRate)
        XCTAssertEqual(record.primaryValue, 65)
        XCTAssertEqual(record.source, "Apple Watch")
        XCTAssertFalse(record.isManualEntry)
    }

    func testSleepRecord() {
        let record = HealthRecord(
            metricType: MetricType.sleepDuration,
            primaryValue: 7.5,
            durationSeconds: 7.5 * 3600
        )
        XCTAssertEqual(record.metricType, MetricType.sleepDuration)
        XCTAssertEqual(record.durationSeconds!, 27000, accuracy: 1)
    }

    // MARK: - ActivityContext

    func testAllContextsHaveIcons() {
        for context in ActivityContext.allCases {
            XCTAssertFalse(context.icon.isEmpty, "Context \(context.rawValue) should have an icon")
        }
    }

    func testAllContextsHaveRawValues() {
        for context in ActivityContext.allCases {
            XCTAssertFalse(context.rawValue.isEmpty, "Context should have a raw value")
        }
    }

    // MARK: - BPCategory

    func testCategoryColors() {
        XCTAssertEqual(BPCategory.normal.color, "green")
        XCTAssertEqual(BPCategory.elevated.color, "yellow")
        XCTAssertEqual(BPCategory.highStage1.color, "orange")
        XCTAssertEqual(BPCategory.highStage2.color, "red")
        XCTAssertEqual(BPCategory.crisis.color, "purple")
    }
}
