import XCTest
@testable import NeoHealthExport

final class UserProfileTests: XCTestCase {

    func testDefaultInit() {
        let profile = UserProfile()
        XCTAssertEqual(profile.name, "")
        XCTAssertEqual(profile.age, 0)
        XCTAssertEqual(profile.heightCm, 0)
        XCTAssertEqual(profile.weightKg, 0)
        XCTAssertEqual(profile.gender, "")
        XCTAssertEqual(profile.doctorName, "")
        XCTAssertEqual(profile.medicalNotes, "")
    }

    func testBMI() {
        let profile = UserProfile()
        profile.heightCm = 175  // 5'9"
        profile.weightKg = 75

        let bmi = profile.bmi
        XCTAssertNotNil(bmi)
        XCTAssertEqual(bmi!, 24.49, accuracy: 0.1)
    }

    func testBMIZeroHeight() {
        let profile = UserProfile()
        profile.heightCm = 0
        profile.weightKg = 75
        XCTAssertNil(profile.bmi)
    }

    func testBMIZeroWeight() {
        let profile = UserProfile()
        profile.heightCm = 175
        profile.weightKg = 0
        XCTAssertNil(profile.bmi)
    }

    func testBMICategories() {
        let profile = UserProfile()
        profile.heightCm = 175

        profile.weightKg = 50 // BMI ~16.3
        XCTAssertEqual(profile.bmiCategory, "Underweight")

        profile.weightKg = 70 // BMI ~22.9
        XCTAssertEqual(profile.bmiCategory, "Normal")

        profile.weightKg = 85 // BMI ~27.8
        XCTAssertEqual(profile.bmiCategory, "Overweight")

        profile.weightKg = 110 // BMI ~35.9
        XCTAssertEqual(profile.bmiCategory, "Obese")
    }

    func testHeightFormatted() {
        let profile = UserProfile()
        profile.heightCm = 175
        let formatted = profile.heightFormatted
        XCTAssertTrue(formatted.contains("5'"), "Should contain feet: \(formatted)")
        XCTAssertTrue(formatted.contains("175 cm"), "Should contain cm: \(formatted)")
    }

    func testHeightFormattedEmpty() {
        let profile = UserProfile()
        profile.heightCm = 0
        XCTAssertEqual(profile.heightFormatted, "")
    }

    func testWeightFormatted() {
        let profile = UserProfile()
        profile.weightKg = 75
        let formatted = profile.weightFormatted
        XCTAssertTrue(formatted.contains("75 kg"), "Should contain kg: \(formatted)")
        XCTAssertTrue(formatted.contains("lbs"), "Should contain lbs: \(formatted)")
    }

    func testWeightFormattedEmpty() {
        let profile = UserProfile()
        profile.weightKg = 0
        XCTAssertEqual(profile.weightFormatted, "")
    }
}
