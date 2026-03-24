import SwiftUI
import SwiftData
import Charts

// MARK: - Hero Card

struct HeroCardView: View {
    let data: HeroCardData
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: data.definitionIcon)
                        .foregroundStyle(data.definitionColor)
                        .font(.caption)
                    Text(data.definitionName)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(data.timeSinceReading, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(data.formattedValue)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(data.definitionUnit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    if let category = data.bpCategory {
                        CategoryBadge(category: category)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: data.trend.icon)
                            .font(.caption2.bold())
                        if let avgFormatted = data.sevenDayAvgFormatted {
                            Text("7d avg: \(avgFormatted)")
                                .font(.caption.monospacedDigit())
                        }
                    }
                    .foregroundStyle(trendColor)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Last \(data.definitionName) reading: \(data.formattedValue)")
        .accessibilityHint("Tap to view details")
    }

    private var trendColor: Color {
        switch data.trend {
        case .up: return data.bpCategory != nil ? .orange : .green
        case .down: return data.bpCategory != nil ? .green : .orange
        case .flat: return .secondary
        }
    }
}

// MARK: - Smart Summary

struct SmartSummaryView: View {
    let data: SmartSummaryData
    @ObservedObject var syncManager: HealthSyncManager
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var dataStore: HealthDataStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let name = data.userName {
                Text("\(data.greeting), \(name)")
                    .font(.title2.bold())
            } else {
                Text(data.greeting)
                    .font(.title2.bold())
            }

