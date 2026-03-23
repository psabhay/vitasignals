import SwiftUI
import SwiftData
import PDFKit

// MARK: - PDF Preview View

struct PDFPreviewView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFKitView(url: url)
                .navigationTitle("Report Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        ShareLink(item: url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
        }
    }
}

private struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}

// MARK: - Report Builder

struct ReportBuilderView: View {
    @EnvironmentObject var dataStore: HealthDataStore
    @Query private var profiles: [UserProfile]
    @Binding var exportRequest: ChartExportRequest?

    @State private var startDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var endDate: Date = .now
    @State private var selectedMetrics: Set<String> = MetricRegistry.allKnownTypes
    @State private var selectedTemplate: ReportTemplate = .comprehensive
    @State private var selectedStyle: ReportStyle = .classic
    @State private var renderedPDF: URL?
    @State private var isGenerating = false
    @State private var generationStatus = ""
    @State private var showPreview = false
    @State private var cachedFilteredCount: Int = 0
    @State private var hasInitialized = false

    private var availableMetricTypes: Set<String> {
        dataStore.availableMetricTypes
    }

    private var selectedAndAvailable: Set<String> {
        selectedMetrics.intersection(availableMetricTypes)
    }

    var body: some View {
        List {
            dateRangeSection
            templateSection
            styleSection
            previewSection
            metricSelectionSection
        }
        .safeAreaInset(edge: .bottom) {
            generateOverlay
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
        }
        .fullScreenCover(isPresented: $showPreview) {
            if let url = renderedPDF {
                PDFPreviewView(url: url)
            } else {
                Color.clear.onAppear { showPreview = false }
            }
        }
        .onAppear {
            if !hasInitialized {
                selectedMetrics.formUnion(dataStore.availableMetricTypes)
                hasInitialized = true
            }
            applyExportRequestIfNeeded()
            updateFilteredCount()
        }
        .onChange(of: startDate) { _, _ in renderedPDF = nil; updateFilteredCount() }
        .onChange(of: endDate) { _, _ in renderedPDF = nil; updateFilteredCount() }
        .onChange(of: exportRequest) { _, _ in applyExportRequestIfNeeded() }
        .onChange(of: selectedTemplate) { _, _ in renderedPDF = nil }
        .navigationTitle("Reports")
        .withProfileButton()
        .alert("Report Generation Failed", isPresented: $showGenerationError) {
            Button("OK") {}
        } message: {
            Text("The report could not be generated. Please try again or select a different date range.")
        }
    }

    // MARK: - Sticky Bottom Overlay

