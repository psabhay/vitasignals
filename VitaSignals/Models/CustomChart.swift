import Foundation
import SwiftData

@Model
final class CustomChart {
    var id: UUID
    var name: String
    var leftMetricType: String
    var rightMetricType: String
    var createdAt: Date

    init(name: String, leftMetricType: String, rightMetricType: String) {
        self.id = UUID()
        self.name = name
        self.leftMetricType = leftMetricType
        self.rightMetricType = rightMetricType
        self.createdAt = .now
    }
}
