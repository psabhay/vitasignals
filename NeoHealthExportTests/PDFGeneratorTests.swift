import XCTest
@testable import NeoHealthExport

final class PDFGeneratorTests: XCTestCase {

    private func makeBPRecords(count: Int, startDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: .now)!) -> [HealthRecord] {
        (0..<count).map { i in
            let date = Calendar.current.date(byAdding: .day, value: i, to: startDate)!
            return HealthRecord.bloodPressure(
                systolic: 120 + Int.random(in: -15...20),
                diastolic: 80 + Int.random(in: -10...15),
                pulse: 72 + Int.random(in: -8...12),
                timestamp: date,
                activityContext: ActivityContext.allCases.randomElement()!
            )
        }
    }

    private func makeHealthRecords() -> [HealthRecord] {
        var records = makeBPRecords(count: 10)
        // Add some other metric records
        for i in 0..<7 {
            let date = Calendar.current.date(byAdding: .day, value: -7 + i, to: .now)!
            records.append(HealthRecord(
                metricType: MetricType.restingHeartRate,
                timestamp: date,
                primaryValue: Double.random(in: 58...72),
                source: "Apple Watch",
                isManualEntry: false
            ))
            records.append(HealthRecord(
                metricType: MetricType.stepCount,
                timestamp: date,
                primaryValue: Double.random(in: 3000...12000),
                source: "Apple Watch",
                isManualEntry: false
            ))
        }
        return records
    }

    func testGenerateWithEmptyRecords() {
        let url = PDFGenerator.generate(records: [])
        XCTAssertNil(url, "Should return nil for empty records")
    }

    func testGenerateBasicPDF() {
        let records = makeBPRecords(count: 10)
        let url = PDFGenerator.generate(records: records, periodLabel: "Test Period")
        XCTAssertNotNil(url, "Should generate a PDF URL")

        if let url {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "PDF file should exist")
            let data = try? Data(contentsOf: url)
            XCTAssertNotNil(data)
            XCTAssertGreaterThan(data?.count ?? 0, 1000, "PDF should have meaningful size")
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testGenerateWithProfile() {
        let records = makeBPRecords(count: 5)
        let userProfile = UserProfile()
        userProfile.name = "Test User"
        userProfile.age = 35
        userProfile.gender = "Male"
        userProfile.heightCm = 175
        userProfile.weightKg = 75
        userProfile.doctorName = "Dr. Test"
        let profile = PDFGenerator.ProfileData(from: userProfile)

        XCTAssertEqual(profile.name, "Test User")
        XCTAssertEqual(profile.age, 35)

        let url = PDFGenerator.generate(records: records, periodLabel: "Test", profile: profile)
        XCTAssertNotNil(url)

        let urlNoProfile = PDFGenerator.generate(records: records, periodLabel: "Test", profile: nil)
        XCTAssertNotNil(urlNoProfile)

        if let url, let urlNoProfile {
            let sizeWith = (try? Data(contentsOf: url))?.count ?? 0
            let sizeWithout = (try? Data(contentsOf: urlNoProfile))?.count ?? 0
            XCTAssertGreaterThanOrEqual(sizeWith, sizeWithout, "PDF with profile should be at least as large")
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: urlNoProfile)
        }
    }

    func testGenerateWithMultipleMetrics() {
        let records = makeHealthRecords()
        let url = PDFGenerator.generate(records: records, periodLabel: "Multi-metric test")
        XCTAssertNotNil(url)
        if let url {
            let data = try? Data(contentsOf: url)
            XCTAssertGreaterThan(data?.count ?? 0, 1000)
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testGenerateWithSelectedMetrics() {
        let records = makeHealthRecords()
        let selectedMetrics: Set<String> = [MetricType.bloodPressure, MetricType.restingHeartRate]
        let url = PDFGenerator.generate(records: records, selectedMetrics: selectedMetrics, periodLabel: "Selected metrics")
        XCTAssertNotNil(url)
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    func testGenerateWithSingleBPReading() {
        let record = HealthRecord.bloodPressure(systolic: 120, diastolic: 80, pulse: 72)
        let url = PDFGenerator.generate(records: [record])
        XCTAssertNotNil(url, "Should handle single reading")
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    func testGenerateWithManyReadings() {
        let records = makeBPRecords(count: 100)
        let url = PDFGenerator.generate(records: records, periodLabel: "100 readings test")
        XCTAssertNotNil(url)
        if let url {
            let data = try? Data(contentsOf: url)
            XCTAssertGreaterThan(data?.count ?? 0, 5000, "Large report should be bigger")
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testGenerateNonBPOnly() {
        var records: [HealthRecord] = []
        for i in 0..<14 {
            let date = Calendar.current.date(byAdding: .day, value: -14 + i, to: .now)!
            records.append(HealthRecord(
                metricType: MetricType.restingHeartRate,
                timestamp: date,
                primaryValue: Double.random(in: 58...72),
                source: "Apple Watch",
                isManualEntry: false
            ))
        }
        let url = PDFGenerator.generate(records: records)
        XCTAssertNotNil(url, "Should generate PDF for non-BP metrics only")
        if let url { try? FileManager.default.removeItem(at: url) }
    }
}