    @ViewBuilder
    private var generateOverlay: some View {
        if let pdfURL = renderedPDF {
            HStack(spacing: 12) {
                Button {
                    showPreview = true
                } label: {
                    Label("Preview", systemImage: "doc.text.magnifyingglass")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                ShareLink(item: pdfURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    renderedPDF = nil
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        } else {
            Button {
                generatePDF()
            } label: {
                HStack {
                    Spacer()
                    if isGenerating {
                        VStack(spacing: 6) {
                            ProgressView()
                            if !generationStatus.isEmpty {
                                Text(generationStatus)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Label("Generate PDF Report", systemImage: "doc.badge.plus")
                            .font(.headline)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating || cachedFilteredCount == 0 || selectedAndAvailable.isEmpty)
        }
    }

    // MARK: - Sections

    private var dateRangeSection: some View {
        Section("Date Range") {
            DatePicker("From", selection: $startDate, displayedComponents: .date)
            DatePicker("To", selection: $endDate, displayedComponents: .date)
        }
    }

    private var templateSection: some View {
        Section {
            ForEach(ReportTemplate.allTemplates) { template in
                Button {
                    selectedTemplate = template
                    renderedPDF = nil
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selectedTemplate.id == template.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedTemplate.id == template.id ? Color.accentColor : .secondary)
                            .font(.title3)
                        Image(systemName: template.icon)
                            .foregroundStyle(selectedTemplate.id == template.id ? Color.accentColor : .secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(template.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        } header: {
            Text("Report Template")
        }
    }

    private var styleSection: some View {
        Section {
            Picker("Visual Style", selection: $selectedStyle) {
                ForEach(ReportStyle.allCases) { style in
                    Text(style.name).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedStyle) { _, _ in renderedPDF = nil }
        } header: {
            Text("Report Style")
        }
    }

    private var previewSection: some View {
        Section {
            LabeledContent("Records in range") {
                Text("\(cachedFilteredCount)")
                    .bold()
                    .foregroundStyle(cachedFilteredCount == 0 ? .red : .primary)
            }
            LabeledContent("Metric types") {
                Text("\(selectedAndAvailable.count)")
            }
            if let p = profiles.first, !p.name.isEmpty {
                LabeledContent("Patient") {
                    Text(p.name)
                }
            }
        } header: {
            Text("Report Preview")
        }
    }

    private var metricSelectionSection: some View {
        let categories = MetricCategory.allCases.compactMap { category -> (MetricCategory, [MetricDefinition])? in
            let defs = MetricRegistry.definitions(for: category)
                .filter { availableMetricTypes.contains($0.type) }
            guard !defs.isEmpty else { return nil }
            return (category, defs)
        }

        return ForEach(categories, id: \.0) { category, defs in
            Section {
                ForEach(defs, id: \.type) { def in
                    Toggle(isOn: Binding(
                        get: { selectedMetrics.contains(def.type) },
                        set: { newValue in
                            if newValue {
                                selectedMetrics.insert(def.type)
                            } else {
                                selectedMetrics.remove(def.type)
                            }
                            renderedPDF = nil
                        }
                    )) {
                        Label(def.name, systemImage: def.icon)
                            .foregroundStyle(def.color)
                    }
                }
            } header: {
                HStack {
                    Label(category.rawValue, systemImage: category.icon)
                        .foregroundStyle(category.color)
                        .font(.caption.bold())
                    Spacer()
                    if category == categories.first?.0 {
                        if availableMetricTypes.isSubset(of: selectedMetrics) {
                            Button("Deselect All") {
                                selectedMetrics.removeAll()
                                renderedPDF = nil
                            }
                            .font(.caption)
                        } else {
                            Button("Select All") {
                                selectedMetrics = availableMetricTypes
                                renderedPDF = nil
                            }
                            .font(.caption)
                        }
                    }
                }
            } footer: {
                if category == categories.last?.0 {
                    Text("Only metrics with data in the selected date range are shown.")
                }
            }
        }
    }

    // MARK: - PDF Generation

    @State private var showGenerationError = false

    private func generatePDF() {
        isGenerating = true
        generationStatus = "Preparing data..."

        let start = startDate
        let end = endDate
        let metrics = selectedAndAvailable
        let style = selectedStyle
        let template = selectedTemplate
        let profileData: PDFGenerator.ProfileData? = {
            guard let p = profiles.first, !p.name.isEmpty else { return nil }
            return PDFGenerator.ProfileData(from: p)
        }()
        let periodLabel = "\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))"

        Task {
            // Fetch records off the immediate render path
            let records = dataStore.fetchRecords(from: start, to: end, metricTypes: selectedMetrics)

            // Snapshot records to detach from SwiftData
            let snapshots = records.map { r in
                HealthRecord(
                    metricType: r.metricType,
                    timestamp: r.timestamp,
                    primaryValue: r.primaryValue,
                    secondaryValue: r.secondaryValue,
                    tertiaryValue: r.tertiaryValue,
                    stringValue: r.stringValue,
                    durationSeconds: r.durationSeconds,
                    healthKitUUID: r.healthKitUUID,
                    source: r.source,
                    isManualEntry: r.isManualEntry,
                    activityContext: r.activityContext,
                    notes: r.notes
                )
            }

            generationStatus = "Generating report..."

            let url = await Task.detached(priority: .background) {
                PDFGenerator.generate(
                    records: snapshots,
                    selectedMetrics: metrics,
                    periodLabel: periodLabel,
                    profile: profileData,
                    style: style,
                    template: template
                )
            }.value

            renderedPDF = url
            isGenerating = false
            generationStatus = ""
            if url == nil {
                showGenerationError = true
            }
        }
    }

    private func updateFilteredCount() {
        cachedFilteredCount = dataStore.fetchRecords(from: startDate, to: endDate).count
    }

    private func applyExportRequestIfNeeded() {
        guard let request = exportRequest else { return }
        startDate = request.startDate
        endDate = request.endDate
        selectedMetrics = request.metrics
        renderedPDF = nil
        exportRequest = nil
        updateFilteredCount()
    }
}
