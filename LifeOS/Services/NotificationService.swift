import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error { Log.automation.error("Notification permission error: \(error.localizedDescription, privacy: .public)") }
            else { Log.automation.info("Notification permission granted: \(granted)") }
        }
    }

    func scheduleReminder(for todo: TodoItem, at date: Date) {
        guard date > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "LifeOS Reminder"
        content.body = todo.title
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: todo.id.uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error { Log.automation.error("Reminder scheduling failed: \(error.localizedDescription, privacy: .public)") }
            else { Log.automation.info("Reminder set for \(date, privacy: .private)") }
        }
    }

    func cancelReminder(for todoId: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [todoId.uuidString])
    }

    // MARK: - Water reminders (repeating)

    private static let waterReminderIDs = (8...21).map { "water_reminder_\($0)" }

    /// Schedules a repeating hydration nudge every `intervalHours` between
    /// `startHour` and `endHour` (24h). Cancels any previous water reminders first.
    func scheduleWaterReminders(startHour: Int = 9, endHour: Int = 21, intervalHours: Int = 2) {
        cancelWaterReminders()
        var hour = startHour
        while hour <= endHour {
            let content = UNMutableNotificationContent()
            content.title = "💧 Time to hydrate"
            content.body = "Log a glass of water in LifeOS."
            content.sound = .default

            var comps = DateComponents()
            comps.hour = hour
            comps.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = UNNotificationRequest(identifier: "water_reminder_\(hour)", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
            hour += max(1, intervalHours)
        }
    }

    func cancelWaterReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Self.waterReminderIDs)
    }

    // MARK: - Meal reminders (repeating, daily)

    struct MealReminder { let id: String; let hour: Int; let minute: Int; let title: String }

    static let defaultMealReminders = [
        MealReminder(id: "meal_breakfast", hour: 8, minute: 0, title: "🍳 Log your breakfast"),
        MealReminder(id: "meal_lunch", hour: 13, minute: 0, title: "🥗 Log your lunch"),
        MealReminder(id: "meal_dinner", hour: 20, minute: 0, title: "🍽️ Log your dinner")
    ]

    func scheduleMealReminders(_ reminders: [MealReminder] = defaultMealReminders) {
        cancelMealReminders()
        for meal in reminders {
            let content = UNMutableNotificationContent()
            content.title = meal.title
            content.body = "Keep your nutrition on track in LifeOS."
            content.sound = .default
            var comps = DateComponents()
            comps.hour = meal.hour
            comps.minute = meal.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = UNNotificationRequest(identifier: meal.id, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }

    func cancelMealReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: Self.defaultMealReminders.map { $0.id })
    }
}

/// Persisted on/off flags for the reminder toggles.
final class ReminderSettings {
    static let shared = ReminderSettings()
    private let waterKey = "waterRemindersEnabled"
    private let mealKey = "mealRemindersEnabled"

    var waterEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: waterKey) }
        set { UserDefaults.standard.set(newValue, forKey: waterKey) }
    }
    var mealEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: mealKey) }
        set { UserDefaults.standard.set(newValue, forKey: mealKey) }
    }
}
