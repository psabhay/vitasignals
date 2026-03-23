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
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var dataStore: HealthDataStore
    @Query(sort: \SavedChartView.createdAt, order: .reverse) private var savedViews: [SavedChartView]
    @State private var timeRange: ChartTimeRange = .month
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var customEndDate: Date = .now
    @State private var expandedMetric: String?
    @State private var selectedMetrics: Set<String> = []
    @State private var showFilterSheet = false
    @State private var hasInitializedMetrics = false
    @State private var showSaveViewAlert = false
    @State private var showSavedViewsSheet = false
    @State private var saveViewName = ""
    @State private var activeViewID: UUID?
    @AppStorage("hasSeenZoomTip") private var hasSeenZoomTip = false

    // Zoom & pan state
    @State private var zoomScale: CGFloat = 1.0
    @State private var steadyZoom: CGFloat = 1.0
    @State private var panOffset: CGFloat = 0.0 // -0.5...0.5, fraction of total range
    @State private var steadyPan: CGFloat = 0.0
    @GestureState private var activeZoom: CGFloat = 1.0
    @GestureState private var activePan: CGFloat = 0.0

    // Cached computed values
    @State private var cachedVisibleTypes: [String] = []
    @State private var cachedEarliestDate: Date?
    @State private var cachedHasData = false
    @State private var cachedRecords: [String: [HealthRecord]] = [:]

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
        // "All Time" — use cached earliest date
        let earliest = cachedEarliestDate ?? end
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

    /// Recompute cached visible metric types and their records.
    /// Called from .onAppear and .onChange — NOT on every render.
    private func recomputeVisible() {
        let metrics = allMetricsWithData
        cachedHasData = !metrics.isEmpty

        var visible: [String] = []
        var records: [String: [HealthRecord]] = [:]

        for type in metrics where selectedMetrics.contains(type) {
            let filtered = filteredRecords(for: type)
            if !filtered.isEmpty {
                visible.append(type)
                records[type] = Array(filtered.reversed())
            }
        }

        cachedVisibleTypes = visible
        cachedRecords = records
    }

    /// Recompute earliest date — only needed for "All Time" mode. Expensive.
    private func recomputeEarliestDate() {
        cachedEarliestDate = dataStore.allRecords.last?.timestamp ?? .now
    }

    private var effectiveZoom: CGFloat { zoomScale * activeZoom }
    private var effectivePan: CGFloat { panOffset + activePan }
    private var isZoomed: Bool { effectiveZoom > 1.01 }

    private var xDomain: ClosedRange<Date> {
        let full = effectiveDateRange
        guard isZoomed else { return full.start...full.end }

        let zoom = effectiveZoom
        let total = full.end.timeIntervalSince(full.start)
        let visible = total / Double(zoom)
        let center = total * (0.5 + Double(effectivePan))

        var start = full.start.addingTimeInterval(center - visible / 2)
        var end = start.addingTimeInterval(visible)

        if start < full.start { start = full.start; end = start.addingTimeInterval(visible) }
        if end > full.end { end = full.end; start = max(full.start, end.addingTimeInterval(-visible)) }

        return start...end
    }

    private var dateRangeLabel: String {
        if timeRange == .custom {
            let fmt = Date.FormatStyle().month(.abbreviated).day()
            return "\(customStartDate.formatted(fmt)) – \(customEndDate.formatted(fmt))"
        }
        return timeRange.rawValue
    }

    private var metricsFilterLabel: String {
        let selected = cachedVisibleTypes.count
        let total = dataStore.availableMetricTypes.count
        if selected == total {
            return "All \(total) metrics"
        }
        return "\(selected) of \(total) metrics"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Inline filter bar — always visible, tappable
                    filterBar

                    if !hasSeenZoomTip && !cachedVisibleTypes.isEmpty {
                        zoomTipBanner
                    }

                    if isZoomed {
                        zoomIndicator
                    }

                    if !cachedHasData {
                        VStack(spacing: 16) {
                            ContentUnavailableView(
                                "No Data",
                                systemImage: "chart.xyaxis.line",
                                description: Text("Add records or sync from Apple Health to see charts.")
                            )
                        }
                        .padding(.top, 60)
                    } else if cachedVisibleTypes.isEmpty {
                        VStack(spacing: 16) {
                            ContentUnavailableView(
                                "No Matching Data",
                                systemImage: "chart.xyaxis.line",
                                description: Text("No records match the current filters.")
                            )
                            Button("Adjust Filters") {
                                showFilterSheet = true
                            }
                            .font(.subheadline.bold())
                        }
                        .padding(.top, 40)
                    } else {
                        ForEach(cachedVisibleTypes, id: \.self) { type in
                            chartCard(for: type)
                        }
                    }
                }
                .padding(.bottom)
                .simultaneousGesture(pinchGesture)
            }
            .navigationTitle("Charts")
            .withProfileButton()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    savedViewsButton
                }
            }
            .alert("Save Current View", isPresented: $showSaveViewAlert) {
                TextField("View name", text: $saveViewName)
                Button("Save") { saveCurrentView() }
                Button("Cancel", role: .cancel) { saveViewName = "" }
            } message: {
                Text("Give this chart configuration a name so you can quickly load it later.")
            }
            .sheet(isPresented: $showFilterSheet) {
                ChartFilterSheet(
                    timeRange: $timeRange,
                    customStartDate: $customStartDate,
                    customEndDate: $customEndDate,
                    selectedMetrics: $selectedMetrics
                )
                .onDisappear { resetZoom() }
            }
            .sheet(isPresented: $showSavedViewsSheet) {
                SavedViewsSheet(
                    activeViewID: $activeViewID,
                    onLoad: { loadSavedView($0) },
                    onUpdate: { updateSavedView($0) },
                    onSaveNew: {
                        saveViewName = ""
                        showSaveViewAlert = true
                    },
                    canSave: !selectedMetrics.isEmpty
                )
            }
            .onAppear {
                if !hasInitializedMetrics {
                    selectedMetrics = Set(allMetricsWithData)
                    hasInitializedMetrics = true
                }
                recomputeEarliestDate()
                recomputeVisible()
            }
            .onChange(of: timeRange) { _, _ in recomputeVisible() }
            .onChange(of: selectedMetrics) { _, _ in recomputeVisible() }
            .onChange(of: customStartDate) { _, _ in recomputeVisible() }
            .onChange(of: customEndDate) { _, _ in recomputeVisible() }
            .onChange(of: dataStore.availableMetricTypes) { oldTypes, newTypes in
                let newlyAdded = newTypes.subtracting(oldTypes)
                if !newlyAdded.isEmpty {
                    selectedMetrics.formUnion(newlyAdded)
                }
                recomputeEarliestDate()
                recomputeVisible()
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
                        if let viewID = activeViewID,
                           let activeView = savedViews.first(where: { $0.id == viewID }) {
                            Text(activeView.name)
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                            Text("\(dateRangeLabel) · \(metricsFilterLabel)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(dateRangeLabel)
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                            Text(metricsFilterLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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

            if let onExport, !cachedVisibleTypes.isEmpty {
                Button {
                    let domain = xDomain
                    onExport(ChartExportRequest(
                        metrics: Set(cachedVisibleTypes),
                        startDate: domain.lowerBound,
                        endDate: domain.upperBound
                    ))
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.accentColor)
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Export to Reports")
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Zoom Tip Banner

    private var zoomTipBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.pinch")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            Text("Pinch to zoom into any date range. Drag to pan.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                withAnimation { hasSeenZoomTip = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }

    // MARK: - Zoom & Pan

    private var zoomIndicator: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.caption.bold())
                .foregroundStyle(Color.accentColor)

            let domain = xDomain
            let fmt = Date.FormatStyle().month(.abbreviated).day()
            Text("\(domain.lowerBound.formatted(fmt)) – \(domain.upperBound.formatted(fmt))")
                .font(.caption.bold())
                .foregroundStyle(.primary)

            Text("\(String(format: "%.1f", effectiveZoom))x")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.3)) { resetZoom() }
            } label: {
                Text("Reset")
                    .font(.caption.bold())
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .gesture(panGesture)
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .updating($activeZoom) { value, state, _ in
                state = max(1.0 / steadyZoom, min(value.magnification, 20.0 / steadyZoom))
            }
            .onEnded { value in
                zoomScale = max(1.0, min(steadyZoom * value.magnification, 20.0))
                steadyZoom = zoomScale
                if zoomScale < 1.05 { resetZoom() }
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .updating($activePan) { value, state, _ in
                guard effectiveZoom > 1.01 else { return }
                let h = abs(value.translation.width)
                let v = abs(value.translation.height)
                guard h > v * 1.3 else { return }
                let delta = -value.translation.width / 400.0 / effectiveZoom
                let candidate = steadyPan + delta
                let maxPan: CGFloat = 0.5 - 0.5 / effectiveZoom
                state = max(-maxPan, min(maxPan, candidate)) - panOffset
            }
            .onEnded { value in
                guard effectiveZoom > 1.01 else { return }
                let h = abs(value.translation.width)
                let v = abs(value.translation.height)
                guard h > v * 1.3 else { return }
                let delta = -value.translation.width / 400.0 / zoomScale
                panOffset = clampPan(steadyPan + delta)
                steadyPan = panOffset
            }
    }

    private func clampPan(_ value: CGFloat) -> CGFloat {
        let maxPan: CGFloat = 0.5 - 0.5 / effectiveZoom
        return max(-maxPan, min(maxPan, value))
    }

    private func resetZoom() {
        zoomScale = 1.0
        steadyZoom = 1.0
        panOffset = 0
        steadyPan = 0
    }

    // MARK: - Saved Views

    private var savedViewsButton: some View {
        Button {
            showSavedViewsSheet = true
        } label: {
            Image(systemName: activeViewID != nil ? "bookmark.fill" : "bookmark")
                .font(.body)
        }
        .accessibilityLabel("Saved Chart Views")
    }

    private func saveCurrentView() {
        let name = saveViewName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let view = SavedChartView(
            name: name,
            timeRange: timeRange.rawValue,
            customStartDate: customStartDate,
            customEndDate: customEndDate,
            selectedMetrics: Array(selectedMetrics)
        )
        modelContext.insert(view)
        try? modelContext.save()
        activeViewID = view.id
        saveViewName = ""
    }

    private func updateSavedView(_ view: SavedChartView) {
        view.timeRangeRaw = timeRange.rawValue
        view.customStartDate = customStartDate
        view.customEndDate = customEndDate
        view.selectedMetrics = Array(selectedMetrics)
        try? modelContext.save()
    }

    private func loadSavedView(_ view: SavedChartView) {
        if let range = ChartTimeRange(rawValue: view.timeRangeRaw) {
            timeRange = range
        }
        customStartDate = view.customStartDate
        customEndDate = view.customEndDate
        selectedMetrics = Set(view.selectedMetrics)
        expandedMetric = nil
        activeViewID = view.id
    }

    private func deleteSavedView(_ view: SavedChartView) {
        if activeViewID == view.id {
            activeViewID = nil
        }
        modelContext.delete(view)
        try? modelContext.save()
    }

    // MARK: - Chart Card

    @ViewBuilder
    private func chartCard(for metricType: String) -> some View {
        let isExpanded = expandedMetric == metricType
        let records = cachedRecords[metricType] ?? []

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

// MARK: - Saved Views Sheet

struct SavedViewsSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedChartView.createdAt, order: .reverse) private var savedViews: [SavedChartView]
    @Binding var activeViewID: UUID?
    var onLoad: (SavedChartView) -> Void
    var onUpdate: (SavedChartView) -> Void
    var onSaveNew: () -> Void
    var canSave: Bool

    @State private var renamingView: SavedChartView?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                // Save / Update actions
                Section {
                    if let viewID = activeViewID,
                       let activeView = savedViews.first(where: { $0.id == viewID }) {
                        Button {
                            onUpdate(activeView)
                            dismiss()
                        } label: {
                            Label("Update \"\(activeView.name)\"", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }

                    Button {
                        dismiss()
                        // Small delay so the sheet dismisses before the alert appears
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onSaveNew()
                        }
                    } label: {
                        Label("Save Current View", systemImage: "plus.circle")
                    }
                    .disabled(!canSave)
                }

                // Saved views list
                if savedViews.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "bookmark")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("No Saved Views")
                                .font(.subheadline.bold())
                            Text("Save your chart configuration to quickly reload it later.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(savedViews) { view in
                            savedViewRow(view)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                let view = savedViews[index]
                                if activeViewID == view.id { activeViewID = nil }
                                modelContext.delete(view)
                            }
                            try? modelContext.save()
                        }
                    } header: {
                        Text("Saved Views (\(savedViews.count))")
                    } footer: {
                        Text("Tap to load. Swipe left to delete. Long-press to rename.")
                    }
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename", isPresented: Binding(
                get: { renamingView != nil },
                set: { if !$0 { renamingView = nil } }
            )) {
                TextField("View name", text: $renameText)
                Button("Save") {
                    if let view = renamingView {
                        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            view.name = trimmed
                            try? modelContext.save()
                        }
                    }
                    renamingView = nil
                }
                Button("Cancel", role: .cancel) { renamingView = nil }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func savedViewRow(_ view: SavedChartView) -> some View {
        let isActive = activeViewID == view.id
        return Button {
            onLoad(view)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isActive ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .font(.subheadline)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(view.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(isActive ? Color.accentColor : .primary)

                    Text(viewDateLabel(view))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(viewMetricNames(view))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }

                Spacer()

                if isActive {
                    Text("Active")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
            }
            .padding(.vertical, 2)
        }
        .tint(.primary)
        .contextMenu {
            Button {
                renameText = view.name
                renamingView = view
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive) {
                if activeViewID == view.id { activeViewID = nil }
                modelContext.delete(view)
                try? modelContext.save()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func viewDateLabel(_ view: SavedChartView) -> String {
        if let range = ChartTimeRange(rawValue: view.timeRangeRaw) {
            if range == .custom {
                let fmt = Date.FormatStyle().month(.abbreviated).day()
                return "\(view.customStartDate.formatted(fmt)) – \(view.customEndDate.formatted(fmt))"
            }
            return range.rawValue
        }
        return view.timeRangeRaw
    }

    private func viewMetricNames(_ view: SavedChartView) -> String {
        let names = view.selectedMetrics.compactMap { MetricRegistry.definition(for: $0)?.name }
        if names.isEmpty { return "No metrics" }
        if names.count <= 3 { return names.joined(separator: ", ") }
        return "\(names.prefix(3).joined(separator: ", ")) + \(names.count - 3) more"
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
        ForEach(categoriesWithData, id: \.category) { group in
            Section {
                ForEach(group.definitions, id: \.type) { def in
                    metricToggle(for: def)
                }
            } header: {
                HStack {
                    Label(group.category.rawValue, systemImage: group.category.icon)
                        .foregroundStyle(group.category.color)
                        .font(.caption.bold())
                    Spacer()
                    if group.category == categoriesWithData.first?.category {
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
        }
    }

    private struct CategoryGroup {
        let category: MetricCategory
        let definitions: [MetricDefinition]
    }

    private var categoriesWithData: [CategoryGroup] {
        MetricCategory.allCases.compactMap { category in
            let defs = MetricRegistry.definitions(for: category)
                .filter { allMetricsWithData.contains($0.type) }
            guard !defs.isEmpty else { return nil }
            return CategoryGroup(category: category, definitions: defs)
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
    @State private var showInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(definition.name)
                    .font(.headline)
                if definition.description != nil {
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showInfo) {
                        Text(definition.description ?? "")
                            .font(.subheadline)
                            .padding()
                            .frame(idealWidth: 260)
                            .presentationCompactAdaptation(.popover)
                    }
                }
            }
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
                        .interpolationMethod(.monotone)

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
                        .annotation(position: .topLeading, alignment: .leading) {
                            Text("Normal min: \(definition.formatValue(refMin)) \(definition.unit)")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                }
                if let refMax = definition.referenceMax {
                    RuleMark(y: .value("Ref Max", refMax))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .foregroundStyle(.green.opacity(0.5))
                        .annotation(position: .bottomLeading, alignment: .leading) {
                            Text("Normal max: \(definition.formatValue(refMax)) \(definition.unit)")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                }
            }
            .frame(height: 220)
            .chartYAxis { AxisMarks(position: .leading) }
            .clipped()

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
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Date", record.timestamp),
                        y: .value("mmHg", record.diastolic),
                        series: .value("Type", "Diastolic")
                    )
                    .foregroundStyle(.blue)
                    .symbol(.diamond)
                    .interpolationMethod(.monotone)
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
            .clipped()
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
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("Date", record.timestamp),
                            y: .value("BPM", record.pulse)
                        )
                        .foregroundStyle(.pink)
                        .symbol(.circle)
                        .interpolationMethod(.monotone)
                    }
                }
                .frame(height: 160)
                .chartYAxis { AxisMarks(position: .leading) }
            .clipped()
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
            .clipped()
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
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Date", record.timestamp),
                        y: .value("PP", pulsePressure(record)),
                        series: .value("Type", "Pulse Pressure")
                    )
                    .foregroundStyle(.orange)
                    .symbol(.diamond)
                    .interpolationMethod(.monotone)
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
            .clipped()

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
