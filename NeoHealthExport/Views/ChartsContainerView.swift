import SwiftUI
import SwiftData
import Charts

enum ChartTimeRange: String, CaseIterable, Identifiable {
    case week = "7 Days"
    case twoWeeks = "14 Days"
    case month = "30 Days"
    case threeMonths = "90 Days"
    case all = "All Time"
    case custom = "Custom"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .week: return 7
        case .twoWeeks: return 14
        case .month: return 30
        case .threeMonths: return 90
        case .all, .custom: return nil
        }
    }
}

/// Passed from Charts → Reports to pre-populate export filters.
struct ChartExportRequest: Equatable {
    let metrics: Set<String>
    let startDate: Date
    let endDate: Date
}

struct ChartsContainerView: View {
    @EnvironmentObject var dataStore: HealthDataStore
    @State private var timeRange: ChartTimeRange = .week
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var customEndDate: Date = .now
    @State private var expandedMetric: String?
    @State private var selectedMetrics: Set<String> = []
    @State private var showFilterSheet = false
    @State private var hasInitializedMetrics = false

    var onExport: ((ChartExportRequest) -> Void)?

    private var effectiveDateRange: (start: Date, end: Date) {
        if timeRange == .custom {
            return (customStartDate, customEndDate)
        }
        let end = Date.now
        if let days = timeRange.days {
            let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
            return (start, end)
        }
        // "All Time" — find earliest record
        let earliest = allMetricsWithData
            .flatMap { dataStore.records(for: $0) }
            .map(\.timestamp)
            .min() ?? end
        return (earliest, end)
    }

    private func filteredRecords(for metricType: String) -> [HealthRecord] {
        let result = dataStore.records(for: metricType)
        let range = effectiveDateRange
        return result.filter { $0.timestamp >= range.start && $0.timestamp <= range.end }
    }

    /// All metric types that have ANY data (independent of date range).
    /// Ordered by registry (curated first, then catalog, grouped by category).
    private var allMetricsWithData: [String] {
        let types = dataStore.availableMetricTypes
        // Walk all categories in order — includes both curated and catalog metrics
        var ordered: [String] = []
        var seen = Set<String>()
        for category in MetricCategory.allCases {
            for def in MetricRegistry.definitions(for: category) where types.contains(def.type) {
                if seen.insert(def.type).inserted {
                    ordered.append(def.type)
                }
            }
        }
        // Include any types not known to the registry at all
        for type in types.sorted() where !seen.contains(type) {
            ordered.append(type)
        }
        return ordered
    }

    /// Metrics the user selected AND that have data in the current date range.
    private var visibleMetricTypes: [String] {
        allMetricsWithData
            .filter { selectedMetrics.contains($0) }
            .filter { !filteredRecords(for: $0).isEmpty }
    }

    private var xDomain: ClosedRange<Date> {
        let range = effectiveDateRange
        return range.start...range.end
    }

    private var dateRangeLabel: String {
        if timeRange == .custom {
            let fmt = Date.FormatStyle().month(.abbreviated).day()
            return "\(customStartDate.formatted(fmt)) – \(customEndDate.formatted(fmt))"
        }
        return timeRange.rawValue
    }

