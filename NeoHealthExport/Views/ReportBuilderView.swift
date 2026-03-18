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

    @State private var startDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var endDate: Date = .now
    @State private var selectedMetrics: Set<String> = MetricRegistry.allKnownTypes
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
        dateRangeSection
        styleSection
        previewSection
        metricSelectionSection
        generateSection
            .onAppear {
                if !hasInitialized {
                    selectedMetrics.formUnion(dataStore.availableMetricTypes)
                    hasInitialized = true
                }
                updateFilteredCount()
            }
            .onChange(of: startDate) { _, _ in renderedPDF = nil; updateFilteredCount() }
            .onChange(of: endDate) { _, _ in renderedPDF = nil; updateFilteredCount() }
    }

    // MARK: - Sections

    private var dateRangeSection: some View {
        Section("Date Range") {
            DatePicker("From", selection: $startDate, displayedComponents: .date)
            DatePicker("To", selection: $endDate, displayedComponents: .date)
        }
    }

    private var styleSection: some View {
        Section {
            ForEach(ReportStyle.allCases) { style in
                Button {
                    selectedStyle = style
                    renderedPDF = nil
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selectedStyle.id == style.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedStyle.id == style.id ? Color.accentColor : .secondary)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(style.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(style.previewDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
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
        Section {
            ForEach(MetricCategory.allCases) { category in
                let defs = MetricRegistry.definitions(for: category)
                    .filter { availableMetricTypes.contains($0.type) }

                if !defs.isEmpty {
                    DisclosureGroup {
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
                    } label: {
                        Label {
                            HStack {
                                Text(category.rawValue)
                                Spacer()
                                let count = defs.filter { selectedMetrics.contains($0.type) }.count
                                Text("\(count)/\(defs.count)")
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
        } header: {
            HStack {
                Text("Metrics to Include")
                Spacer()
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
        } footer: {
            Text("Only metrics with data in the selected date range are shown. Metrics with no data will be skipped.")
        }
    }

    @ViewBuilder
    private var generateSection: some View {
        Section {
            if let pdfURL = renderedPDF {
                Button {
                    showPreview = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Preview Report", systemImage: "doc.text.magnifyingglass")
                            .font(.headline)
                        Spacer()
                    }
                }
                .fullScreenCover(isPresented: $showPreview) {
                    if let url = renderedPDF {
                        PDFPreviewView(url: url)
                    }
                }

                ShareLink(item: pdfURL) {
                    HStack {
                        Spacer()
                        Label("Share PDF Report", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                        Spacer()
                    }
                }
                Button {
                    renderedPDF = nil
                } label: {
                    HStack {
                        Spacer()
                        Label("Regenerate", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                        Spacer()
                    }
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
                }
                .disabled(isGenerating || cachedFilteredCount == 0 || selectedAndAvailable.isEmpty)
            }
        }
    }

    // MARK: - PDF Generation

    private func generatePDF() {
        isGenerating = true
        generationStatus = "Generating report..."

        let records = dataStore.fetchRecords(from: startDate, to: endDate, metricTypes: selectedMetrics)
        let periodLabel = "\(startDate.formatted(date: .abbreviated, time: .omitted)) – \(endDate.formatted(date: .abbreviated, time: .omitted))"
        let profileData: PDFGenerator.ProfileData? = {
            guard let p = profiles.first, !p.name.isEmpty else { return nil }
            return PDFGenerator.ProfileData(from: p)
        }()

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
        let metrics = selectedAndAvailable
        let style = selectedStyle

        Task.detached(priority: .background) {
            let url = PDFGenerator.generate(
                records: snapshots,
                selectedMetrics: metrics,
                periodLabel: periodLabel,
                profile: profileData,
                style: style
            )
            await MainActor.run {
                renderedPDF = url
                isGenerating = false
                generationStatus = ""
            }
        }
    }

    private func updateFilteredCount() {
        cachedFilteredCount = dataStore.fetchRecords(from: startDate, to: endDate).count
    }
}
