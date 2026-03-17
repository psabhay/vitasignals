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

    @State private var startDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
    @State private var endDate: Date = .now
    @State private var selectedMetrics: Set<String> = Set(MetricRegistry.all.map(\.type))
    @State private var renderedPDF: URL?
    @State private var isGenerating = false
    @State private var generationStatus = ""
    @State private var showPreview = false

    private var filteredRecords: [HealthRecord] {
        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate))!
        return dataStore.allRecords.filter { $0.timestamp >= start && $0.timestamp < end }
    }

    private var availableMetricTypes: Set<String> {
        dataStore.availableMetricTypes
    }

    private var selectedAndAvailable: Set<String> {
        selectedMetrics.intersection(availableMetricTypes)
    }

    private var filteredRecordCount: Int {
        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate))!
        return dataStore.allRecords.lazy.filter { $0.timestamp >= start && $0.timestamp < end }.count
    }

    var body: some View {
        dateRangeSection
        previewSection
        metricSelectionSection
        generateSection
    }

    // MARK: - Sections

    private var dateRangeSection: some View {
        Section("Date Range") {
            DatePicker("From", selection: $startDate, displayedComponents: .date)
                .onChange(of: startDate) { _, _ in renderedPDF = nil }
            DatePicker("To", selection: $endDate, displayedComponents: .date)
                .onChange(of: endDate) { _, _ in renderedPDF = nil }
        }
    }

    private var previewSection: some View {
        Section {
            LabeledContent("Records in range") {
                Text("\(filteredRecordCount)")
                    .bold()
                    .foregroundStyle(filteredRecordCount == 0 ? .red : .primary)
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
                if selectedMetrics.count == availableMetricTypes.count {
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
                .disabled(isGenerating || filteredRecordCount == 0 || selectedAndAvailable.isEmpty)
            }
        }
    }

    // MARK: - PDF Generation

    private func generatePDF() {
        isGenerating = true
        generationStatus = "Generating report..."

        let records = filteredRecords.filter { selectedMetrics.contains($0.metricType) }
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

        Task.detached {
            let url = PDFGenerator.generate(
                records: snapshots,
                selectedMetrics: metrics,
                periodLabel: periodLabel,
                profile: profileData
            )
            await MainActor.run {
                renderedPDF = url
                isGenerating = false
                generationStatus = ""
            }
        }
    }
}
