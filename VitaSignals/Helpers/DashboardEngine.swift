import SwiftUI
import SwiftData

// MARK: - Output Data Types

enum TrendDirection {
    case up, down, flat

    var icon: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .flat: return "minus"
        }
    }
}

enum DayPeriod {
    case morning, afternoon, evening
}

struct HeroCardData {
    let metricType: String
    let definitionName: String
    let definitionIcon: String
    let definitionColor: Color
    let definitionUnit: String
    let formattedValue: String
    let sevenDayAvg: Double?
    let sevenDayAvgFormatted: String?
    let trend: TrendDirection
    let bpCategory: BPCategory?
    let timeSinceReading: Date
}

struct SmartSummaryData {
    let greeting: String
    let userName: String?
    let contextIcon: String
    let contextLine: String
    let period: DayPeriod
}

struct HighlightItem: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let color: Color
    let priority: Int // lower = higher priority
}

struct QuickLogMetric: Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: Color
    let isCustom: Bool
}

struct MovingAverageRow: Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: Color
    let currentAvg: String
    let previousAvg: String?
    let improving: Bool?
    let lowerIsBetter: Bool
}

struct WeeklyRecapData {
    let thisWeekCount: Int
    let lastWeekCount: Int
    let streak: Int
    let metricSummaries: [MetricWeeklySummary]
    let weekLabel: String
}

struct MetricWeeklySummary: Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: Color
    let thisWeekAvg: String
    let lastWeekAvg: String?
    let improving: Bool?
    let lowerIsBetter: Bool
}

struct NudgeItem: Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: Color
    let hoursSinceLastLog: Int
    let message: String
}

struct GoalProgressData: Identifiable {
    let id: UUID
    let metricType: String
    let name: String
    let icon: String
    let color: Color
    let targetDescription: String
    let fraction: Double
    let readingsThisWeek: Int
    let readingsInTarget: Int
    let trend: TrendDirection
}

// MARK: - Dashboard Engine

@MainActor
final class DashboardEngine: ObservableObject {
    // Published outputs — view body reads only these
    @Published var heroCard: HeroCardData?
    @Published var smartSummary = SmartSummaryData(greeting: "", userName: nil, contextIcon: "", contextLine: "", period: .morning)
    @Published var highlights: [HighlightItem] = []
    @Published var quickLogMetrics: [QuickLogMetric] = []
    @Published var movingAverages: [MovingAverageRow] = []
    @Published var weeklyRecap: WeeklyRecapData?
    @Published var nudgeItems: [NudgeItem] = []
    @Published var goalProgress: [GoalProgressData] = []
    @Published var dashboardCards: [ResolvedDashboardCard] = []

    // MARK: - Main Entry Point

    func recompute(
        dataStore: HealthDataStore,
        userName: String?,
        goals: [MetricGoal],
        customMetrics: [CustomMetric],
        cards: [DashboardCard],
        modelContext: ModelContext
    ) {
        let calendar = Calendar.current
        let now = Date.now
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let fourteenDaysAgo = calendar.date(byAdding: .day, value: -14, to: now) ?? now

        heroCard = computeHeroCard(dataStore: dataStore, sevenDaysAgo: sevenDaysAgo)
        smartSummary = computeSmartSummary(dataStore: dataStore, userName: userName, calendar: calendar, now: now)
        highlights = computeHighlights(dataStore: dataStore, calendar: calendar, now: now, sevenDaysAgo: sevenDaysAgo, fourteenDaysAgo: fourteenDaysAgo)
        quickLogMetrics = computeQuickLogMetrics(dataStore: dataStore, customMetrics: customMetrics)
        movingAverages = computeMovingAverages(dataStore: dataStore, sevenDaysAgo: sevenDaysAgo, fourteenDaysAgo: fourteenDaysAgo)
        weeklyRecap = computeWeeklyRecap(dataStore: dataStore, calendar: calendar, now: now)
        nudgeItems = computeNudges(dataStore: dataStore, customMetrics: customMetrics, now: now)
        goalProgress = computeGoalProgress(dataStore: dataStore, goals: goals, sevenDaysAgo: sevenDaysAgo, fourteenDaysAgo: fourteenDaysAgo)

        // Sync and resolve dashboard chart cards
        DashboardCardResolver.syncCards(existingCards: cards, availableMetrics: dataStore.availableMetricTypes, context: modelContext)
        dashboardCards = DashboardCardResolver.resolve(cards: cards, dataStore: dataStore)
    }

