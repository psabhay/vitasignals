import SwiftUI
import SwiftData
import Charts

struct ExportView: View {
    let readings: [BPReading]
    let timeRange: ChartTimeRange
    @Environment(\.dismiss) private var dismiss
    @State private var renderedPDF: URL?
    @State private var isGenerating = false
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.accentColor)

                Text("Export BP Report")
                    .font(.title2.bold())

                Text("Generate a PDF report with your blood pressure readings and charts for the selected period (\(timeRange.rawValue)).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 8) {
                    HStack {
                        Text("Readings:")
                        Spacer()
                        Text("\(readings.count)")
                            .bold()
                    }
                    if let first = readings.last, let last = readings.first {
                        HStack {
                            Text("Period:")
                            Spacer()
                            Text("\(first.formattedDateOnly) – \(last.formattedDateOnly)")
                                .bold()
                        }
                    }
                }
                .font(.subheadline)
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                Spacer()

                if let pdfURL = renderedPDF {
                    ShareLink(item: pdfURL) {
                        Label("Share PDF Report", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal)
                } else {
                    Button {
                        generatePDF()
                    } label: {
                        Group {
                            if isGenerating {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Label("Generate PDF Report", systemImage: "doc.badge.plus")
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                    }
                    .disabled(isGenerating)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func generatePDF() {
        isGenerating = true

        DispatchQueue.global(qos: .userInitiated).async {
            let url = PDFGenerator.generate(readings: readings, timeRange: timeRange)
            DispatchQueue.main.async {
                renderedPDF = url
                isGenerating = false
            }
        }
    }
}
