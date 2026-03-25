import Foundation
import UserNotifications

/// Manages local notification reminders for custom metrics.
///
/// Handles permission requests, scheduling repeating calendar-based notifications,
/// actionable notification responses (Log Now / Snooze), snooze limits, and
/// midnight expiration so reminders never carry over to the next day.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationManager()

    /// Posted when the user taps "Log Now" or taps the notification banner.
    /// `userInfo` contains `["metricType": String]`.
    static let openMetricFormNotification = Notification.Name("VS_OpenMetricForm")

    // MARK: - Constants

    private static let categoryID = "METRIC_REMINDER"
    private static let logNowActionID = "LOG_NOW"
    private static let snoozeActionID = "SNOOZE"
    private static let maxSnoozes = 2
    private static let snoozeInterval: TimeInterval = 30 * 60 // 30 minutes

    // MARK: - Init

    private override init() {
        super.init()
    }

    // MARK: - Setup

    /// Call once at app launch to register as delegate and define actionable categories.
    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let logAction = UNNotificationAction(
            identifier: Self.logNowActionID,
            title: "Log Now",
            options: .foreground
        )
        let snoozeAction = UNNotificationAction(
            identifier: Self.snoozeActionID,
            title: "Snooze 30 min",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [logAction, snoozeAction],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }

    // MARK: - Permission

    /// Requests notification permission. Returns `true` if granted.
    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    // MARK: - Schedule / Cancel

    /// Schedules (or reschedules) repeating calendar notifications for a metric's reminder.
    /// Removes any existing notifications for this metric first.
    func scheduleReminder(for metric: CustomMetric) {
        let center = UNUserNotificationCenter.current()
        cancelReminder(for: metric.metricType)

        guard metric.reminderEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time to log \(metric.name)"
        content.body = "Tap to record your \(metric.name)."
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        content.userInfo = [
            "metricType": metric.metricType,
            "metricName": metric.name,
        ]

        for weekday in metric.effectiveReminderDays {
            var components = DateComponents()
            components.hour = metric.reminderHour
            components.minute = metric.reminderMinute
            components.weekday = weekday

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let identifier = "reminder-\(metric.metricType)-wd\(weekday)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            center.add(request)
        }
    }

    /// Removes all pending and delivered notifications for a metric.
    func cancelReminder(for metricType: String) {
        let center = UNUserNotificationCenter.current()
        let prefix = "reminder-\(metricType)"
        let snoozePrefix = "snooze-\(metricType)"

        center.getPendingNotificationRequests { requests in
            let ids = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) || $0.hasPrefix(snoozePrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    // MARK: - Snooze

    /// Schedules a one-shot snooze notification, respecting midnight boundary and max count.
    private func scheduleSnooze(metricType: String, metricName: String) {
        let calendar = Calendar.current
        let now = Date.now

        // — Snooze count limit —
        let dayKey = now.formatted(.dateTime.year().month().day())
        let countKey = "snooze_count_\(metricType)_\(dayKey)"
        let currentCount = UserDefaults.standard.integer(forKey: countKey)
        guard currentCount < Self.maxSnoozes else { return }

        // — Midnight boundary —
        let snoozeFireDate = now.addingTimeInterval(Self.snoozeInterval)
        guard calendar.isDate(snoozeFireDate, inSameDayAs: now) else {
            // Less than 30 min to midnight — don't snooze across days
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Reminder: Log \(metricName)"
        content.body = "You snoozed this reminder. Tap to log now."
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        content.userInfo = [
            "metricType": metricType,
            "metricName": metricName,
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Self.snoozeInterval, repeats: false)
        let identifier = "snooze-\(metricType)-\(currentCount)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
        UserDefaults.standard.set(currentCount + 1, forKey: countKey)
    }

    // MARK: - Reminder-Aware Nudge Check

    /// Returns `true` if the metric has a reminder today, the reminder time has passed,
    /// and no record has been logged after the reminder time.
    func hasUnfulfilledReminder(_ metric: CustomMetric, latestRecordToday: Date?) -> Bool {
        guard metric.reminderEnabled else { return false }

        let calendar = Calendar.current
        let now = Date.now
        let todayWeekday = calendar.component(.weekday, from: now)

        guard metric.effectiveReminderDays.contains(todayWeekday) else { return false }

        // Build the reminder fire time for today
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = metric.reminderHour
        components.minute = metric.reminderMinute
        guard let reminderTime = calendar.date(from: components) else { return false }

        // Reminder hasn't fired yet today
        guard now >= reminderTime else { return false }

        // If user logged after the reminder time, it's fulfilled
        if let latest = latestRecordToday, latest >= reminderTime { return false }

        return true
    }

    // MARK: - Cleanup

    /// Clears day-scoped snooze counts for yesterday and older. Call on app launch.
    func cleanUpStaleSnoozeState() {
        let defaults = UserDefaults.standard
        let todayKey = Date.now.formatted(.dateTime.year().month().day())

        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("snooze_count_") {
            // Key format: snooze_count_{metricType}_{dayKey}
            if !key.hasSuffix(todayKey) {
                defaults.removeObject(forKey: key)
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show banner even when app is in foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Handle user interaction with the notification.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let metricType = userInfo["metricType"] as? String ?? ""
        let metricName = userInfo["metricName"] as? String ?? ""

        switch response.actionIdentifier {
        case Self.logNowActionID, UNNotificationDefaultActionIdentifier:
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Self.openMetricFormNotification,
                    object: nil,
                    userInfo: ["metricType": metricType]
                )
            }

        case Self.snoozeActionID:
            scheduleSnooze(metricType: metricType, metricName: metricName)

        default:
            break
        }
    }
}