    // MARK: - Hero Card

    private func computeHeroCard(dataStore: HealthDataStore, sevenDaysAgo: Date) -> HeroCardData? {
        let primaryType = determinePrimaryMetric(dataStore: dataStore)
        guard let metricType = primaryType else { return nil }
        let records = dataStore.records(for: metricType)
        guard let latest = records.first else { return nil }
        let def = MetricRegistry.definition(for: metricType)

        // 7-day average
        let recent7d = records.filter { $0.timestamp >= sevenDaysAgo }
        let avg: Double?
        let avgFormatted: String?
        if recent7d.count >= 2 {
            if metricType == MetricType.bloodPressure {
                let avgSys = Double(recent7d.map(\.systolic).reduce(0, +)) / Double(recent7d.count)
                let avgDia = Double(recent7d.map(\.diastolic).reduce(0, +)) / Double(recent7d.count)
                avg = avgSys
                avgFormatted = "\(Int(avgSys))/\(Int(avgDia))"
            } else {
                let a = recent7d.map(\.primaryValue).reduce(0, +) / Double(recent7d.count)
                avg = a
                avgFormatted = def?.formatValue(a)
            }
        } else {
            avg = nil
            avgFormatted = nil
        }

        // Trend
        let trend: TrendDirection
        if let avg, metricType == MetricType.bloodPressure {
            let diff = Double(latest.systolic) - avg
            trend = abs(diff) < 3 ? .flat : (diff > 0 ? .up : .down)
        } else if let avg {
            let pct = avg > 0 ? (latest.primaryValue - avg) / avg : 0
            trend = abs(pct) < 0.05 ? .flat : (pct > 0 ? .up : .down)
        } else {
            trend = .flat
        }

        return HeroCardData(
            metricType: metricType,
            definitionName: def?.name ?? metricType,
            definitionIcon: def?.icon ?? "chart.xyaxis.line",
            definitionColor: def?.color ?? .gray,
            definitionUnit: def?.unit ?? "",
            formattedValue: latest.formattedPrimaryValue,
            sevenDayAvg: avg,
            sevenDayAvgFormatted: avgFormatted,
            trend: trend,
            bpCategory: metricType == MetricType.bloodPressure ? latest.bpCategory : nil,
            timeSinceReading: latest.timestamp
        )
    }

    private func determinePrimaryMetric(dataStore: HealthDataStore) -> String? {
        // BP if has data
        if !dataStore.records(for: MetricType.bloodPressure).isEmpty {
            return MetricType.bloodPressure
        }
        // Otherwise most records in last 30 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        var best: (String, Int)? = nil
        for (type, records) in dataStore.recordsByType {
            let count = records.filter { $0.timestamp >= cutoff }.count
            if count > 0, count > (best?.1 ?? 0) {
                best = (type, count)
            }
        }
        return best?.0
    }

    // MARK: - Smart Summary