    private var metricsFilterLabel: String {
        let selected = allMetricsWithData.filter { selectedMetrics.contains($0) }.count
        let total = allMetricsWithData.count
        if selected == total {
            return "All \(total) metrics"
        }
        return "\(selected) of \(total) metrics"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Inline filter bar — always visible, tappable
                    filterBar

                    if allMetricsWithData.isEmpty {
                        ContentUnavailableView(
                            "No Data",
                            systemImage: "chart.xyaxis.line",
                            description: Text("No health data recorded yet. Add records or sync from Apple Health.")
                        )
                        .padding(.top, 60)
                    } else if visibleMetricTypes.isEmpty {
                        ContentUnavailableView(
                            "No Matching Data",
                            systemImage: "chart.xyaxis.line",
                            description: Text("No records match the current filters. Tap the filter bar to adjust.")
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(visibleMetricTypes, id: \.self) { type in
                            chartCard(for: type)
                        }
                    }
                }
                .padding(.bottom)
            }
            .navigationTitle("Charts")
            .withProfileButton()
            .sheet(isPresented: $showFilterSheet) {
                ChartFilterSheet(
                    timeRange: $timeRange,
                    customStartDate: $customStartDate,
                    customEndDate: $customEndDate,
                    selectedMetrics: $selectedMetrics
                )
            }
            .onAppear {
                if !hasInitializedMetrics {
                    selectedMetrics = Set(allMetricsWithData)
                    hasInitializedMetrics = true
                }
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            Button {
                showFilterSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(dateRangeLabel)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        Text(metricsFilterLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("Edit")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            if let onExport, !visibleMetricTypes.isEmpty {
                Button {
                    let range = effectiveDateRange
                    onExport(ChartExportRequest(
                        metrics: Set(visibleMetricTypes),
                        startDate: range.start,
                        endDate: range.end
                    ))
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.accentColor)
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Chart Card

    @ViewBuilder
    private func chartCard(for metricType: String) -> some View {
        let isExpanded = expandedMetric == metricType
        let records = Array(filteredRecords(for: metricType).reversed())

        if isExpanded {
            expandedContent(for: metricType, records: records)
        } else {
            compactCard(for: metricType, records: records)
        }
    }

    @ViewBuilder
    private func compactCard(for metricType: String, records: [HealthRecord]) -> some View {
        if metricType == MetricType.bloodPressure {
            ComparisonBPChart(records: records, xDomain: xDomain) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    expandedMetric = metricType
                }
            }
        } else if let def = MetricRegistry.definition(for: metricType) {
            ComparisonMetricChart(records: records, definition: def, xDomain: xDomain) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    expandedMetric = metricType
                }
            }
        }
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private func expandedContent(for metricType: String, records: [HealthRecord]) -> some View {
        VStack(spacing: 0) {
            // Tappable collapse header
            expandedHeader(for: metricType)

            if metricType == MetricType.bloodPressure {
                bpExpandedCharts(records: records)
            } else if let def = MetricRegistry.definition(for: metricType) {
                genericExpandedContent(records: records, definition: def)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.tint.opacity(0.3), lineWidth: 1.5)
        )
        .padding(.horizontal)
    }

    private func expandedHeader(for metricType: String) -> some View {
        let def = MetricRegistry.definition(for: metricType)
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                expandedMetric = nil
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: def?.icon ?? "chart.xyaxis.line")
                    .foregroundStyle(def?.color ?? .primary)
                    .font(.subheadline)
                Text(def?.name ?? metricType)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - BP Expanded

    @ViewBuilder
    private func bpExpandedCharts(records: [HealthRecord]) -> some View {
        VStack(spacing: 16) {
            BPTrendChart(records: records)
            PulseChart(records: records)
            BPSummaryCard(records: records)
            WeeklyAveragesChart(records: records)
            MorningVsEveningChart(records: records)
            MAPTrendChart(records: records)
        }
        .padding(.bottom)
    }

    // MARK: - Generic Expanded

    @ViewBuilder
    private func genericExpandedContent(records: [HealthRecord], definition: MetricDefinition) -> some View {
        VStack(spacing: 16) {
            GenericMetricChart(records: records, definition: definition)

            // Summary stats
            if !records.isEmpty {
                genericSummaryStats(records: records, definition: definition)
            }

            // Recent records
            if !records.isEmpty {
                genericRecentRecords(records: records, definition: definition)
            }
        }
        .padding(.bottom)
    }

    private func genericSummaryStats(records: [HealthRecord], definition: MetricDefinition) -> some View {
        let values = records.map(\.primaryValue)
        let count = Double(max(values.count, 1))
        let avg = values.reduce(0, +) / count
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 0

        return VStack(spacing: 14) {
            HStack {
                Text("Summary")
                    .font(.headline)
                Spacer()
                Text("\(records.count) records")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                statColumn(title: "Average", value: definition.formatValue(avg), unit: definition.unit)
                Divider().frame(height: 50)
                statColumn(title: "Minimum", value: definition.formatValue(minV), unit: definition.unit)
                Divider().frame(height: 50)
                statColumn(title: "Maximum", value: definition.formatValue(maxV), unit: definition.unit)
            }

            if let refMin = definition.referenceMin, let refMax = definition.referenceMax {
                let inRange = values.filter { $0 >= refMin && $0 <= refMax }.count
                let pct = values.isEmpty ? 0 : Int(Double(inRange) / count * 100)
                HStack {
                    Text("In normal range (\(definition.formatValue(refMin))–\(definition.formatValue(refMax)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(pct)%")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(pct >= 70 ? .green : .orange)
                }
            }
        }
        .padding(.horizontal)
    }

    private func statColumn(title: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold().monospacedDigit())
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func genericRecentRecords(records: [HealthRecord], definition: MetricDefinition) -> some View {
        let recent = Array(records.reversed().prefix(10))
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Records").font(.headline)
                Spacer()
                Text("\(records.count) total").font(.caption).foregroundStyle(.secondary)
            }

            ForEach(recent) { record in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.formattedPrimaryValue)
                            .font(.subheadline.bold().monospacedDigit())
                        Text(definition.unit).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(record.formattedDateOnly).font(.caption).foregroundStyle(.secondary)
                        Text(record.formattedTimeOnly).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
                if record.id != recent.last?.id {
                    Divider()
                }
            }

