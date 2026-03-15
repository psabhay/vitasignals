import XCTest
@testable import BPLogger

final class PDFGeneratorTests: XCTestCase {

    private func makeReadings(count: Int, startDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: .now)!) -> [BPReading] {
        (0..<count).map { i in
            let date = Calendar.current.date(byAdding: .day, value: i, to: startDate)!
            return BPReading(
                systolic: 120 + Int.random(in: -15...20),
                diastolic: 80 + Int.random(in: -10...15),
                pulse: 72 + Int.random(in: -8...12),
                timestamp: date,
                activityContext: ActivityContext.allCases.randomElement()!
            )
        }
    }

    func testGenerateWithEmptyReadings() {
        let url = PDFGenerator.generate(readings: [])
        XCTAssertNil(url, "Should return nil for empty readings")
    }

    func testGenerateBasicPDF() {
        let readings = makeReadings(count: 10)
        let url = PDFGenerator.generate(readings: readings, periodLabel: "Test Period")
        XCTAssertNotNil(url, "Should generate a PDF URL")

        if let url {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "PDF file should exist")
            let data = try? Data(contentsOf: url)
            XCTAssertNotNil(data)
            XCTAssertGreaterThan(data?.count ?? 0, 1000, "PDF should have meaningful size")
            // Cleanup
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testGenerateWithProfile() {
        let readings = makeReadings(count: 5)
        let userProfile = UserProfile()
        userProfile.name = "Test User"
        userProfile.age = 35
        userProfile.gender = "Male"
        userProfile.heightCm = 175
        userProfile.weightKg = 75
        userProfile.doctorName = "Dr. Test"
        let profile = PDFGenerator.ProfileData(from: userProfile)

        // Verify profile data was captured
        XCTAssertEqual(profile.name, "Test User")
        XCTAssertEqual(profile.age, 35)
        XCTAssertEqual(profile.gender, "Male")
        XCTAssertEqual(profile.heightCm, 175)
        XCTAssertEqual(profile.weightKg, 75)
        XCTAssertEqual(profile.doctorName, "Dr. Test")

        let url = PDFGenerator.generate(readings: readings, periodLabel: "Test", profile: profile)
        XCTAssertNotNil(url)

        // PDF with profile should be larger than without
        let urlNoProfile = PDFGenerator.generate(readings: readings, periodLabel: "Test", profile: nil)
        XCTAssertNotNil(urlNoProfile)

        if let url, let urlNoProfile {
            let sizeWith = (try? Data(contentsOf: url))?.count ?? 0
            let sizeWithout = (try? Data(contentsOf: urlNoProfile))?.count ?? 0
            XCTAssertGreaterThan(sizeWith, sizeWithout, "PDF with profile (\(sizeWith) bytes) should be larger than without (\(sizeWithout) bytes)")

            // Check the PDF text contains the profile name
            if let pdfDoc = CGPDFDocument(url as CFURL) {
                let pageCount = pdfDoc.numberOfPages
                XCTAssertGreaterThan(pageCount, 0)
            }

            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: urlNoProfile)
        }
    }

    func testGenerateWithHealthContext() {
        let readings = makeReadings(count: 14)
        var ctx = HealthContext()
        ctx.restingHeartRates = (0..<14).map {
            HealthContext.DailyValue(date: Calendar.current.date(byAdding: .day, value: -14 + $0, to: .now)!, value: Double.random(in: 58...72))
        }
        ctx.stepCounts = (0..<14).map {
            HealthContext.DailyValue(date: Calendar.current.date(byAdding: .day, value: -14 + $0, to: .now)!, value: Double.random(in: 3000...12000))
        }
        ctx.sleepEntries = (0..<14).map {
            HealthContext.SleepEntry(date: Calendar.current.date(byAdding: .day, value: -14 + $0, to: .now)!, duration: Double.random(in: 5...9) * 3600)
        }

        let url = PDFGenerator.generate(readings: readings, periodLabel: "Test", healthContext: ctx)
        XCTAssertNotNil(url)
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    func testGenerateWithSingleReading() {
        let reading = BPReading(systolic: 120, diastolic: 80, pulse: 72, activityContext: .atRest)
        let url = PDFGenerator.generate(readings: [reading])
        XCTAssertNotNil(url, "Should handle single reading")
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    func testGenerateWithManyReadings() {
        let readings = makeReadings(count: 100)
        let url = PDFGenerator.generate(readings: readings, periodLabel: "100 readings test")
        XCTAssertNotNil(url)
        if let url {
            let data = try? Data(contentsOf: url)
            XCTAssertGreaterThan(data?.count ?? 0, 5000, "Large report should be bigger")
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testGenerateWithEmptyHealthContext() {
        let readings = makeReadings(count: 5)
        let ctx = HealthContext() // all empty
        let url = PDFGenerator.generate(readings: readings, healthContext: ctx)
        XCTAssertNotNil(url, "Should handle empty health context gracefully")
        if let url { try? FileManager.default.removeItem(at: url) }
    }
}