    private func computeSmartSummary(dataStore: HealthDataStore, userName: String?, calendar: Calendar, now: Date) -> SmartSummaryData {
        let hour = calendar.component(.hour, from: now)
        let period: DayPeriod
        let greeting: String
        if hour < 12 { period = .morning; greeting = "Good morning" }
        else if hour < 17 { period = .afternoon; greeting = "Good afternoon" }
        else { period = .evening; greeting = "Good evening" }

        let contextIcon: String
        let contextLine: String

        let todayRecords = dataStore.allRecords.filter { calendar.isDateInToday($0.timestamp) }
        let todayCount = todayRecords.count

        switch period {
        case .morning:
            // Check for sleep data from last night
            let sleepRecords = dataStore.records(for: MetricType.sleepDuration)
            let lastSleep = sleepRecords.first(where: {
                let h = calendar.component(.hour, from: $0.timestamp)
                return calendar.isDateInToday($0.timestamp) || (calendar.isDateInYesterday($0.timestamp) && h >= 20)
            })
            if let sleep = lastSleep {
                let hours = sleep.durationSeconds.map { $0 / 3600 } ?? sleep.primaryValue
                contextIcon = "moon.stars.fill"
                contextLine = "You slept \(String(format: "%.1f", hours))h last night. Start your day with a reading."
            } else if todayCount > 0 {
                contextIcon = "checkmark.circle"
                contextLine = "\(todayCount) reading\(todayCount == 1 ? "" : "s") logged so far today."
            } else {
                contextIcon = "sunrise"
                contextLine = "Start your day with a health reading."
            }

        case .afternoon:
            if todayCount > 0 {
                let lastTime = todayRecords.first?.timestamp ?? now
                contextIcon = "checkmark.circle"
                contextLine = "\(todayCount) reading\(todayCount == 1 ? "" : "s") today. Last: \(lastTime.formatted(.relative(presentation: .named)))."
            } else {
                contextIcon = "sun.max"
                contextLine = "No readings logged yet today."
            }

        case .evening:
            if todayCount > 0 {
                // Compare today's primary metric avg to 7-day avg
                let primaryType = determinePrimaryMetric(dataStore: dataStore)
                let todayMetric = primaryType.flatMap { type in todayRecords.filter { $0.metricType == type } } ?? []
                if todayMetric.count >= 2, let type = primaryType {
                    let def = MetricRegistry.definition(for: type)
                    let todayAvg = todayMetric.map(\.primaryValue).reduce(0, +) / Double(todayMetric.count)
                    contextIcon = "moon.stars"
                    contextLine = "\(todayCount) readings today. Avg \(def?.name ?? ""): \(def?.formatValue(todayAvg) ?? "") \(def?.unit ?? "")."
                } else {
                    contextIcon = "moon.stars"
                    contextLine = "\(todayCount) reading\(todayCount == 1 ? "" : "s") logged today."
                }
            } else {
                contextIcon = "moon.stars"
                contextLine = "No readings today. There's still time to log one."
            }
        }

        return SmartSummaryData(
            greeting: greeting,
            userName: userName,
            contextIcon: contextIcon,
            contextLine: contextLine,
            period: period
        )
    }

    // MARK: - Highlights

