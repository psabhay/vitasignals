import UIKit
import SwiftUI

struct PDFGenerator {
    static func generate(readings: [BPReading], timeRange: ChartTimeRange) -> URL? {
        let sorted = readings.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { return nil }

        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 40
        let contentWidth = pageWidth - margin * 2

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BP_Report_\(dateStamp()).pdf")

        UIGraphicsBeginPDFContextToFile(url.path, CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight), nil)

        var currentY: CGFloat = 0

        func newPage() {
            UIGraphicsBeginPDFPage()
            currentY = margin
        }

        func checkPageBreak(_ neededHeight: CGFloat) {
            if currentY + neededHeight > pageHeight - margin {
                newPage()
            }
        }

        func drawText(_ text: String, font: UIFont, color: UIColor = .black, x: CGFloat = margin, maxWidth: CGFloat? = nil) -> CGFloat {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            let width = maxWidth ?? contentWidth
            let rect = CGRect(x: x, y: currentY, width: width, height: .greatestFiniteMagnitude)
            let boundingRect = (text as NSString).boundingRect(with: rect.size, options: [.usesLineFragmentOrigin], attributes: attributes, context: nil)
            (text as NSString).draw(in: CGRect(x: x, y: currentY, width: width, height: boundingRect.height), withAttributes: attributes)
            let height = boundingRect.height
            currentY += height
            return height
        }

        func drawLine(y: CGFloat? = nil) {
            let lineY = y ?? currentY
            let context = UIGraphicsGetCurrentContext()!
            context.setStrokeColor(UIColor.systemGray4.cgColor)
            context.setLineWidth(0.5)
            context.move(to: CGPoint(x: margin, y: lineY))
            context.addLine(to: CGPoint(x: pageWidth - margin, y: lineY))
            context.strokePath()
            if y == nil { currentY += 8 }
        }

        // Page 1: Summary
        newPage()

        _ = drawText("Blood Pressure Report", font: .systemFont(ofSize: 24, weight: .bold))
        currentY += 4
        _ = drawText("Generated \(Date.now.formatted(date: .long, time: .shortened))", font: .systemFont(ofSize: 11), color: .systemGray)
        currentY += 4

        if let first = sorted.first, let last = sorted.last {
            _ = drawText("Period: \(first.formattedDateOnly) – \(last.formattedDateOnly) (\(timeRange.rawValue))", font: .systemFont(ofSize: 12), color: .systemGray)
        }
        currentY += 8
        _ = drawText("Total Readings: \(sorted.count)", font: .systemFont(ofSize: 12))
        currentY += 16
        drawLine()
        currentY += 8

        // Averages
        let avgSys = sorted.map(\.systolic).reduce(0, +) / sorted.count
        let avgDia = sorted.map(\.diastolic).reduce(0, +) / sorted.count
        let avgPulse = sorted.map(\.pulse).reduce(0, +) / sorted.count
        let minSys = sorted.map(\.systolic).min()!
        let maxSys = sorted.map(\.systolic).max()!
        let minDia = sorted.map(\.diastolic).min()!
        let maxDia = sorted.map(\.diastolic).max()!

        _ = drawText("Summary Statistics", font: .systemFont(ofSize: 18, weight: .semibold))
        currentY += 12

        let statFont = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        let labelFont = UIFont.systemFont(ofSize: 13, weight: .medium)

        _ = drawText("Average Blood Pressure:", font: labelFont)
        currentY += 4
        _ = drawText("  \(avgSys)/\(avgDia) mmHg", font: statFont)
        currentY += 8

        _ = drawText("Average Pulse:", font: labelFont)
        currentY += 4
        _ = drawText("  \(avgPulse) bpm", font: statFont)
        currentY += 8

        _ = drawText("Systolic Range:", font: labelFont)
        currentY += 4
        _ = drawText("  \(minSys) – \(maxSys) mmHg", font: statFont)
        currentY += 8

        _ = drawText("Diastolic Range:", font: labelFont)
        currentY += 4
        _ = drawText("  \(minDia) – \(maxDia) mmHg", font: statFont)
        currentY += 16
        drawLine()
        currentY += 8

