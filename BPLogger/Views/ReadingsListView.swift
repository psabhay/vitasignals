import SwiftUI
import SwiftData

struct ReadingsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BPReading.timestamp, order: .reverse) private var readings: [BPReading]
    @State private var showingAddReading = false
    @State private var showingImport = false
    @State private var selectedReading: BPReading?
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
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            modelContext.delete(reading)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            selectedReading = reading
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(.orange)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
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
            .sheet(isPresented: $showingImport) {
                HealthImportView()
            }
            .sheet(item: $selectedReading) { reading in
                ReadingDetailView(reading: reading)
            }
        }
    }
}

struct ReadingDetailView: View {
    let reading: BPReading
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showEditSheet = false
    @State private var showDeleteConfirmation = false

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
                        if reading.isFromHealthKit {
                            Label("Imported from Apple Health", systemImage: "heart.circle")
                                .font(.caption)
                                .foregroundStyle(.pink)
                                .padding(.top, 4)
                        }
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

                Section {
                    Button {
                        showEditSheet = true
                    } label: {
                        Label("Edit Reading", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Reading", systemImage: "trash")
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
            .sheet(isPresented: $showEditSheet) {
                EditReadingView(reading: reading)
            }
            .confirmationDialog("Delete this reading?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    modelContext.delete(reading)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(reading.formattedReading) mmHg on \(reading.formattedDate)")
            }
        }
    }
}