    private func computeHighlights(
        dataStore: HealthDataStore,
        calendar: Calendar,
        now: Date,
        sevenDaysAgo: Date,
        fourteenDaysAgo: Date
    ) -> [HighlightItem] {
        var items: [HighlightItem] = []

        // Today's count
        let todayCount = dataStore.allRecords.prefix(while: { now.timeIntervalSince($0.timestamp) < 86400 * 2 })
            .filter { calendar.isDateInToday($0.timestamp) }.count
        if todayCount > 0 {
            items.append(HighlightItem(icon: "checkmark.circle.fill",
                text: "\(todayCount) reading\(todayCount == 1 ? "" : "s") recorded today", color: .green, priority: 50))
        }

        // Streak
        let streak = computeStreak(allRecords: dataStore.allRecords, calendar: calendar, now: now)
        if streak >= 3 {
            items.append(HighlightItem(icon: "flame.fill", text: "\(streak)-day logging streak", color: .orange, priority: 40))
        }

        // Trend alerts — for each metric with enough data
        for (type, records) in dataStore.recordsByType {
            let recent = records.filter { $0.timestamp >= sevenDaysAgo }
            let prev = records.filter { $0.timestamp >= fourteenDaysAgo && $0.timestamp < sevenDaysAgo }
            guard recent.count >= 3, prev.count >= 3 else { continue }
            let def = MetricRegistry.definition(for: type)

            let recentAvg: Double, prevAvg: Double
            if type == MetricType.bloodPressure {
                recentAvg = Double(recent.map(\.systolic).reduce(0, +)) / Double(recent.count)
                prevAvg = Double(prev.map(\.systolic).reduce(0, +)) / Double(prev.count)
            } else {
                recentAvg = recent.map(\.primaryValue).reduce(0, +) / Double(recent.count)
                prevAvg = prev.map(\.primaryValue).reduce(0, +) / Double(prev.count)
            }
            guard prevAvg != 0 else { continue }
            let pctChange = ((recentAvg - prevAvg) / abs(prevAvg)) * 100
            guard abs(pctChange) >= 8 else { continue }

            let direction = pctChange > 0 ? "up" : "down"
            let arrow = pctChange > 0 ? "arrow.up.right" : "arrow.down.right"
            let lowerIsBetter = type == MetricType.bloodPressure
            let isImproving = lowerIsBetter ? pctChange < 0 : pctChange > 0
            items.append(HighlightItem(
                icon: arrow,
                text: "\(def?.name ?? type) \(direction) \(Int(abs(pctChange)))% vs last week",
                color: isImproving ? .green : .orange,
                priority: 10
            ))
        }

        // Consecutive concerning BP readings
        let bpRecords = dataStore.records(for: MetricType.bloodPressure)
        if !bpRecords.isEmpty {
            var consecutive = 0
            for r in bpRecords {
                if r.bpCategory != .normal { consecutive += 1 } else { break }
            }
            if consecutive >= 3 {
                items.append(HighlightItem(
                    icon: "exclamationmark.triangle.fill",
                    text: "\(consecutive) consecutive BP readings above normal",
                    color: .red,
                    priority: 5
                ))
            }
        }

        // Morning vs Evening BP pattern
        if bpRecords.count >= 10 {
            var morningSys: [Int] = [], eveningSys: [Int] = []
            for r in bpRecords where r.timestamp >= fourteenDaysAgo {
                let h = calendar.component(.hour, from: r.timestamp)
                if h >= 5 && h < 12 { morningSys.append(r.systolic) }
                else if h >= 17 && h <= 23 { eveningSys.append(r.systolic) }
            }
            if morningSys.count >= 5, eveningSys.count >= 5 {
                let mAvg = morningSys.reduce(0, +) / morningSys.count
                let eAvg = eveningSys.reduce(0, +) / eveningSys.count
                let diff = abs(mAvg - eAvg)
                if diff >= 5 {
                    let higher = mAvg > eAvg ? "morning" : "evening"
                    items.append(HighlightItem(
                        icon: "clock.arrow.2.circlepath",
                        text: "BP averages \(diff) pts higher in the \(higher)",
                        color: .indigo,
                        priority: 20
                    ))
                }
            }
        }

        // Multi-metric correlation: steps vs BP
        let stepRecords = dataStore.records(for: MetricType.stepCount)
        if !bpRecords.isEmpty, stepRecords.count >= 10 {
            // Group both by day, compare BP on high-step days vs low-step days
            var dailySteps: [Date: Double] = [:]
            var dailyBP: [Date: [Int]] = [:]
            for r in stepRecords where r.timestamp >= fourteenDaysAgo {
                let day = calendar.startOfDay(for: r.timestamp)
                dailySteps[day, default: 0] += r.primaryValue
            }
            for r in bpRecords where r.timestamp >= fourteenDaysAgo {
                let day = calendar.startOfDay(for: r.timestamp)
                dailyBP[day, default: []].append(r.systolic)
            }
            let commonDays = Set(dailySteps.keys).intersection(Set(dailyBP.keys))
            if commonDays.count >= 6 {
                let sorted = commonDays.sorted()
                let commonStepValues = commonDays.compactMap { dailySteps[$0] }.sorted()
                if commonStepValues.count >= 2 {
                    let medianSteps = commonStepValues[commonStepValues.count / 2]
                    var highStepBP: [Int] = [], lowStepBP: [Int] = []
                    for day in sorted {
                        guard let bp = dailyBP[day], let steps = dailySteps[day] else { continue }
                        let avgBP = bp.reduce(0, +) / bp.count
                        if steps >= medianSteps { highStepBP.append(avgBP) }
                        else { lowStepBP.append(avgBP) }
                    }
                    if highStepBP.count >= 3, lowStepBP.count >= 3 {
                        let highAvg = highStepBP.reduce(0, +) / highStepBP.count
                        let lowAvg = lowStepBP.reduce(0, +) / lowStepBP.count
                        let diff = lowAvg - highAvg
                        if diff >= 3 {
                            items.append(HighlightItem(
                                icon: "figure.walk",
                                text: "BP tends to be \(diff) pts lower on active days",
                                color: .teal,
                                priority: 25
                            ))
                        }
                    }
                }
            }
        }

        // Sort by priority (lower = shown first), cap at 5
        return Array(items.sorted { $0.priority < $1.priority }.prefix(5))
    }

