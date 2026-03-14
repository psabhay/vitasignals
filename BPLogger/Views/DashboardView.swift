import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BPReading.timestamp, order: .reverse) private var readings: [BPReading]
    @State private var showingAddReading = false
    @State private var showingImport = false

    private var todayReadings: [BPReading] {
        readings.filter { Calendar.current.isDateInToday($0.timestamp) }
    }

    private var last7DaysReadings: [BPReading] {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        return readings.filter { $0.timestamp >= sevenDaysAgo }
    }

    private var averageSystolic: Int? {
        guard !last7DaysReadings.isEmpty else { return nil }
        return last7DaysReadings.map(\.systolic).reduce(0, +) / last7DaysReadings.count
    }

    private var averageDiastolic: Int? {
        guard !last7DaysReadings.isEmpty else { return nil }
        return last7DaysReadings.map(\.diastolic).reduce(0, +) / last7DaysReadings.count
    }

    private var averagePulse: Int? {
        guard !last7DaysReadings.isEmpty else { return nil }
        return last7DaysReadings.map(\.pulse).reduce(0, +) / last7DaysReadings.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let latest = readings.first {
                        latestReadingCard(latest)
                    } else {
                        emptyStateView
                    }

                    if !last7DaysReadings.isEmpty {
                        weekAverageCard
                        miniChartCard
                    }

                    todaySection
                }
                .padding()
            }
            .navigationTitle("BP Logger")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingAddReading = true
                        } label: {
                            Label("Add Manually", systemImage: "plus")
                        }
                        Button {
                            showingImport = true
                        } label: {
                            Label("Import from Health", systemImage: "heart.circle")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingAddReading) {
                AddReadingView()
            }
            .sheet(isPresented: $showingImport) {
                HealthImportView()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No Readings Yet")
                .font(.title2.bold())
            Text("Tap + to log your first blood pressure reading")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func latestReadingCard(_ reading: BPReading) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Latest Reading")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(reading.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(reading.systolic)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Text("/")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.secondary)
                Text("\(reading.diastolic)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Text("mmHg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }

            HStack(spacing: 16) {
                Label("\(reading.pulse) bpm", systemImage: "heart.fill")
                    .font(.subheadline)
                    .foregroundStyle(.pink)

                Label(reading.activityContext.rawValue, systemImage: reading.activityContext.icon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            CategoryBadge(category: reading.category)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var weekAverageCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("7-Day Average")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(last7DaysReadings.count) readings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                if let sys = averageSystolic, let dia = averageDiastolic {
                    VStack {
                        Text("\(sys)/\(dia)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("mmHg")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let pulse = averagePulse {
                    VStack {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.pink)
                            Text("\(pulse)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                        }
                        Text("bpm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var miniChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 7 Days")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            Chart {
                ForEach(last7DaysReadings.reversed()) { reading in
                    LineMark(
                        x: .value("Time", reading.timestamp),
                        y: .value("Systolic", reading.systolic)
                    )
                    .foregroundStyle(.red)
                    .symbol(.circle)

                    LineMark(
                        x: .value("Time", reading.timestamp),
                        y: .value("Diastolic", reading.diastolic)
                    )
                    .foregroundStyle(.blue)
                    .symbol(.diamond)
                }

                RuleMark(y: .value("Normal Systolic", 120))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .foregroundStyle(.green.opacity(0.5))

                RuleMark(y: .value("Normal Diastolic", 80))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .foregroundStyle(.green.opacity(0.3))
            }
            .frame(height: 180)
            .chartYAxis {
                AxisMarks(position: .leading)
            }

            HStack(spacing: 16) {
                Label("Systolic", systemImage: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                Label("Diastolic", systemImage: "diamond.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Label("Normal", systemImage: "line.diagonal")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            if todayReadings.isEmpty {
                Text("No readings today")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(todayReadings) { reading in
                    ReadingRow(reading: reading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct CategoryBadge: View {
    let category: BPCategory

    var badgeColor: Color {
        switch category {
        case .normal: return .green
        case .elevated: return .yellow
        case .highStage1: return .orange
        case .highStage2: return .red
        case .crisis: return .purple
        }
    }

    var body: some View {
        Text(category.rawValue)
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(badgeColor.opacity(0.15), in: Capsule())
            .foregroundStyle(badgeColor)
    }
}

struct ReadingRow: View {
    let reading: BPReading

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(reading.formattedReading)
                        .font(.headline.monospacedDigit())
                    if reading.isFromHealthKit {
                        Image(systemName: "heart.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.pink)
                    }
                }
                HStack(spacing: 8) {
                    Label("\(reading.pulse)", systemImage: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.pink)
                    Label(reading.activityContext.rawValue, systemImage: reading.activityContext.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(reading.formattedTimeOnly)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CategoryBadge(category: reading.category)
            }
        }
        .padding(.vertical, 4)
    }
}