            if records.count > 10 {
                Text("Showing 10 of \(records.count) records")
                    .font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Chart Filter Sheet

struct ChartFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataStore: HealthDataStore
    @Binding var timeRange: ChartTimeRange
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    @Binding var selectedMetrics: Set<String>

    /// All metrics that have any data — not filtered by date range.
    private var allMetricsWithData: [String] {
        let types = dataStore.availableMetricTypes
        var ordered: [String] = []
        var seen = Set<String>()
        for category in MetricCategory.allCases {
            for def in MetricRegistry.definitions(for: category) where types.contains(def.type) {
                if seen.insert(def.type).inserted {
                    ordered.append(def.type)
                }
            }
        }
        for type in types.sorted() where !seen.contains(type) {
            ordered.append(type)
        }
        return ordered
    }

    private var presetRanges: [ChartTimeRange] {
        ChartTimeRange.allCases.filter { $0 != .custom }
    }

    private var allSelected: Bool {
        Set(allMetricsWithData).isSubset(of: selectedMetrics)
    }

    var body: some View {
        NavigationStack {
            List {
                dateRangeSection
                metricSelectionSection
            }
            .navigationTitle("Chart Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Date Range

    @ViewBuilder
    private var dateRangeSection: some View {
        Section("Date Range") {
            dateRangePresets
            customDateRange
        }
    }

    @ViewBuilder
    private var dateRangePresets: some View {
        let ranges = presetRanges
        ForEach(ranges, id: \.self) { range in
            dateRangeButton(for: range)
        }
    }

    private func dateRangeButton(for range: ChartTimeRange) -> some View {
        Button {
            timeRange = range
        } label: {
            HStack {
                Text(range.rawValue)
                    .foregroundStyle(.primary)
                Spacer()
                if timeRange == range {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private var customDateRange: some View {
        DisclosureGroup {
            DatePicker("From", selection: $customStartDate, displayedComponents: .date)
                .onChange(of: customStartDate) { _, _ in timeRange = .custom }
            DatePicker("To", selection: $customEndDate, displayedComponents: .date)
                .onChange(of: customEndDate) { _, _ in timeRange = .custom }
        } label: {
            HStack {
                Text("Custom Range")
                    .foregroundStyle(.primary)
                Spacer()
                if timeRange == .custom {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    // MARK: - Metric Selection

    private var metricSelectionSection: some View {
        Section {
            ForEach(MetricCategory.allCases) { category in
                categoryRow(for: category)
            }
        } header: {
            HStack {
                Text("Metrics")
                Spacer()
                if allSelected {
                    Button("Deselect All") {
                        selectedMetrics.subtract(allMetricsWithData)
                    }
                    .font(.caption)
                } else {
                    Button("Select All") {
                        selectedMetrics.formUnion(allMetricsWithData)
                    }
                    .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func categoryRow(for category: MetricCategory) -> some View {
        let defs = MetricRegistry.definitions(for: category)
            .filter { allMetricsWithData.contains($0.type) }

        if !defs.isEmpty {
            let selectedCount = defs.filter { selectedMetrics.contains($0.type) }.count
            DisclosureGroup {
                ForEach(defs, id: \.type) { def in
                    metricToggle(for: def)
                }
            } label: {
                Label {
                    HStack {
                        Text(category.rawValue)
                        Spacer()
                        Text("\(selectedCount)/\(defs.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: category.icon)
                        .foregroundStyle(category.color)
                }
            }
        }
    }

    private func metricToggle(for def: MetricDefinition) -> some View {
        Toggle(isOn: Binding(
            get: { selectedMetrics.contains(def.type) },
            set: { on in
                if on {
                    selectedMetrics.insert(def.type)
                } else {
                    selectedMetrics.remove(def.type)
                }
            }
        )) {
            Label(def.name, systemImage: def.icon)
                .foregroundStyle(def.color)
        }
    }
}

// MARK: - Generic Metric Chart Card

struct GenericMetricChart: View {
    let records: [HealthRecord]
    let definition: MetricDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(definition.name)
                .font(.headline)
            if let refMin = definition.referenceMin, let refMax = definition.referenceMax {
                Text("Normal: \(definition.formatValue(refMin))–\(definition.formatValue(refMax)) \(definition.unit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(records) { record in
                    if definition.chartStyle == .bar {
                        BarMark(
                            x: .value("Date", record.timestamp, unit: .day),
                            y: .value(definition.unit, record.primaryValue)
                        )
                        .foregroundStyle(definition.color.opacity(0.7))
                    } else {
                        LineMark(
                            x: .value("Date", record.timestamp),
                            y: .value(definition.unit, record.primaryValue)
                        )
                        .foregroundStyle(definition.color)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", record.timestamp),
                            y: .value(definition.unit, record.primaryValue)
                        )
                        .foregroundStyle(definition.color)
                        .symbolSize(records.count > 30 ? 10 : 20)
                    }
                }

                if let refMin = definition.referenceMin {
                    RuleMark(y: .value("Ref Min", refMin))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .foregroundStyle(.green.opacity(0.5))
                }
                if let refMax = definition.referenceMax {
                    RuleMark(y: .value("Ref Max", refMax))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .foregroundStyle(.green.opacity(0.5))
                }
            }
            .frame(height: 220)
            .chartYAxis { AxisMarks(position: .leading) }

            if !records.isEmpty {
                let avg = records.map(\.primaryValue).reduce(0, +) / Double(records.count)
                let minV = records.map(\.primaryValue).min() ?? 0
                let maxV = records.map(\.primaryValue).max() ?? 0
                HStack {
                    Text("Avg: \(definition.formatValue(avg)) \(definition.unit)")
                    Spacer()
                    Text("Range: \(definition.formatValue(minV)) – \(definition.formatValue(maxV))")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - BP Trend Line Chart

struct BPTrendChart: View {
    let records: [HealthRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Blood Pressure Trend")
                .font(.headline)

            Chart {
                ForEach(records) { record in
                    LineMark(
                        x: .value("Date", record.timestamp),
                        y: .value("mmHg", record.systolic),
                        series: .value("Type", "Systolic")
                    )
                    .foregroundStyle(.red)
                    .symbol(.circle)
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", record.timestamp),
                        y: .value("mmHg", record.diastolic),
                        series: .value("Type", "Diastolic")
                    )
                    .foregroundStyle(.blue)
                    .symbol(.diamond)
                    .interpolationMethod(.catmullRom)
                }

                RuleMark(y: .value("Target Sys", 120))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .foregroundStyle(.green.opacity(0.5))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("120").font(.caption2).foregroundStyle(.green)
                    }
                RuleMark(y: .value("Target Dia", 80))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .foregroundStyle(.green.opacity(0.3))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("80").font(.caption2).foregroundStyle(.green)
                    }
            }
            .frame(height: 220)
            .chartYAxis { AxisMarks(position: .leading) }
            .chartLegend(position: .bottom)

            HStack(spacing: 16) {
                Label("Systolic", systemImage: "circle.fill")
                    .font(.caption2).foregroundStyle(.red)
                Label("Diastolic", systemImage: "diamond.fill")
                    .font(.caption2).foregroundStyle(.blue)
                Label("Normal", systemImage: "line.diagonal")
                    .font(.caption2).foregroundStyle(.green)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Blood pressure trend chart showing systolic and diastolic values over time")
    }
}

// MARK: - Pulse Chart

struct PulseChart: View {
    let records: [HealthRecord]

    private var recordsWithPulse: [HealthRecord] {
        records.filter { $0.pulseOptional != nil }
    }

    var body: some View {
        if !recordsWithPulse.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pulse Trend")
                    .font(.headline)

                Chart {
                    ForEach(recordsWithPulse) { record in
                        AreaMark(
                            x: .value("Date", record.timestamp),
                            y: .value("BPM", record.pulse)
                        )
                        .foregroundStyle(.pink.opacity(0.15))
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Date", record.timestamp),
                            y: .value("BPM", record.pulse)
                        )
                        .foregroundStyle(.pink)
                        .symbol(.circle)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .frame(height: 160)
                .chartYAxis { AxisMarks(position: .leading) }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
    }
}

// MARK: - Clinical Summary Card

struct BPSummaryCard: View {
    let records: [HealthRecord]

    private var avgSystolic: Int {
        guard !records.isEmpty else { return 0 }
        return records.map(\.systolic).reduce(0, +) / records.count
    }
    private var avgDiastolic: Int {
        guard !records.isEmpty else { return 0 }
        return records.map(\.diastolic).reduce(0, +) / records.count
    }
    private var avgPulse: Int? {
        let withPulse = records.compactMap(\.pulseOptional)
        guard !withPulse.isEmpty else { return nil }
        return withPulse.reduce(0, +) / withPulse.count
    }
    private var avgCategory: BPCategory {
        BPCategory.classify(systolic: avgSystolic, diastolic: avgDiastolic)
    }
    private var percentNormal: Int {
        guard !records.isEmpty else { return 0 }
        let normal = records.filter { $0.bpCategory == .normal }.count
        return Int(Double(normal) / Double(records.count) * 100)
    }

    private func categoryColor(_ cat: BPCategory) -> Color {
        switch cat {
        case .normal: return .green
        case .elevated: return .yellow
        case .highStage1: return .orange
        case .highStage2: return .red
        case .crisis: return .purple
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Summary")
                    .font(.headline)
                Spacer()
                Text("\(records.count) readings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Average BP").font(.caption).foregroundStyle(.secondary)
                    Text("\(avgSystolic)/\(avgDiastolic)")
                        .font(.title2.bold().monospacedDigit())
                    Text(avgCategory.rawValue)
                        .font(.caption2.bold())
                        .foregroundStyle(categoryColor(avgCategory))
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 50)

                VStack(spacing: 4) {
                    Text("Avg Pulse").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption)
                        Text(avgPulse.map { "\($0)" } ?? "N/A").font(.title2.bold().monospacedDigit())
                    }
                    Text("bpm").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 50)

                VStack(spacing: 4) {
                    Text("In Range").font(.caption).foregroundStyle(.secondary)
                    Text("\(percentNormal)%")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(percentNormal >= 50 ? .green : .orange)
                    Text("normal").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            Divider()

            let minS = records.map(\.systolic).min() ?? 0
            let maxS = records.map(\.systolic).max() ?? 0
            let minD = records.map(\.diastolic).min() ?? 0
            let maxD = records.map(\.diastolic).max() ?? 0

            HStack {
                Text("Systolic range").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(minS) – \(maxS) mmHg").font(.caption.monospacedDigit())
            }
            HStack {
                Text("Diastolic range").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(minD) – \(maxD) mmHg").font(.caption.monospacedDigit())
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - Weekly Averages Chart

struct WeeklyAveragesChart: View {
    let records: [HealthRecord]

    private struct WeekData: Identifiable {
        let id = UUID()
        let weekStart: Date
        let avgSystolic: Double
        let avgDiastolic: Double
        let count: Int
        var label: String { weekStart.formatted(.dateTime.month(.abbreviated).day()) }
    }

    private var weeklyData: [WeekData] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: records) { record in
            calendar.dateInterval(of: .weekOfYear, for: record.timestamp)?.start ?? record.timestamp
        }
        return grouped.map { weekStart, weekRecords in
            WeekData(
                weekStart: weekStart,
                avgSystolic: Double(weekRecords.map(\.systolic).reduce(0, +)) / Double(weekRecords.count),
                avgDiastolic: Double(weekRecords.map(\.diastolic).reduce(0, +)) / Double(weekRecords.count),
                count: weekRecords.count
            )
        }.sorted { $0.weekStart < $1.weekStart }
    }

    var body: some View {
        if weeklyData.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                Text("Weekly Averages").font(.headline)

                Chart {
                    ForEach(weeklyData) { week in
                        BarMark(
                            x: .value("Week", week.label),
                            yStart: .value("Diastolic", week.avgDiastolic),
                            yEnd: .value("Systolic", week.avgSystolic)
                        )
                        .foregroundStyle(
                            .linearGradient(colors: [.blue.opacity(0.7), .red.opacity(0.7)], startPoint: .bottom, endPoint: .top)
                        )
                    }
                    RuleMark(y: .value("Target Sys", 120))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .foregroundStyle(.green.opacity(0.5))
                    RuleMark(y: .value("Target Dia", 80))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .foregroundStyle(.green.opacity(0.3))
                }
                .frame(height: 220)
                .chartYAxis { AxisMarks(position: .leading) }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
    }
}

// MARK: - Morning vs Evening

struct MorningVsEveningChart: View {
    let records: [HealthRecord]

    private struct PeriodStats: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let avgSystolic: Double
        let avgDiastolic: Double
        let avgPulse: Double?
        let count: Int
    }

    private var periodData: [PeriodStats] {
        let calendar = Calendar.current
        let morning = records.filter { let h = calendar.component(.hour, from: $0.timestamp); return h >= 5 && h < 12 }
        let afternoon = records.filter { let h = calendar.component(.hour, from: $0.timestamp); return h >= 12 && h < 17 }
        let evening = records.filter { let h = calendar.component(.hour, from: $0.timestamp); return h >= 17 || h < 5 }

        var result: [PeriodStats] = []
        for (name, icon, group) in [
            ("Morning\n5am–12pm", "sunrise", morning),
            ("Afternoon\n12pm–5pm", "sun.max", afternoon),
            ("Evening\n5pm–5am", "moon.stars", evening)
        ] {
            if !group.isEmpty {
                result.append(PeriodStats(
                    name: name, icon: icon,
                    avgSystolic: Double(group.map(\.systolic).reduce(0, +)) / Double(group.count),
                    avgDiastolic: Double(group.map(\.diastolic).reduce(0, +)) / Double(group.count),
                    avgPulse: {
                        let pulses = group.compactMap(\.pulseOptional)
                        return pulses.isEmpty ? nil : Double(pulses.reduce(0, +)) / Double(pulses.count)
                    }(),
                    count: group.count
                ))
            }
        }
        return result
    }

    var body: some View {
        if periodData.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                Text("Time of Day Comparison").font(.headline)

                HStack(spacing: 12) {
                    ForEach(periodData) { period in
                        VStack(spacing: 8) {
                            Image(systemName: period.icon).font(.title3).foregroundStyle(.secondary)
                            Text("\(Int(period.avgSystolic))/\(Int(period.avgDiastolic))")
                                .font(.headline.monospacedDigit())
                            HStack(spacing: 2) {
                                Image(systemName: "heart.fill").font(.system(size: 8)).foregroundStyle(.pink)
                                Text(period.avgPulse.map { "\(Int($0))" } ?? "–").font(.caption.monospacedDigit())
                            }
                            Text(period.name).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Text("\(period.count) readings").font(.system(size: 9)).foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
    }
}

// MARK: - MAP Trend

struct MAPTrendChart: View {
    let records: [HealthRecord]

    private func mapValue(_ r: HealthRecord) -> Double {
        Double(r.diastolic) + Double(r.systolic - r.diastolic) / 3.0
    }
    private func pulsePressure(_ r: HealthRecord) -> Int {
        r.systolic - r.diastolic
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mean Arterial Pressure").font(.headline)
            Text("MAP = diastolic + \u{2153}(systolic \u{2212} diastolic). Normal: 70\u{2013}100 mmHg")
                .font(.caption).foregroundStyle(.secondary)

            Chart {
                ForEach(records) { record in
                    LineMark(
                        x: .value("Date", record.timestamp),
                        y: .value("MAP", mapValue(record))
                    )
                    .foregroundStyle(.purple)
                    .symbol(.circle)
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", record.timestamp),
                        y: .value("PP", pulsePressure(record)),
                        series: .value("Type", "Pulse Pressure")
                    )
                    .foregroundStyle(.orange)
                    .symbol(.diamond)
                    .interpolationMethod(.catmullRom)
                }

                RuleMark(y: .value("MAP High", 100))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .foregroundStyle(.green.opacity(0.4))
                RuleMark(y: .value("MAP Low", 70))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .foregroundStyle(.green.opacity(0.4))
            }
            .frame(height: 200)
            .chartYAxis { AxisMarks(position: .leading) }

            HStack(spacing: 16) {
                Label("MAP", systemImage: "circle.fill").font(.caption2).foregroundStyle(.purple)
                Label("Pulse Pressure", systemImage: "diamond.fill").font(.caption2).foregroundStyle(.orange)
                Label("Normal range", systemImage: "line.diagonal").font(.caption2).foregroundStyle(.green)
            }

            if !records.isEmpty {
                let avgMAP = records.map { mapValue($0) }.reduce(0, +) / Double(records.count)
                let avgPP = records.map { pulsePressure($0) }.reduce(0, +) / records.count
                HStack {
                    Text("Avg MAP: \(Int(avgMAP)) mmHg").font(.caption.monospacedDigit()).foregroundStyle(.purple)
                    Spacer()
                    Text("Avg Pulse Pressure: \(avgPP) mmHg").font(.caption.monospacedDigit()).foregroundStyle(.orange)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}
