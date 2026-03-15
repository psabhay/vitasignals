import SwiftUI
import SwiftData

struct ReportOptions {
    var bpSummary = true
    var bpCharts = true
    var bpWeeklyAverages = true
    var bpTimeOfDay = true
    var bpDetailedTable = true

    var cardioFitness = true
    var lifestyleFactors = true
    var sleepRecovery = true
    var correlationAnalysis = true

    var includesAnyHealthData: Bool {
        cardioFitness || lifestyleFactors || sleepRecovery || correlationAnalysis
    }
}

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BPReading.timestamp, order: .reverse) private var allReadings: [BPReading]
    @Query private var profiles: [UserProfile]

    @StateObject private var hkManager = HealthKitManager()
    @State private var startDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
    @State private var endDate: Date = .now
    @State private var options = ReportOptions()
    @State private var renderedPDF: URL?
    @State private var isGenerating = false
    @State private var generationStatus = ""

    private var filteredReadings: [BPReading] {
        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate))!
        return allReadings.filter { $0.timestamp >= start && $0.timestamp < end }
    }

    private var allBPSelected: Bool {
        options.bpSummary && options.bpCharts && options.bpWeeklyAverages && options.bpTimeOfDay && options.bpDetailedTable
    }

    private var allHealthSelected: Bool {
        options.cardioFitness && options.lifestyleFactors && options.sleepRecovery && options.correlationAnalysis
    }

    var body: some View {
        NavigationStack {
            Form {
                dateRangeSection
                previewSection
                bpSectionsSection
                healthSectionsSection
                generateSection
            }
            .navigationTitle("Export Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
            LabeledContent("Readings in range") {
                Text("\(filteredReadings.count)")
                    .bold()
                    .foregroundStyle(filteredReadings.isEmpty ? .red : .primary)
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

    private var bpSectionsSection: some View {
        Section {
            sectionToggle("Summary & Statistics", isOn: $options.bpSummary, icon: "list.clipboard", color: .blue)
            sectionToggle("BP & Heart Rate Charts", isOn: $options.bpCharts, icon: "chart.xyaxis.line", color: .red)
            sectionToggle("Weekly Averages", isOn: $options.bpWeeklyAverages, icon: "calendar", color: .orange)
            sectionToggle("Time of Day Comparison", isOn: $options.bpTimeOfDay, icon: "clock", color: .purple)
            sectionToggle("Detailed Readings Table", isOn: $options.bpDetailedTable, icon: "tablecells", color: .gray)
        } header: {
            HStack {
                Text("Blood Pressure Sections")
                Spacer()
                Button(allBPSelected ? "Deselect All" : "Select All") {
                    let target = !allBPSelected
                    options.bpSummary = target
                    options.bpCharts = target
                    options.bpWeeklyAverages = target
                    options.bpTimeOfDay = target
                    options.bpDetailedTable = target
                    renderedPDF = nil
                }
                .font(.caption)
            }
        }
    }

    private var healthSectionsSection: some View {
        Section {
            sectionToggle("Cardio Fitness", subtitle: "Resting HR, HRV, VO2 Max", isOn: $options.cardioFitness, icon: "heart.circle", color: .red)
            sectionToggle("Lifestyle Factors", subtitle: "Steps, Exercise, Weight", isOn: $options.lifestyleFactors, icon: "figure.walk", color: .green)
            sectionToggle("Sleep & Recovery", subtitle: "Sleep, Respiratory Rate, SpO2", isOn: $options.sleepRecovery, icon: "bed.double", color: .indigo)
            sectionToggle("Correlation Analysis", subtitle: "Weekly metrics comparison", isOn: $options.correlationAnalysis, icon: "chart.dots.scatter", color: .orange)
        } header: {
            HStack {
                Text("Apple Health Sections")
                Spacer()
                Button(allHealthSelected ? "Deselect All" : "Select All") {
                    let target = !allHealthSelected
                    options.cardioFitness = target
                    options.lifestyleFactors = target
                    options.sleepRecovery = target
                    options.correlationAnalysis = target
                    renderedPDF = nil
                }
                .font(.caption)
            }
        } footer: {
            Text("Health sections require data from Apple Watch or Apple Health. Sections with no data will be skipped automatically.")
        }
    }

    @ViewBuilder
    private var generateSection: some View {
        Section {
            if let pdfURL = renderedPDF {
                ShareLink(item: pdfURL) {
                    HStack {
                        Spacer()
                        Label("Share PDF Report", systemImage: "square.and.arrow.up")
                            .font(.headline)
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
                .disabled(isGenerating || filteredReadings.isEmpty)
            }
        }
    }

    // MARK: - Toggle Row

    private func sectionToggle(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>, icon: String, color: Color) -> some View {
        Toggle(isOn: Binding(
            get: { isOn.wrappedValue },
            set: { newValue in
                isOn.wrappedValue = newValue
                renderedPDF = nil
            }
        )) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
        }
    }

    // MARK: - PDF Generation

    private func generatePDF() {
        isGenerating = true
        generationStatus = ""

        // Capture everything on main thread as plain values
        let readingSnapshots = filteredReadings.map { r in
            (sys: r.systolic, dia: r.diastolic, pulse: r.pulse,
             ts: r.timestamp, ctx: r.activityContext, notes: r.notes,
             hkID: r.healthKitID)
        }
        let periodLabel = "\(startDate.formatted(date: .abbreviated, time: .omitted)) – \(endDate.formatted(date: .abbreviated, time: .omitted))"
        let opts = options
        let profileData: PDFGenerator.ProfileData? = {
            guard let p = profiles.first, !p.name.isEmpty else { return nil }
            return PDFGenerator.ProfileData(from: p)
        }()

        // Reconstruct BPReading objects detached from SwiftData
        let bpReadings = readingSnapshots.map { r in
            BPReading(systolic: r.sys, diastolic: r.dia, pulse: r.pulse,
                      timestamp: r.ts, activityContext: r.ctx, notes: r.notes,
                      healthKitID: r.hkID)
        }

        let capturedStartDate = startDate
        let capturedEndDate = endDate

        Task {
            var healthContext: HealthContext?

            if opts.includesAnyHealthData {
                generationStatus = "Requesting health data access..."
                await hkManager.requestExpandedAuthorization()

                generationStatus = "Fetching health data..."
                let start = Calendar.current.startOfDay(for: capturedStartDate)
                let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: capturedEndDate))!
                healthContext = await hkManager.fetchHealthContext(from: start, to: end)
            }

            generationStatus = "Generating PDF..."
            let hc = healthContext
            let pd = profileData
            let rd = bpReadings

            DispatchQueue.global(qos: .userInitiated).async {
                let url = PDFGenerator.generate(
                    readings: rd,
                    periodLabel: periodLabel,
                    profile: pd,
                    healthContext: hc,
                    options: opts
                )
                DispatchQueue.main.async {
                    renderedPDF = url
                    isGenerating = false
                    generationStatus = ""
                }
            }
        }
    }
}