        // Category breakdown
        _ = drawText("Category Breakdown", font: .systemFont(ofSize: 18, weight: .semibold))
        currentY += 12

        let categoryGroups = Dictionary(grouping: sorted) { $0.category }
        let categories: [BPCategory] = [.normal, .elevated, .highStage1, .highStage2, .crisis]
        for cat in categories {
            let count = categoryGroups[cat]?.count ?? 0
            if count > 0 {
                let pct = Int(Double(count) / Double(sorted.count) * 100)
                _ = drawText("  \(cat.rawValue): \(count) (\(pct)%)", font: statFont)
                currentY += 4
            }
        }
        currentY += 16
        drawLine()
        currentY += 8

        // Context breakdown
        _ = drawText("Readings by Context", font: .systemFont(ofSize: 18, weight: .semibold))
        currentY += 12

        let contextGroups = Dictionary(grouping: sorted) { $0.activityContext }
        let contextSorted = contextGroups.sorted { ($0.value.count) > ($1.value.count) }
        for (context, contextReadings) in contextSorted {
            let ctxAvgSys = contextReadings.map(\.systolic).reduce(0, +) / contextReadings.count
            let ctxAvgDia = contextReadings.map(\.diastolic).reduce(0, +) / contextReadings.count
            checkPageBreak(20)
            _ = drawText("  \(context.rawValue): \(contextReadings.count) readings, avg \(ctxAvgSys)/\(ctxAvgDia)", font: statFont)
            currentY += 4
        }

        // Page 2+: All readings table
        newPage()
        _ = drawText("All Readings", font: .systemFont(ofSize: 18, weight: .semibold))
        currentY += 12

        // Table header
        let colWidths: [CGFloat] = [140, 70, 70, 50, 130, 0]
        let headers = ["Date & Time", "Systolic", "Diastolic", "Pulse", "Context", "Category"]
        let headerFont = UIFont.systemFont(ofSize: 10, weight: .bold)
        var colX = margin
        for (i, header) in headers.enumerated() {
            let w = i < colWidths.count - 1 ? colWidths[i] : contentWidth - colX + margin
            let attributes: [NSAttributedString.Key: Any] = [.font: headerFont, .foregroundColor: UIColor.systemGray]
            (header as NSString).draw(in: CGRect(x: colX, y: currentY, width: w, height: 16), withAttributes: attributes)
            colX += w
        }
        currentY += 18
        drawLine()
        currentY += 4

        let cellFont = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        for reading in sorted.reversed() {
            checkPageBreak(20)
            colX = margin
            let cells = [
                reading.formattedDate,
                "\(reading.systolic) mmHg",
                "\(reading.diastolic) mmHg",
                "\(reading.pulse)",
                reading.activityContext.rawValue,
                reading.category.rawValue
            ]
            for (i, cell) in cells.enumerated() {
                let w = i < colWidths.count - 1 ? colWidths[i] : contentWidth - colX + margin
                let color: UIColor = {
                    switch i {
                    case 1: return .systemRed
                    case 2: return .systemBlue
                    case 3: return .systemPink
                    default: return .label
                    }
                }()
                let attributes: [NSAttributedString.Key: Any] = [.font: cellFont, .foregroundColor: color]
                (cell as NSString).draw(in: CGRect(x: colX, y: currentY, width: w, height: 14), withAttributes: attributes)
                colX += w
            }
            currentY += 16

            if !reading.notes.isEmpty {
                let noteAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.italicSystemFont(ofSize: 9),
                    .foregroundColor: UIColor.systemGray
                ]
                ("  Note: " + reading.notes as NSString).draw(
                    in: CGRect(x: margin + 8, y: currentY, width: contentWidth - 16, height: 12),
                    withAttributes: noteAttr
                )
                currentY += 14
            }
        }

        // Footer on last page
        currentY = pageHeight - margin - 20
        let footerAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.systemGray
        ]
        ("BP Logger Report – For medical professional review" as NSString).draw(
            at: CGPoint(x: margin, y: currentY),
            withAttributes: footerAttr
        )

        UIGraphicsEndPDFContext()
        return url
    }

    private static func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }
}
