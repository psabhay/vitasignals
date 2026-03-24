import Foundation
import SwiftData

@Model
final class DashboardCard {
    var id: UUID
    var sortIndex: Int
    var kind: String          // "default"
    var metricType: String?
    var savedViewID: UUID?    // unused, kept for migration compatibility
    var isHidden: Bool

    init(sortIndex: Int, kind: String, metricType: String? = nil, savedViewID: UUID? = nil) {
        self.id = UUID()
        self.sortIndex = sortIndex
        self.kind = kind
        self.metricType = metricType
        self.savedViewID = savedViewID
        self.isHidden = false
    }
}
