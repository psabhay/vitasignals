import XCTest
@testable import BPLogger

final class BPReadingTests: XCTestCase {

    // MARK: - BP Classification

    func testClassifyNormal() {
        XCTAssertEqual(BPReading.classify(systolic: 115, diastolic: 75), .normal)
        XCTAssertEqual(BPReading.classify(systolic: 90, diastolic: 60), .normal)
        XCTAssertEqual(BPReading.classify(systolic: 119, diastolic: 79), .normal)
    }

    func testClassifyElevated() {
        XCTAssertEqual(BPReading.classify(systolic: 120, diastolic: 75), .elevated)
        XCTAssertEqual(BPReading.classify(systolic: 129, diastolic: 79), .elevated)
    }

    func testClassifyHighStage1() {
        XCTAssertEqual(BPReading.classify(systolic: 130, diastolic: 80), .highStage1)
        XCTAssertEqual(BPReading.classify(systolic: 139, diastolic: 89), .highStage1)
        // Diastolic alone can trigger
        XCTAssertEqual(BPReading.classify(systolic: 115, diastolic: 85), .highStage1)
    }

    func testClassifyHighStage2() {
        XCTAssertEqual(BPReading.classify(systolic: 140, diastolic: 90), .highStage2)
        XCTAssertEqual(BPReading.classify(systolic: 160, diastolic: 100), .highStage2)
        XCTAssertEqual(BPReading.classify(systolic: 180, diastolic: 120), .highStage2)
    }

    func testClassifyCrisis() {
        XCTAssertEqual(BPReading.classify(systolic: 181, diastolic: 100), .crisis)
        XCTAssertEqual(BPReading.classify(systolic: 150, diastolic: 121), .crisis)
        XCTAssertEqual(BPReading.classify(systolic: 200, diastolic: 130), .crisis)
    }

    func testClassifyHigherCategoryWins() {
        // Systolic says elevated (125), diastolic says stage 1 (85) -> stage 1 wins
        XCTAssertEqual(BPReading.classify(systolic: 125, diastolic: 85), .highStage1)
        // Systolic says stage 2 (145), diastolic says normal (70) -> stage 2 wins
        XCTAssertEqual(BPReading.classify(systolic: 145, diastolic: 70), .highStage2)
    }

    // MARK: - BPReading Model

    func testReadingCreation() {
        let reading = BPReading(systolic: 120, diastolic: 80, pulse: 72, activityContext: .atRest)
        XCTAssertEqual(reading.systolic, 120)
        XCTAssertEqual(reading.diastolic, 80)
        XCTAssertEqual(reading.pulse, 72)
        XCTAssertEqual(reading.activityContext, .atRest)
        XCTAssertEqual(reading.notes, "")
        XCTAssertNil(reading.healthKitID)
        XCTAssertFalse(reading.isFromHealthKit)
    }

    func testReadingWithHealthKitID() {
        let reading = BPReading(systolic: 130, diastolic: 85, pulse: 68, activityContext: .afterMedication, healthKitID: "test-hk-id")
        XCTAssertTrue(reading.isFromHealthKit)
        XCTAssertEqual(reading.healthKitID, "test-hk-id")
    }

    func testFormattedReading() {
        let reading = BPReading(systolic: 135, diastolic: 88, pulse: 75, activityContext: .atRest)
        XCTAssertEqual(reading.formattedReading, "135/88")
    }

    func testCategory() {
        let normal = BPReading(systolic: 115, diastolic: 75, pulse: 72, activityContext: .atRest)
        XCTAssertEqual(normal.category, .normal)

        let high = BPReading(systolic: 150, diastolic: 95, pulse: 80, activityContext: .stressed)
        XCTAssertEqual(high.category, .highStage2)
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
