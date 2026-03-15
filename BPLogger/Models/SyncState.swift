import Foundation
import SwiftData

@Model
final class SyncState {
    var metricType: String
    var lastSyncDate: Date?
    var isAvailable: Bool

    init(metricType: String, lastSyncDate: Date? = nil, isAvailable: Bool = false) {
        self.metricType = metricType
        self.lastSyncDate = lastSyncDate
        self.isAvailable = isAvailable
    }
}
