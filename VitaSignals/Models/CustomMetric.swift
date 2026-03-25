import Foundation
import SwiftData
import SwiftUI

@Model
final class CustomMetric {
    var id: UUID
    var name: String
    var unit: String
    var icon: String
    var colorIndex: Int
    var isCumulative: Bool
    var inputMin: Double
    var inputMax: Double
    var inputStep: Double
    var metricType: String
    var createdAt: Date

    // MARK: - Reminder
    var reminderEnabled: Bool = false
    var reminderHour: Int = 20       // Default 8 PM
    var reminderMinute: Int = 0
    var reminderFrequency: String = "daily"  // "daily", "weekdays", "custom"
    var reminderCustomDays: Int = 0          // Bitmask: bit 0 = Sunday(1), bit 1 = Monday(2), …, bit 6 = Saturday(7)

    /// Weekday numbers (1=Sun … 7=Sat) the reminder should fire on.
    var effectiveReminderDays: [Int] {
        switch reminderFrequency {
        case "weekdays": return [2, 3, 4, 5, 6]
        case "custom":
            var days: [Int] = []
            for i in 0..<7 where reminderCustomDays & (1 << i) != 0 {
                days.append(i + 1)
            }
            return days.isEmpty ? Array(1...7) : days
        default: return Array(1...7)
        }
    }

    init(
        name: String,
        unit: String,
        icon: String = "star.fill",
        colorIndex: Int = 0,
        isCumulative: Bool = true,
        inputMin: Double = 0,
        inputMax: Double = 100,
        inputStep: Double = 1
    ) {
        let id = UUID()
        self.id = id
        self.name = name
        self.unit = unit
        self.icon = icon
        self.colorIndex = colorIndex
        self.isCumulative = isCumulative
        self.inputMin = inputMin
        self.inputMax = inputMax
        self.inputStep = inputStep
        self.metricType = "custom_\(id.uuidString)"
        self.createdAt = .now
    }

    var color: Color {
        Self.palette[colorIndex % Self.palette.count]
    }

    func toMetricDefinition() -> MetricDefinition {
        MetricDefinition(
            type: metricType,
            name: name,
            unit: unit,
            icon: icon,
            color: color,
            category: .custom,
            chartStyle: isCumulative ? .bar : .line,
            aggregation: isCumulative ? .sum : .average,
            referenceMin: nil,
            referenceMax: nil,
            inputMin: inputMin,
            inputMax: inputMax,
            inputStep: inputStep,
            hkQuantityType: nil,
            hkUnit: nil,
            isCumulative: isCumulative
        )
    }

    // MARK: - Available Icons

    static let availableIcons: [String] = [
        "cup.and.saucer.fill", "mug.fill", "wineglass.fill", "fork.knife",
        "pill.fill", "cross.fill", "heart.fill", "brain.head.profile",
        "figure.walk", "dumbbell.fill", "flame.fill", "leaf.fill",
        "drop.fill", "bolt.fill", "moon.fill", "sun.max.fill",
        "star.fill", "face.smiling", "book.fill", "smoke.fill",
        "bed.double.fill", "clock.fill", "music.note", "paintpalette.fill",
    ]

    // MARK: - Color Palette

    static let palette: [Color] = [
        .blue, .purple, .pink, .red, .orange, .yellow,
        .green, .mint, .teal, .cyan, .indigo, .brown,
    ]
}
