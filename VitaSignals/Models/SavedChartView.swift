import Foundation
import SwiftData

@Model
final class SavedChartView {
    var id: UUID
    var name: String
    var timeRangeRaw: String
    var customStartDate: Date
    var customEndDate: Date
    var selectedMetrics: [String]
    var createdAt: Date
    var savedZoomScale: Double
    var savedPanOffset: Double

    init(
        name: String,
        timeRange: String,
        customStartDate: Date = .now,
        customEndDate: Date = .now,
        selectedMetrics: [String],
        zoomScale: Double = 1.0,
        panOffset: Double = 0.0
    ) {
        self.id = UUID()
        self.name = name
        self.timeRangeRaw = timeRange
        self.customStartDate = customStartDate
        self.customEndDate = customEndDate
        self.selectedMetrics = selectedMetrics
        self.createdAt = .now
        self.savedZoomScale = zoomScale
        self.savedPanOffset = panOffset
    }
}
