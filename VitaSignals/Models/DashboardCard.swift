import Foundation
import SwiftData

@Model
final class DashboardCard {
    var id: UUID
    var sortIndex: Int
    var kind: String          // "default"
    var metricType: String?
    var customChartID: UUID?
    var isHidden: Bool

    init(sortIndex: Int, kind: String, metricType: String? = nil, customChartID: UUID? = nil) {
        self.id = UUID()
        self.sortIndex = sortIndex
        self.kind = kind
        self.metricType = metricType
        self.customChartID = customChartID
        self.isHidden = false
    }
}