            if !data.contextLine.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: data.contextIcon)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(data.contextLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if syncManager.isSyncing {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text(syncManager.syncProgress)
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if let lastSync = syncManager.lastSyncDate {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                    Text("Synced \(lastSync, format: .relative(presentation: .named))")
                        .font(.caption)
                }
                .foregroundStyle(.tertiary)
            } else if syncManager.permissionDenied {
                Button {
                    Task {
                        await syncManager.syncAll(container: modelContext.container, dataStore: dataStore)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.circle")
                            .foregroundStyle(.pink)
                        Text("Connect Apple Health for more insights")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Quick Log Row

struct QuickLogRowView: View {
    let metrics: [QuickLogMetric]
    var onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Quick Log")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(metrics) { metric in
                        Button {
                            onTap(metric.id)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: metric.icon)
                                    .font(.title3)
                                    .foregroundStyle(metric.color)
                                Text(metric.name)
                                    .font(.caption2.bold())
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                            .frame(width: 68, height: 64)
                            .background(metric.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(metric.color.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Log \(metric.name)")
                        .accessibilityHint("Opens form to add a new reading")
                    }
                }
            }
        }
    }
}

// MARK: - Moving Averages Card

struct MovingAveragesCardView: View {
    let rows: [MovingAverageRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("7-Day Averages")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("vs prior week")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ForEach(rows) { row in
                HStack(spacing: 10) {
                    Image(systemName: row.icon)
                        .foregroundStyle(row.color)
                        .font(.caption)
                        .frame(width: 20)
                    Text(row.name)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text(row.currentAvg)
                        .font(.subheadline.bold().monospacedDigit())
                    if let improving = row.improving {
                        Image(systemName: improving ? "arrow.down.right" : "arrow.up.right")
                            .font(.caption2.bold())
                            .foregroundStyle(improving == row.lowerIsBetter ? .green : (improving ? .green : .orange))
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Weekly Recap Card

struct WeeklyRecapCardView: View {
    let data: WeeklyRecapData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This Week")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(data.weekLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text("\(data.thisWeekCount)")
                        .font(.title2.bold().monospacedDigit())
                    Text("readings")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if data.lastWeekCount > 0 {
                    VStack(spacing: 2) {
                        let diff = data.thisWeekCount - data.lastWeekCount
                        HStack(spacing: 2) {
                            Image(systemName: diff >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption2)
                            Text("\(abs(diff))")
                                .font(.caption.bold().monospacedDigit())
                        }
                        .foregroundStyle(diff >= 0 ? .green : .orange)
                        Text("vs last week")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if data.streak >= 3 {
                    VStack(spacing: 2) {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("\(data.streak)")
                                .font(.caption.bold().monospacedDigit())
                        }
                        Text("day streak")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            if !data.metricSummaries.isEmpty {
                Divider()
                ForEach(data.metricSummaries) { summary in
                    HStack(spacing: 10) {
                        Image(systemName: summary.icon)
                            .foregroundStyle(summary.color)
                            .font(.caption)
                            .frame(width: 20)
                        Text(summary.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(summary.thisWeekAvg)
                            .font(.caption.bold().monospacedDigit())
                        if let lw = summary.lastWeekAvg {
                            Text("vs \(lw)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if let improving = summary.improving {
                            Image(systemName: improving ? "arrow.down.right" : "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(improving == summary.lowerIsBetter ? .green : (improving ? .green : .orange))
                        }
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Nudge Card

struct NudgeCardView: View {
    let item: NudgeItem
    var onTap: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .foregroundStyle(item.color)
                .font(.title3)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Log \(item.name)")
                    .font(.subheadline.bold())
                Text(item.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss \(item.name) reminder")
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityLabel("Log \(item.name). \(item.message)")
        .accessibilityHint("Tap to add a reading")
    }
}

// MARK: - Goal Progress Card

struct GoalProgressCardView: View {
    let data: GoalProgressData

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: data.icon)
                    .foregroundStyle(data.color)
                    .font(.caption)
                Text(data.name)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(data.targetDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: data.trend.icon)
                    .font(.caption2.bold())
                    .foregroundStyle(data.trend == .up ? .green : (data.trend == .down ? .orange : .secondary))
            }

            ProgressView(value: data.fraction)
                .tint(progressColor)

            HStack {
                Text("\(data.readingsInTarget) of \(data.readingsThisWeek) in target")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(data.fraction * 100))%")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(progressColor)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var progressColor: Color {
        if data.fraction >= 0.7 { return .green }
        if data.fraction >= 0.4 { return .orange }
        return .red
    }
}

// MARK: - Set Goal Sheet

struct SetGoalSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataStore: HealthDataStore

    @State private var selectedMetric: String = ""
    @State private var targetType: String = "below"
    @State private var targetValue: Double = 120
    @State private var targetValueHigh: Double = 80

    var editingGoal: MetricGoal?

    private var availableMetrics: [(String, MetricDefinition)] {
        var result: [(String, MetricDefinition)] = []
        for category in MetricCategory.allCases {
            for def in MetricRegistry.definitions(for: category) where dataStore.availableMetricTypes.contains(def.type) {
                result.append((def.type, def))
            }
        }
        return result
    }

    private var selectedDef: MetricDefinition? {
        MetricRegistry.definition(for: selectedMetric)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Metric") {
                    Picker("Metric", selection: $selectedMetric) {
                        Text("Select...").tag("")
                        ForEach(availableMetrics, id: \.0) { type, def in
                            Label(def.name, systemImage: def.icon).tag(type)
                        }
                    }
                }

                if !selectedMetric.isEmpty {
                    Section("Target") {
                        Picker("Type", selection: $targetType) {
                            Text("Below").tag("below")
                            Text("Above").tag("above")
                            Text("Range").tag("range")
                        }
                        .pickerStyle(.segmented)

                        if let def = selectedDef {
                            HStack {
                                Text(targetType == "range" ? "Min" : "Target")
                                Spacer()
                                TextField("Value", value: $targetValue, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                Text(def.unit)
                                    .foregroundStyle(.secondary)
                            }

                            if targetType == "range" || (selectedMetric == MetricType.bloodPressure && targetType == "below") {
                                HStack {
                                    Text(selectedMetric == MetricType.bloodPressure ? "Diastolic" : "Max")
                                    Spacer()
                                    TextField("Value", value: $targetValueHigh, format: .number)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 80)
                                    Text(selectedDef?.unit ?? "")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(editingGoal == nil ? "Set Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveGoal() }
                        .disabled(selectedMetric.isEmpty)
                }
            }
            .onAppear {
                if let goal = editingGoal {
                    selectedMetric = goal.metricType
                    targetType = goal.targetType
                    targetValue = goal.targetValue
                    targetValueHigh = goal.targetValueHigh ?? 80
                }
            }
        }
    }

    private func saveGoal() {
        if let goal = editingGoal {
            goal.metricType = selectedMetric
            goal.targetType = targetType
            goal.targetValue = targetValue
            goal.targetValueHigh = (targetType == "range" || (selectedMetric == MetricType.bloodPressure && targetType == "below")) ? targetValueHigh : nil
        } else {
            let goal = MetricGoal(
                metricType: selectedMetric,
                targetType: targetType,
                targetValue: targetValue,
                targetValueHigh: (targetType == "range" || (selectedMetric == MetricType.bloodPressure && targetType == "below")) ? targetValueHigh : nil
            )
            modelContext.insert(goal)
        }
        try? modelContext.save()
        dismiss()
    }
}