    private func computeStreak(allRecords: [HealthRecord], calendar: Calendar, now: Date) -> Int {
        let today = calendar.startOfDay(for: now)
        var daysWithData = Set<Date>()
        for record in allRecords {
            let day = calendar.startOfDay(for: record.timestamp)
            daysWithData.insert(day)
            if today.timeIntervalSince(day) > 366 * 86400 { break }
        }
        var streak = 0
        var day = today
        while daysWithData.contains(day) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    // MARK: - Quick Log

    private func computeQuickLogMetrics(dataStore: HealthDataStore, customMetrics: [CustomMetric]) -> [QuickLogMetric] {
        var result: [QuickLogMetric] = []

        // BP first if has data
        if dataStore.availableMetricTypes.contains(MetricType.bloodPressure) {
            if let def = MetricRegistry.definition(for: MetricType.bloodPressure) {
                result.append(QuickLogMetric(id: MetricType.bloodPressure, name: def.name, icon: def.icon, color: def.color, isCustom: false))
            }
        }

        // All custom metrics (always manual)
        for cm in customMetrics {
            let def = MetricRegistry.definition(for: cm.metricType)
            result.append(QuickLogMetric(
                id: cm.metricType,
                name: def?.name ?? cm.name,
                icon: def?.icon ?? cm.icon,
                color: def?.color ?? cm.color,
                isCustom: true
            ))
        }

        // Other manually-logged metrics
        let customTypes = Set(customMetrics.map(\.metricType))
        for (type, records) in dataStore.recordsByType {
            guard type != MetricType.bloodPressure, !customTypes.contains(type) else { continue }
            guard records.contains(where: { $0.isManualEntry }) else { continue }
            if let def = MetricRegistry.definition(for: type) {
                result.append(QuickLogMetric(id: type, name: def.name, icon: def.icon, color: def.color, isCustom: false))
            }
        }

        return Array(result.prefix(8))
    }

    // MARK: - Moving Averages

    private func computeMovingAverages(dataStore: HealthDataStore, sevenDaysAgo: Date, fourteenDaysAgo: Date) -> [MovingAverageRow] {
        var rows: [MovingAverageRow] = []

        // Ordered by registry
        var orderedTypes: [String] = []
        for category in MetricCategory.allCases {
            for def in MetricRegistry.definitions(for: category) where dataStore.availableMetricTypes.contains(def.type) {
                orderedTypes.append(def.type)
            }
        }

        for type in orderedTypes {
            let records = dataStore.records(for: type)
            let recent = records.filter { $0.timestamp >= sevenDaysAgo }
            let prev = records.filter { $0.timestamp >= fourteenDaysAgo && $0.timestamp < sevenDaysAgo }
            guard recent.count >= 2 else { continue }
            let def = MetricRegistry.definition(for: type)
            let lowerIsBetter = type == MetricType.bloodPressure || type == MetricType.restingHeartRate

            let currentFormatted: String
            let previousFormatted: String?
            let improving: Bool?

            if type == MetricType.bloodPressure {
                let curSys = Double(recent.map(\.systolic).reduce(0, +)) / Double(recent.count)
                let curDia = Double(recent.map(\.diastolic).reduce(0, +)) / Double(recent.count)
                currentFormatted = "\(Int(curSys))/\(Int(curDia))"
                if prev.count >= 2 {
                    let prevSys = Double(prev.map(\.systolic).reduce(0, +)) / Double(prev.count)
                    let prevDia = Double(prev.map(\.diastolic).reduce(0, +)) / Double(prev.count)
                    previousFormatted = "\(Int(prevSys))/\(Int(prevDia))"
                    improving = curSys < prevSys
                } else {
                    previousFormatted = nil; improving = nil
                }
            } else {
                let curAvg = recent.map(\.primaryValue).reduce(0, +) / Double(recent.count)
                currentFormatted = def?.formatValue(curAvg) ?? String(format: "%.1f", curAvg)
                if prev.count >= 2 {
                    let prevAvg = prev.map(\.primaryValue).reduce(0, +) / Double(prev.count)
                    previousFormatted = def?.formatValue(prevAvg)
                    improving = lowerIsBetter ? curAvg < prevAvg : curAvg > prevAvg
                } else {
                    previousFormatted = nil; improving = nil
                }
            }

            rows.append(MovingAverageRow(
                id: type,
                name: def?.name ?? type,
                icon: def?.icon ?? "chart.xyaxis.line",
                color: def?.color ?? .gray,
                currentAvg: currentFormatted,
                previousAvg: previousFormatted,
                improving: improving,
                lowerIsBetter: lowerIsBetter
            ))
        }

        return Array(rows.prefix(5))
    }

    // MARK: - Weekly Recap

    private func computeWeeklyRecap(dataStore: HealthDataStore, calendar: Calendar, now: Date) -> WeeklyRecapData? {
        // This week: Monday to now
        guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return nil }
        let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) ?? thisWeekStart

