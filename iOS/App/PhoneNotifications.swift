import Foundation
import UserNotifications
import ReminderCore

struct PhoneNotifications {
    static func requests(for reminder: Reminder) -> [UNNotificationRequest] {
        let calendar = Calendar.current
        let content = UNMutableNotificationContent()
        content.title = reminder.title; content.body = reminder.detail; content.sound = nil
        content.userInfo = ["reminderID": reminder.id.uuidString]
        var base = calendar.dateComponents([.hour, .minute], from: reminder.date)
        base.calendar = calendar
        let days: [Int?]
        switch reminder.repeatRule {
        case .once:
            base = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.date); base.calendar = calendar; days = [nil]
        case .daily: days = [nil]
        case .weekly: days = [calendar.component(.weekday, from: reminder.date)]
        case .weekdays: days = reminder.weekdays.sorted().map { Optional($0) }
        }
        return days.map { day in
            var date = base; date.weekday = day
            let id = reminder.id.uuidString + "-silent-" + (day.map(String.init) ?? reminder.repeatRule.rawValue)
            return UNNotificationRequest(identifier: id, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: reminder.repeatRule != .once))
        }
    }
    static func belongs(_ id: String, to reminderID: UUID) -> Bool { id.hasPrefix(reminderID.uuidString + "-silent-") }
}

@MainActor final class PhoneNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var open: ((UUID) -> Void)?
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) { completion([.banner, .list]) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completion: @escaping () -> Void) {
        if let raw = response.notification.request.content.userInfo["reminderID"] as? String, let id = UUID(uuidString: raw) {
            Task { @MainActor in self.open?(id) }
        }
        completion()
    }
}
