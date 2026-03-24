import Foundation
import SwiftData

@Model
final class MetricGoal {
    var id: UUID
    var metricType: String
    var targetType: String      // "below" | "above" | "range"
    var targetValue: Double
    var targetValueHigh: Double?
    var createdAt: Date
    var isActive: Bool

    init(
        metricType: String,
        targetType: String,
        targetValue: Double,
        targetValueHigh: Double? = nil
    ) {
        self.id = UUID()
        self.metricType = metricType
        self.targetType = targetType
        self.targetValue = targetValue
        self.targetValueHigh = targetValueHigh
        self.createdAt = .now
        self.isActive = true
    }

    var targetDescription: String {
        guard let def = MetricRegistry.definition(for: metricType) else {
            return "\(targetType) \(String(format: "%.0f", targetValue))"
        }
        switch targetType {
        case "below":
            if metricType == MetricType.bloodPressure, let high = targetValueHigh {
                return "Below \(Int(targetValue))/\(Int(high))"
            }
            return "Below \(def.formatValue(targetValue)) \(def.unit)"
        case "above":
            return "Above \(def.formatValue(targetValue)) \(def.unit)"
        case "range":
            return "\(def.formatValue(targetValue))–\(def.formatValue(targetValueHigh ?? targetValue)) \(def.unit)"
        default:
            return ""
        }
    }
}
