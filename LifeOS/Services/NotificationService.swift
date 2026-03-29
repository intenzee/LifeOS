import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error { print("🔔 Notification permission error: \(error)") }
            else { print("🔔 Notification permission granted: \(granted)") }
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
            if let error { print("❌ Reminder error: \(error)") }
            else { print("✅ Reminder set for \(date)") }
        }
    }

    func cancelReminder(for todoId: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [todoId.uuidString])
    }
}
