import SwiftUI
import SwiftData

struct ReadingsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BPReading.timestamp, order: .reverse) private var readings: [BPReading]
    @State private var showingAddReading = false
    @State private var selectedReading: BPReading?
    @State private var searchText = ""
    @State private var filterContext: ActivityContext?

    private var groupedReadings: [(String, [BPReading])] {
        let filtered: [BPReading]
        if let filterContext {
            filtered = readings.filter { $0.activityContext == filterContext }
        } else {
            filtered = Array(readings)
        }

        let grouped = Dictionary(grouping: filtered) { reading in
            reading.formattedDateOnly
        }

        return grouped.sorted { lhs, rhs in
            guard let lDate = lhs.value.first?.timestamp,
                  let rDate = rhs.value.first?.timestamp else { return false }
            return lDate > rDate
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if readings.isEmpty {
                    ContentUnavailableView(
                        "No Readings",
                        systemImage: "list.bullet.clipboard",
                        description: Text("Your blood pressure readings will appear here")
                    )
                } else {
                    List {
                        if filterContext != nil {
                            Section {
                                Button("Clear Filter") {
                                    filterContext = nil
                                }
                            }
                        }

                        ForEach(groupedReadings, id: \.0) { date, dayReadings in
                            Section(date) {
                                ForEach(dayReadings) { reading in
                                    Button {
                                        selectedReading = reading
                                    } label: {
                                        ReadingRow(reading: reading)
                                    }
                                    .tint(.primary)
                                }
                                .onDelete { indexSet in
                                    deleteReadings(dayReadings: dayReadings, at: indexSet)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddReading = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("All Readings") { filterContext = nil }
                        Divider()
                        ForEach(ActivityContext.allCases) { context in
                            Button {
                                filterContext = context
                            } label: {
                                Label(context.rawValue, systemImage: context.icon)
                            }
                        }
                    } label: {
                        Image(systemName: filterContext != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showingAddReading) {
                AddReadingView()
            }
            .sheet(item: $selectedReading) { reading in
                ReadingDetailView(reading: reading)
            }
        }
    }

    private func deleteReadings(dayReadings: [BPReading], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(dayReadings[index])
        }
    }
}

struct ReadingDetailView: View {
    let reading: BPReading
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        Text(reading.formattedReading)
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                        Text("mmHg")
                            .foregroundStyle(.secondary)
                        CategoryBadge(category: reading.category)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .padding(.vertical)
                }

                Section("Details") {
                    LabeledContent("Systolic") {
                        Text("\(reading.systolic) mmHg")
                            .foregroundStyle(.red)
                    }
                    LabeledContent("Diastolic") {
                        Text("\(reading.diastolic) mmHg")
                            .foregroundStyle(.blue)
                    }
                    LabeledContent("Pulse") {
                        Text("\(reading.pulse) bpm")
                            .foregroundStyle(.pink)
                    }
                }

                Section("Context") {
                    LabeledContent("Date") {
                        Text(reading.formattedDate)
                    }
                    LabeledContent("Activity") {
                        Label(reading.activityContext.rawValue, systemImage: reading.activityContext.icon)
                    }
                }

                if !reading.notes.isEmpty {
                    Section("Notes") {
                        Text(reading.notes)
                    }
                }
            }
            .navigationTitle("Reading Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
