import SwiftUI

// MARK: - Downsample

/// Thin an array of records to at most `maxPoints` evenly spaced entries.
/// Keeps first and last for accurate range display.
func downsample(_ records: [HealthRecord], maxPoints: Int = ChartResolution.card) -> [HealthRecord] {
    guard records.count > maxPoints else { return records }
    let step = Double(records.count - 1) / Double(maxPoints - 1)
    var result: [HealthRecord] = []
    result.reserveCapacity(maxPoints)
    for i in 0..<maxPoints {
        let index = Int((Double(i) * step).rounded())
        result.append(records[index])
    }
    return result
}

// MARK: - Ordered Metrics With Data

/// Returns metric types that have data, ordered by registry (curated first, then catalog, grouped by category).
func orderedMetricsWithData(from availableTypes: Set<String>) -> [String] {
    var ordered: [String] = []
    var seen = Set<String>()
    for category in MetricCategory.allCases {
        for def in MetricRegistry.definitions(for: category) where availableTypes.contains(def.type) {
            if seen.insert(def.type).inserted {
                ordered.append(def.type)
            }
        }
    }
    for type in availableTypes.sorted() where !seen.contains(type) {
        ordered.append(type)
    }
    return ordered
}

// MARK: - Stat Column

/// Reusable stat column used in summary cards across chart views.
func statColumn(title: String, value: String, unit: String) -> some View {
    VStack(spacing: 4) {
        Text(title).font(.caption).foregroundStyle(.secondary)
        Text(value).font(.title2.bold().monospacedDigit())
        Text(unit).font(.caption2).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
}
