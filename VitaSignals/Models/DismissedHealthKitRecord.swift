import Foundation
import SwiftData

@Model
final class DismissedHealthKitRecord {
    var metricType: String
    var healthKitUUID: String

    init(metricType: String, healthKitUUID: String) {
        self.metricType = metricType
        self.healthKitUUID = healthKitUUID
    }
}