        let thisWeek = dataStore.allRecords.filter { $0.timestamp >= thisWeekStart }
        let lastWeek = dataStore.allRecords.filter { $0.timestamp >= lastWeekStart && $0.timestamp < thisWeekStart }

        guard thisWeek.count >= 3 || lastWeek.count >= 3 else { return nil }

        let streak = computeStreak(allRecords: dataStore.allRecords, calendar: calendar, now: now)

        // Metric summaries for top metrics
        var summaries: [MetricWeeklySummary] = []
        for (type, allTypeRecords) in dataStore.recordsByType {
            let tw = allTypeRecords.filter { $0.timestamp >= thisWeekStart }
            let lw = allTypeRecords.filter { $0.timestamp >= lastWeekStart && $0.timestamp < thisWeekStart }
            guard tw.count >= 2 else { continue }
            let def = MetricRegistry.definition(for: type)
            let lowerIsBetter = type == MetricType.bloodPressure || type == MetricType.restingHeartRate

            let twAvg: String
            let lwAvg: String?
            let improving: Bool?

            if type == MetricType.bloodPressure {
                let sys = Double(tw.map(\.systolic).reduce(0, +)) / Double(tw.count)
                let dia = Double(tw.map(\.diastolic).reduce(0, +)) / Double(tw.count)
                twAvg = "\(Int(sys))/\(Int(dia))"
                if lw.count >= 2 {
                    let pSys = Double(lw.map(\.systolic).reduce(0, +)) / Double(lw.count)
                    let pDia = Double(lw.map(\.diastolic).reduce(0, +)) / Double(lw.count)
                    lwAvg = "\(Int(pSys))/\(Int(pDia))"
                    improving = sys < pSys
                } else { lwAvg = nil; improving = nil }
            } else {
                let a = tw.map(\.primaryValue).reduce(0, +) / Double(tw.count)
                twAvg = def?.formatValue(a) ?? String(format: "%.1f", a)
                if lw.count >= 2 {
                    let pa = lw.map(\.primaryValue).reduce(0, +) / Double(lw.count)
                    lwAvg = def?.formatValue(pa)
                    improving = lowerIsBetter ? a < pa : a > pa
                } else { lwAvg = nil; improving = nil }
            }

            summaries.append(MetricWeeklySummary(
                id: type, name: def?.name ?? type,
                icon: def?.icon ?? "chart.xyaxis.line", color: def?.color ?? .gray,
                thisWeekAvg: twAvg, lastWeekAvg: lwAvg, improving: improving, lowerIsBetter: lowerIsBetter
            ))
        }

        let fmt = Date.FormatStyle().month(.abbreviated).day()
        let weekLabel = "\(thisWeekStart.formatted(fmt)) – \(now.formatted(fmt))"

