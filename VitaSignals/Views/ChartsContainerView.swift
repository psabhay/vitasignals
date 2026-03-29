import SwiftUI
import SwiftData
import Charts

struct ChartsContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var dataStore: HealthDataStore
    @Query(sort: \SavedChartView.createdAt, order: .reverse) private var savedViews: [SavedChartView]
    @Query(sort: \CustomChart.createdAt) private var customCharts: [CustomChart]
    @State private var timeRange: ChartTimeRange = .month
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var customEndDate: Date = .now
    @State private var expandedMetric: String?
    @State private var selectedMetrics: Set<String> = []
    @State private var showFilterSheet = false
    @State private var hasInitializedMetrics = false
    @State private var showSaveViewAlert = false
    @State private var saveViewName = ""
    @State private var activeViewID: UUID?
    @State private var renamingView: SavedChartView?
    @State private var renameText = ""
    @State private var isLoadingView = false
    @AppStorage("hasSeenZoomTip") private var hasSeenZoomTip = false
    @State private var showHiddenList = false
    @State private var showCreateCustomChart = false
    @State private var editingCustomChart: CustomChart?

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

    private var effectiveDateRange: ClosedRange<Date> {
        if timeRange == .custom {
            return normalizedDateDomain(customStartDate...customEndDate, minimumSpan: 24 * 60 * 60)
        }
        let end = Date.now
        if let days = timeRange.days {
            let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
            return normalizedDateDomain(start...end, minimumSpan: 60)
        }
        // "All Time" — use cached earliest date
        let earliest = cachedEarliestDate ?? end
        return normalizedDateDomain(earliest...end, minimumSpan: 60)
    }

    private func filteredRecords(for metricType: String) -> [HealthRecord] {
        let result = dataStore.records(for: metricType)
        let range = effectiveDateRange
        return result.filter { $0.timestamp >= range.lowerBound && $0.timestamp <= range.upperBound }
    }

    /// All metric types that have ANY data (independent of date range).
    /// Ordered by registry (curated first, then catalog, grouped by category).
    private var allMetricsWithData: [String] {
        orderedMetricsWithData(from: dataStore.availableMetricTypes)
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

    private var effectiveZoom: CGFloat {
        Self.sanitizedZoom(zoomScale * activeZoom)
    }

    private var effectivePan: CGFloat {
        clampPan(panOffset + activePan)
    }
    private var isZoomed: Bool { effectiveZoom > 1.01 }

    private var xDomain: ClosedRange<Date> {
        let full = effectiveDateRange
        guard isZoomed else { return full }

        let zoom = Double(effectiveZoom)
        let total = full.upperBound.timeIntervalSince(full.lowerBound)
        guard zoom.isFinite, zoom > 0, total.isFinite, total > 0 else { return full }

        let visible = total / Double(zoom)
        let center = total * (0.5 + Double(effectivePan))
        guard visible.isFinite, center.isFinite else { return full }

        var start = full.lowerBound.addingTimeInterval(center - visible / 2)
        var end = start.addingTimeInterval(visible)

        if start < full.lowerBound {
            start = full.lowerBound
            end = start.addingTimeInterval(visible)
        }
        if end > full.upperBound {
            end = full.upperBound
            start = max(full.lowerBound, end.addingTimeInterval(-visible))
        }

        return normalizedDateDomain(start...end)
    }

    private var dateRangeLabel: String {
        if timeRange == .custom {
            let fmt = Date.FormatStyle().month(.abbreviated).day()
            let range = effectiveDateRange
            return "\(range.lowerBound.formatted(fmt)) – \(range.upperBound.formatted(fmt))"
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

    private var isDefaultView: Bool {
        timeRange == .month
            && selectedMetrics == Set(allMetricsWithData)
            && !isZoomed
            && activeViewID == nil
    }

    private func resetToDefault() {
        timeRange = .month
        customStartDate = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
        customEndDate = .now
        selectedMetrics = Set(allMetricsWithData)
        activeViewID = nil
        resetZoom()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    savedViewsPillRow

                    // Inline filter bar — always visible, tappable
                    filterBar

                    // Custom charts section — always visible at the top
                    createChartButton

                    if !customCharts.isEmpty {
                        ForEach(customCharts) { chart in
                            customChartCard(chart)
                        }
                    }

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
                        hiddenMetricsBanner

                        ForEach(cachedVisibleTypes, id: \.self) { type in
                            chartCard(for: type)
                        }
                    }
                }
                .padding(.bottom)
                .simultaneousGesture(pinchGesture)
            }
            .navigationTitle("Metrics")
            .navigationDestination(item: $expandedMetric) { metricType in
                let records = cachedRecords[metricType] ?? []
                expandedContent(for: metricType, records: records)
            }
            .alert("Save Current View", isPresented: $showSaveViewAlert) {
                TextField("View name", text: $saveViewName)
                Button("Save") { saveCurrentView() }
                Button("Cancel", role: .cancel) { saveViewName = "" }
            } message: {
                Text("Give this chart configuration a name so you can quickly load it later.")
            }
            .alert("Rename View", isPresented: Binding(
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
            .sheet(isPresented: $showFilterSheet) {
                ChartFilterSheet(
                    timeRange: $timeRange,
                    customStartDate: $customStartDate,
                    customEndDate: $customEndDate,
                    selectedMetrics: $selectedMetrics
                )
                .onDisappear { resetZoom() }
            }
            .sheet(isPresented: $showCreateCustomChart) {
                CreateCustomChartSheet()
            }
            .sheet(item: $editingCustomChart) { chart in
                CreateCustomChartSheet(editingChart: chart)
            }
            .onAppear {
                if !hasInitializedMetrics {
                    selectedMetrics = Set(allMetricsWithData)
                    hasInitializedMetrics = true
                }
                recomputeEarliestDate()
                recomputeVisible()
            }
            .onChange(of: timeRange) { _, _ in
                if !isLoadingView { activeViewID = nil }
                recomputeVisible()
            }
            .onChange(of: selectedMetrics) { _, _ in
                if !isLoadingView { activeViewID = nil }
                recomputeVisible()
            }
            .onChange(of: customStartDate) { _, _ in
                if !isLoadingView { activeViewID = nil }
                recomputeVisible()
            }
            .onChange(of: customEndDate) { _, _ in
                if !isLoadingView { activeViewID = nil }
                recomputeVisible()
            }
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

    // MARK: - Saved Views Pill Row

    private var savedViewsPillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" default pill
                Button {
                    withAnimation { resetToDefault() }
                } label: {
                    Text("All")
                        .font(.caption.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            activeViewID == nil && isDefaultView
                                ? Color.accentColor
                                : Color(.systemGray5),
                            in: Capsule()
                        )
                        .foregroundStyle(
                            activeViewID == nil && isDefaultView ? .white : .primary
                        )
                }
                .buttonStyle(.plain)

                // Saved view pills
                ForEach(savedViews) { view in
                    let isActive = activeViewID == view.id
                    Button {
                        withAnimation { loadSavedView(view) }
                    } label: {
                        Text(view.name)
                            .font(.caption.bold())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                isActive ? Color.accentColor : Color(.systemGray5),
                                in: Capsule()
                            )
                            .foregroundStyle(isActive ? .white : .primary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            renamingView = view
                            renameText = view.name
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }

                        Button {
                            updateSavedView(view)
                        } label: {
                            Label("Update with Current", systemImage: "arrow.triangle.2.circlepath")
                        }

                        Button(role: .destructive) {
                            deleteSavedView(view)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                // "+" pill to save current view
                Button {
                    saveViewName = ""
                    showSaveViewAlert = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color(.systemGray5), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
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

            if !isDefaultView {
                Button {
                    withAnimation { resetToDefault() }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.accentColor)
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset to default view")
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Hidden Metrics Banner

    @ViewBuilder
    private var hiddenMetricsBanner: some View {
        let allWithData = allMetricsWithData
        let hiddenTypes = allWithData.filter { !selectedMetrics.contains($0) }
        if !hiddenTypes.isEmpty {
            VStack(spacing: 0) {
                // Header row — tappable to expand/collapse
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showHiddenList.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "eye.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(hiddenTypes.count) hidden metric\(hiddenTypes.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: showHiddenList ? "chevron.up" : "chevron.down")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Expanded list of hidden metrics
                if showHiddenList {
                    Divider().padding(.horizontal, 12)

                    VStack(spacing: 0) {
                        ForEach(hiddenTypes, id: \.self) { type in
                            let def = MetricRegistry.definition(for: type)
                            Button {
                                withAnimation { _ = selectedMetrics.insert(type) }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: def?.icon ?? "chart.xyaxis.line")
                                        .font(.caption)
                                        .foregroundStyle(def?.color ?? .gray)
                                        .frame(width: 20)
                                    Text(def?.name ?? type)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "eye")
                                        .font(.caption)
                                        .foregroundStyle(Color.accentColor)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        // Show All button
                        if hiddenTypes.count > 1 {
                            Divider().padding(.horizontal, 12)
                            Button {
                                withAnimation { selectedMetrics.formUnion(allWithData) }
                            } label: {
                                Text("Show All")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.accentColor)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
        }
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
        guard value.isFinite, maxPan.isFinite else { return 0 }
        return max(-maxPan, min(maxPan, value))
    }

    private static func sanitizedZoom(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 1.0 }
        return max(1.0, min(value, 20.0))
    }

    private static func sanitizedPan(_ value: CGFloat, zoom: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        let safeZoom = sanitizedZoom(zoom)
        let maxPan = 0.5 - 0.5 / safeZoom
        guard maxPan.isFinite else { return 0 }
        return max(-maxPan, min(maxPan, value))
    }

    private func resetZoom() {
        zoomScale = 1.0
        steadyZoom = 1.0
        panOffset = 0
        steadyPan = 0
    }

    // MARK: - Saved Views

    private func saveCurrentView() {
        let name = saveViewName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let safeZoom = Self.sanitizedZoom(zoomScale)
        let safePan = Self.sanitizedPan(panOffset, zoom: safeZoom)
        let view = SavedChartView(
            name: name,
            timeRange: timeRange.rawValue,
            customStartDate: customStartDate,
            customEndDate: customEndDate,
            selectedMetrics: Array(selectedMetrics),
            zoomScale: Double(safeZoom),
            panOffset: Double(safePan)
        )
        modelContext.insert(view)
        try? modelContext.save()
        activeViewID = view.id
        saveViewName = ""
    }

    private func updateSavedView(_ view: SavedChartView) {
        let safeZoom = Self.sanitizedZoom(zoomScale)
        let safePan = Self.sanitizedPan(panOffset, zoom: safeZoom)
        view.timeRangeRaw = timeRange.rawValue
        view.customStartDate = customStartDate
        view.customEndDate = customEndDate
        view.selectedMetrics = Array(selectedMetrics)
        view.savedZoomScale = Double(safeZoom)
        view.savedPanOffset = Double(safePan)
        try? modelContext.save()
    }

    private func loadSavedView(_ view: SavedChartView) {
        isLoadingView = true
        if let range = ChartTimeRange(rawValue: view.timeRangeRaw) {
            timeRange = range
        }
        customStartDate = view.customStartDate
        customEndDate = view.customEndDate
        selectedMetrics = Set(view.selectedMetrics)
        expandedMetric = nil
        activeViewID = view.id

        // Restore zoom/pan state
        let restoredZoom = Self.sanitizedZoom(CGFloat(view.savedZoomScale))
        let restoredPan = Self.sanitizedPan(CGFloat(view.savedPanOffset), zoom: restoredZoom)
        zoomScale = restoredZoom
        steadyZoom = restoredZoom
        panOffset = restoredPan
        steadyPan = restoredPan
        DispatchQueue.main.async { isLoadingView = false }
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
        let records = cachedRecords[metricType] ?? []
        let def = MetricRegistry.definition(for: metricType)
        if def?.chartStyle == .bpDual {
            ComparisonBPChart(records: records, xDomain: xDomain) {
                expandedMetric = metricType
            } onHide: {
                withAnimation { _ = selectedMetrics.remove(metricType) }
            }
        } else if let def = MetricRegistry.definition(for: metricType) {
            ComparisonMetricChart(records: records, definition: def, xDomain: xDomain) {
                expandedMetric = metricType
            } onHide: {
                withAnimation { _ = selectedMetrics.remove(metricType) }
            }
        }
    }

    // MARK: - Custom Chart Card

    @ViewBuilder
    private func customChartCard(_ chart: CustomChart) -> some View {
        let leftRecords = cachedRecords[chart.leftMetricType] ?? filteredRecords(for: chart.leftMetricType)
        let rightRecords = cachedRecords[chart.rightMetricType] ?? filteredRecords(for: chart.rightMetricType)
        if let leftDef = MetricRegistry.definition(for: chart.leftMetricType),
           let rightDef = MetricRegistry.definition(for: chart.rightMetricType) {
            DualAxisChartView(
                chartName: chart.name,
                leftRecords: leftRecords,
                rightRecords: rightRecords,
                leftDefinition: leftDef,
                rightDefinition: rightDef,
                xDomain: xDomain,
                onDelete: {
                    deleteCustomChart(chart)
                }
            )
            .contextMenu {
                Button {
                    editingCustomChart = chart
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    deleteCustomChart(chart)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func deleteCustomChart(_ chart: CustomChart) {
        // Remove associated DashboardCard
        let chartID = chart.id
        let descriptor = FetchDescriptor<DashboardCard>()
        if let cards = try? modelContext.fetch(descriptor) {
            for card in cards where card.customChartID == chartID {
                modelContext.delete(card)
            }
        }
        modelContext.delete(chart)
        try? modelContext.save()
    }

    // MARK: - Create Chart Button

    private var createChartButton: some View {
        Button {
            showCreateCustomChart = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.rectangle.on.rectangle")
                    .font(.subheadline)
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create Custom Chart")
                        .font(.subheadline.bold())
                    Text("Compare two metrics side by side")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private func expandedContent(for metricType: String, records: [HealthRecord]) -> some View {
        let def = MetricRegistry.definition(for: metricType)
        ScrollView {
            VStack(spacing: 16) {
                if def?.chartStyle == .bpDual {
                    bpExpandedCharts(records: records)
                } else if let def = MetricRegistry.definition(for: metricType) {
                    genericExpandedContent(records: records, definition: def)
                }
            }
            .padding(.bottom)
        }
        .navigationTitle(def?.name ?? metricType)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - BP Expanded

    @ViewBuilder
    private func bpExpandedCharts(records: [HealthRecord]) -> some View {
        VStack(spacing: 16) {
            BPTrendChart(records: records, xDomain: xDomain)
            PulseChart(records: records, xDomain: xDomain)
            BPSummaryCard(records: records)
            WeeklyAveragesChart(records: records, xDomain: xDomain)
            MorningVsEveningChart(records: records)
            MAPTrendChart(records: records, xDomain: xDomain)
        }
        .padding(.bottom)
    }

    // MARK: - Generic Expanded

    @ViewBuilder
    private func genericExpandedContent(records: [HealthRecord], definition: MetricDefinition) -> some View {
        VStack(spacing: 16) {
            GenericMetricChart(records: records, definition: definition, xDomain: xDomain)

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
        orderedMetricsWithData(from: dataStore.availableMetricTypes)
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
    var xDomain: ClosedRange<Date>? = nil
    @State private var showInfo = false
    @State private var chartData: [HealthRecord] = []

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
                ForEach(chartData) { record in
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
                    }
                }

                ReferenceRangeMarks(definition)
            }
            .frame(height: ChartHeight.detail)
            .chartYAxis { AxisMarks(position: .leading) }
            .chartXAxis { chartDateXAxisContent() }
            .conditionalXScale(domain: xDomain)
            .clipped()

            if !records.isEmpty {
                let values = records.map(\.primaryValue)
                let avg = values.reduce(0, +) / Double(values.count)
                let minV = values.min() ?? 0
                let maxV = values.max() ?? 0
                HStack {
                    Text("Avg: \(definition.formatValue(avg)) \(definition.unit)")
                    Spacer()
                    Text("Range: \(definition.formatValue(minV)) – \(definition.formatValue(maxV))")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .chartCardStyle()
        .onAppear { chartData = downsample(records, maxPoints: ChartResolution.detail) }
        .onChange(of: records) { _, new in chartData = downsample(new, maxPoints: ChartResolution.detail) }
    }
}

// MARK: - BP Trend Line Chart

struct BPTrendChart: View {
    let records: [HealthRecord]
    var xDomain: ClosedRange<Date>? = nil
    @State private var chartData: [HealthRecord] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Blood Pressure Trend")
                .font(.headline)

            Chart {
                ForEach(chartData) { record in
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

                BPReferenceMarks()
            }
            .frame(height: ChartHeight.detail)
            .chartYAxis { AxisMarks(position: .leading) }
            .conditionalXScale(domain: xDomain)
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
        .chartCardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Blood pressure trend chart showing systolic and diastolic values over time")
        .onAppear { chartData = downsample(records, maxPoints: ChartResolution.detail) }
        .onChange(of: records) { _, new in chartData = downsample(new, maxPoints: ChartResolution.detail) }
    }
}

// MARK: - Pulse Chart

struct PulseChart: View {
    let records: [HealthRecord]
    var xDomain: ClosedRange<Date>? = nil
    @State private var chartData: [HealthRecord] = []

    private var recordsWithPulse: [HealthRecord] {
        records.filter { $0.pulseOptional != nil }
    }

    var body: some View {
        if !recordsWithPulse.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pulse Trend")
                    .font(.headline)

                Chart {
                    ForEach(chartData) { record in
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
                .frame(height: ChartHeight.compact)
                .chartYAxis { AxisMarks(position: .leading) }
                .conditionalXScale(domain: xDomain)
                .clipped()
            }
            .chartCardStyle()
            .onAppear { chartData = downsample(recordsWithPulse, maxPoints: ChartResolution.detail) }
            .onChange(of: records) { _, _ in chartData = downsample(recordsWithPulse, maxPoints: ChartResolution.detail) }
        }
    }
}

// MARK: - Clinical Summary Card

struct BPSummaryCard: View {
    let records: [HealthRecord]

    // Single-pass computation of all stats
    private struct Stats {
        var sumSys = 0, sumDia = 0, sumPulse = 0, pulseCount = 0
        var minSys = Int.max, maxSys = Int.min
        var minDia = Int.max, maxDia = Int.min
        var normalCount = 0
    }

    @State private var cachedStats: Stats = Stats()

    private static func computeStats(_ records: [HealthRecord]) -> Stats {
        var s = Stats()
        for r in records {
            s.sumSys += r.systolic; s.sumDia += r.diastolic
            if let p = r.pulseOptional { s.sumPulse += p; s.pulseCount += 1 }
            if r.systolic < s.minSys { s.minSys = r.systolic }
            if r.systolic > s.maxSys { s.maxSys = r.systolic }
            if r.diastolic < s.minDia { s.minDia = r.diastolic }
            if r.diastolic > s.maxDia { s.maxDia = r.diastolic }
            if r.bpCategory == .normal { s.normalCount += 1 }
        }
        return s
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
        let s = cachedStats
        let count = max(records.count, 1)
        let avgSys = s.sumSys / count
        let avgDia = s.sumDia / count
        let avgCat = BPCategory.classify(systolic: avgSys, diastolic: avgDia)
        let avgPulse: Int? = s.pulseCount > 0 ? s.sumPulse / s.pulseCount : nil
        let pctNormal = Int(Double(s.normalCount) / Double(count) * 100)

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
                    Text("\(avgSys)/\(avgDia)")
                        .font(.title2.bold().monospacedDigit())
                    Text(avgCat.rawValue)
                        .font(.caption2.bold())
                        .foregroundStyle(categoryColor(avgCat))
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
                    Text("\(pctNormal)%")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(pctNormal >= 50 ? .green : .orange)
                    Text("normal").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            Divider()

            HStack {
                Text("Systolic range").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(s.minSys) – \(s.maxSys) mmHg").font(.caption.monospacedDigit())
            }
            HStack {
                Text("Diastolic range").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(s.minDia) – \(s.maxDia) mmHg").font(.caption.monospacedDigit())
            }
        }
        .chartCardStyle()
        .onAppear { cachedStats = Self.computeStats(records) }
        .onChange(of: records) { _, new in cachedStats = Self.computeStats(new) }
    }
}

// MARK: - Weekly Averages Chart

struct WeeklyAveragesChart: View {
    let records: [HealthRecord]
    var xDomain: ClosedRange<Date>? = nil

    private struct WeekData: Identifiable {
        var id: Date { weekStart }
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
                    RuleMark(y: .value("Target Sys", BPReference.systolicNormal))
                        .lineStyle(ChartRefLine.stroke)
                        .foregroundStyle(ChartRefLine.normalColor)
                    RuleMark(y: .value("Target Dia", BPReference.diastolicNormal))
                        .lineStyle(ChartRefLine.stroke)
                        .foregroundStyle(ChartRefLine.normalColor)
                }
                .frame(height: ChartHeight.detail)
                .chartYAxis { AxisMarks(position: .leading) }
                .clipped()
            }
            .chartCardStyle()
        }
    }
}

// MARK: - Morning vs Evening

struct MorningVsEveningChart: View {
    let records: [HealthRecord]

    private struct PeriodStats: Identifiable {
        let id: String
        let name: String
        let icon: String
        let avgSystolic: Double
        let avgDiastolic: Double
        let avgPulse: Double?
        let count: Int
    }

    @State private var cachedPeriodData: [PeriodStats] = []

    private static func computePeriodData(_ records: [HealthRecord]) -> [PeriodStats] {
        let calendar = Calendar.current
        var sumSys = [0, 0, 0], sumDia = [0, 0, 0], sumPulse = [0, 0, 0]
        var pulseCount = [0, 0, 0], count = [0, 0, 0]

        for r in records {
            let h = calendar.component(.hour, from: r.timestamp)
            let idx: Int
            if h >= 5 && h < 12 { idx = 0 }
            else if h >= 12 && h < 17 { idx = 1 }
            else { idx = 2 }
            sumSys[idx] += r.systolic
            sumDia[idx] += r.diastolic
            if let p = r.pulseOptional { sumPulse[idx] += p; pulseCount[idx] += 1 }
            count[idx] += 1
        }

        let labels = [
            ("morning", "Morning\n5am–12pm", "sunrise"),
            ("afternoon", "Afternoon\n12pm–5pm", "sun.max"),
            ("evening", "Evening\n5pm–5am", "moon.stars")
        ]

        return labels.enumerated().compactMap { i, info in
            guard count[i] > 0 else { return nil }
            let c = Double(count[i])
            return PeriodStats(
                id: info.0, name: info.1, icon: info.2,
                avgSystolic: Double(sumSys[i]) / c,
                avgDiastolic: Double(sumDia[i]) / c,
                avgPulse: pulseCount[i] > 0 ? Double(sumPulse[i]) / Double(pulseCount[i]) : nil,
                count: count[i]
            )
        }
    }

    var body: some View {
        Group {
            if cachedPeriodData.count >= 2 {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Time of Day Comparison").font(.headline)

                    HStack(spacing: 12) {
                        ForEach(cachedPeriodData) { period in
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
                .chartCardStyle()
            }
        }
        .onAppear { cachedPeriodData = Self.computePeriodData(records) }
        .onChange(of: records) { _, new in cachedPeriodData = Self.computePeriodData(new) }
    }
}

// MARK: - MAP Trend

struct MAPTrendChart: View {
    let records: [HealthRecord]
    var xDomain: ClosedRange<Date>? = nil
    @State private var chartData: [HealthRecord] = []
    @State private var avgMAP: Double = 0
    @State private var avgPP: Int = 0

    private func mapValue(_ r: HealthRecord) -> Double {
        Double(r.diastolic) + Double(r.systolic - r.diastolic) / 3.0
    }
    private func pulsePressure(_ r: HealthRecord) -> Int {
        r.systolic - r.diastolic
    }

    private func recompute(_ records: [HealthRecord]) {
        chartData = downsample(records, maxPoints: ChartResolution.detail)
        guard !records.isEmpty else { avgMAP = 0; avgPP = 0; return }
        avgMAP = records.map { mapValue($0) }.reduce(0, +) / Double(records.count)
        avgPP = records.map { pulsePressure($0) }.reduce(0, +) / records.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mean Arterial Pressure").font(.headline)
            Text("MAP = diastolic + \u{2153}(systolic \u{2212} diastolic). Normal: 70\u{2013}100 mmHg")
                .font(.caption).foregroundStyle(.secondary)

            Chart {
                ForEach(chartData) { record in
                    LineMark(
                        x: .value("Date", record.timestamp),
                        y: .value("MAP", mapValue(record))
                    )
                    .foregroundStyle(.purple)
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Date", record.timestamp),
                        y: .value("PP", pulsePressure(record)),
                        series: .value("Type", "Pulse Pressure")
                    )
                    .foregroundStyle(.orange)
                    .interpolationMethod(.monotone)
                }

                RuleMark(y: .value("MAP High", BPReference.mapHigh))
                    .lineStyle(ChartRefLine.stroke)
                    .foregroundStyle(ChartRefLine.normalColor)
                RuleMark(y: .value("MAP Low", BPReference.mapLow))
                    .lineStyle(ChartRefLine.stroke)
                    .foregroundStyle(ChartRefLine.normalColor)
            }
            .frame(height: ChartHeight.dual)
            .chartYAxis { AxisMarks(position: .leading) }
            .conditionalXScale(domain: xDomain)
            .clipped()

            HStack(spacing: 16) {
                Label("MAP", systemImage: "circle.fill").font(.caption2).foregroundStyle(.purple)
                Label("Pulse Pressure", systemImage: "diamond.fill").font(.caption2).foregroundStyle(.orange)
                Label("Normal range", systemImage: "line.diagonal").font(.caption2).foregroundStyle(.green)
            }

            if !records.isEmpty {
                HStack {
                    Text("Avg MAP: \(Int(avgMAP)) mmHg").font(.caption.monospacedDigit()).foregroundStyle(.purple)
                    Spacer()
                    Text("Avg Pulse Pressure: \(avgPP) mmHg").font(.caption.monospacedDigit()).foregroundStyle(.orange)
                }
            }
        }
        .chartCardStyle()
        .onAppear { recompute(records) }
        .onChange(of: records) { _, new in recompute(new) }
    }
}