        return WeeklyRecapData(
            thisWeekCount: thisWeek.count,
            lastWeekCount: lastWeek.count,
            streak: streak,
            metricSummaries: Array(summaries.prefix(3)),
            weekLabel: weekLabel
        )
    }

    // MARK: - Nudges

    private func computeNudges(dataStore: HealthDataStore, customMetrics: [CustomMetric], now: Date) -> [NudgeItem] {
        let calendar = Calendar.current
        let todayKey = now.formatted(.dateTime.year().month().day())
        var result: [NudgeItem] = []

        // --- Reminder-based nudges (highest priority) ---
        for cm in customMetrics where cm.reminderEnabled {
            let type = cm.metricType
            let dismissKey = "nudge_dismissed_\(type)"
            if UserDefaults.standard.string(forKey: dismissKey) == todayKey { continue }

            // Find latest record today for this metric
            let todayRecords = dataStore.records(for: type).filter { calendar.isDateInToday($0.timestamp) }
            let latestToday = todayRecords.first?.timestamp

            if NotificationManager.shared.hasUnfulfilledReminder(cm, latestRecordToday: latestToday) {
                let def = MetricRegistry.definition(for: type)
                result.append(NudgeItem(
                    id: type,
                    name: def?.name ?? cm.name,
                    icon: "bell.fill",
                    color: def?.color ?? cm.color,
                    hoursSinceLastLog: 0,
                    message: "Reminder: time to log \(cm.name)"
                ))
            }
        }

        // --- Regular manual-metric nudges ---
        let reminderTypes = Set(result.map(\.id))
        var manualTypes: [String: Date] = [:]
        for record in dataStore.allRecords where record.isManualEntry {
            if manualTypes[record.metricType] == nil {
                manualTypes[record.metricType] = record.timestamp
            }
        }

        for (type, lastDate) in manualTypes {
            guard !reminderTypes.contains(type) else { continue }

            let hours = now.timeIntervalSince(lastDate) / 3600
            guard hours > 16 else { continue }

            let dismissKey = "nudge_dismissed_\(type)"
            if UserDefaults.standard.string(forKey: dismissKey) == todayKey { continue }

            guard now.timeIntervalSince(lastDate) < 14 * 86400 else { continue }

            let def = MetricRegistry.definition(for: type)
            result.append(NudgeItem(
                id: type,
                name: def?.name ?? type,
                icon: def?.icon ?? "chart.xyaxis.line",
                color: def?.color ?? .gray,
                hoursSinceLastLog: Int(hours),
                message: "Last logged \(lastDate.formatted(.relative(presentation: .named)))"
            ))
        }

        return Array(result.prefix(3))
    }

    // MARK: - Goal Progress

    private func computeGoalProgress(
        dataStore: HealthDataStore,
        goals: [MetricGoal],
        sevenDaysAgo: Date,
        fourteenDaysAgo: Date
    ) -> [GoalProgressData] {
        return goals.filter(\.isActive).compactMap { goal in
            let records = dataStore.records(for: goal.metricType)
            let thisWeek = records.filter { $0.timestamp >= sevenDaysAgo }
            let lastWeek = records.filter { $0.timestamp >= fourteenDaysAgo && $0.timestamp < sevenDaysAgo }
            let def = MetricRegistry.definition(for: goal.metricType)

            guard !thisWeek.isEmpty else { return nil }

            let inTarget = thisWeek.filter { r in
                switch goal.targetType {
                case "below":
                    if goal.metricType == MetricType.bloodPressure {
                        return r.primaryValue < goal.targetValue && Double(r.diastolic) < (goal.targetValueHigh ?? 80)
                    }
                    return r.primaryValue < goal.targetValue
                case "above":
                    return r.primaryValue > goal.targetValue
                case "range":
                    return r.primaryValue >= goal.targetValue && r.primaryValue <= (goal.targetValueHigh ?? goal.targetValue)
                default: return false
                }
            }

            let fraction = Double(inTarget.count) / Double(thisWeek.count)

            // Trend: compare this week fraction vs last week
            let trend: TrendDirection
            if !lastWeek.isEmpty {
                let lastInTarget = lastWeek.filter { r in
                    switch goal.targetType {
                    case "below":
                        if goal.metricType == MetricType.bloodPressure {
                            return r.primaryValue < goal.targetValue && Double(r.diastolic) < (goal.targetValueHigh ?? 80)
                        }
                        return r.primaryValue < goal.targetValue
                    case "above": return r.primaryValue > goal.targetValue
                    case "range": return r.primaryValue >= goal.targetValue && r.primaryValue <= (goal.targetValueHigh ?? goal.targetValue)
                    default: return false
                    }
                }
                let lastFraction = Double(lastInTarget.count) / Double(lastWeek.count)
                trend = fraction > lastFraction + 0.05 ? .up : (fraction < lastFraction - 0.05 ? .down : .flat)
            } else {
                trend = .flat
            }

            return GoalProgressData(
                id: goal.id,
                metricType: goal.metricType,
                name: def?.name ?? goal.metricType,
                icon: def?.icon ?? "target",
                color: def?.color ?? .gray,
                targetDescription: goal.targetDescription,
                fraction: fraction,
                readingsThisWeek: thisWeek.count,
                readingsInTarget: inTarget.count,
                trend: trend
            )
        }
    }
}
