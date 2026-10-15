import AppKit
import UserNotifications
import ReminderCore
import Combine

@MainActor final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var status: UNAuthorizationStatus = .notDetermined
    private let center = UNUserNotificationCenter.current()
    var onAction: ((String, String) -> Void)?
    var isPaused: () -> Bool = { false }
    var shouldPlayForegroundSound: () -> Bool = { true }

    override init() {
        super.init()
        center.delegate = self
        let snooze = [5, 10, 15].map { UNNotificationAction(identifier: "snooze-\($0)", title: "تأجيل \($0) دقائق") }
        let done = UNNotificationAction(identifier: "done", title: "تم")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "reminder", actions: [done] + snooze, intentIdentifiers: []),
            UNNotificationCategory(identifier: "no-snooze", actions: [done], intentIdentifiers: [])
        ])
    }
    var statusText: String {
        switch status {
        case .authorized, .provisional, .ephemeral: return "مسموح بها"
        case .denied: return "غير مسموح بها"
        case .notDetermined: return "لم يُطلب الإذن بعد"
        @unknown default: return "غير معروف"
        }
    }
    func refresh() async { status = await center.notificationSettings().authorizationStatus }
    func requestPermission() async throws {
        _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refresh()
    }
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
    }
    func sync(_ plan: [PlannedNotification], settings: AppSettings, validPrefixes: Set<String>) async throws {
        await refresh()
        let pending = await center.pendingNotificationRequests()
        let desired = Set(plan.map(\.id))
        let now = Date().timeIntervalSince1970
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { request in
            guard request.identifier.hasPrefix("mr-"), !desired.contains(request.identifier) else { return false }
            // Let a due OS request complete; runtime's deadline must not race and cancel its banner.
            let fireAt = request.content.userInfo["fireAt"] as? Double ?? 0
            let finishing = fireAt <= now && now - fireAt < 5 &&
                validPrefixes.contains(where: { request.identifier.hasPrefix($0) }) && !settings.isPaused(at: Date())
            return !finishing
        }.map(\.identifier))
        let delivered = await center.deliveredNotifications()
        let cutoff = Date().addingTimeInterval(TimeInterval(-settings.graceMinutes * 60))
        let stale = delivered.filter { notification in
            let id = notification.request.identifier
            return id.hasPrefix("mr-") && (notification.date < cutoff || !validPrefixes.contains(where: { id.hasPrefix($0) }))
        }
        center.removeDeliveredNotifications(withIdentifiers: stale.map { $0.request.identifier })
        guard status == .authorized || status == .provisional else { return }
        let existing = Dictionary(uniqueKeysWithValues: pending.map { ($0.identifier, $0) })
        for item in plan {
            // A reconcile may cross a due boundary; never create an immediate duplicate.
            guard item.date.timeIntervalSinceNow > 0.5 else { continue }
            let content = UNMutableNotificationContent()
            let reminder = item.occurrence.reminder
            content.title = item.kind == .pre ? "باقي \(reminder.preAlertMinutes) دقائق على \(reminder.title)" : reminder.title
            content.body = reminder.detail.isEmpty ? "حان الوقت — خذ لحظة لنفسك." : reminder.detail
            // Due audio belongs to SoundManager even when our menu-bar app is in the background.
            // OS pre-alerts keep their normal short sound; due banners remain silent if the app quits.
            if item.kind == .pre && settings.soundEnabled && reminder.sound != .none { content.sound = .default }
            content.categoryIdentifier = item.kind == .due ? (reminder.snoozeAllowed ? "reminder" : "no-snooze") : ""
            content.userInfo = ["occurrenceID": item.occurrence.id, "due": item.occurrence.date.timeIntervalSince1970, "fireAt": item.date.timeIntervalSince1970]
            if let old = existing[item.id],
               let fireAt = old.content.userInfo["fireAt"] as? Double,
               abs(fireAt - item.date.timeIntervalSince1970) < 0.5,
               old.content.title == content.title, old.content.body == content.body,
               (old.content.sound == nil) == (content.sound == nil) { continue }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, item.date.timeIntervalSinceNow), repeats: false)
            try await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
        Log.notification.debug("Reconciled \(plan.count) pending notification candidates")
    }
    func clearOccurrence(_ id: String) {
        let ids = ["mr-\(id)-pre", "mr-\(id)-due"]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
    func clearAll() {
        center.removeAllPendingNotificationRequests(); center.removeAllDeliveredNotifications()
    }
    func test() async throws {
        await refresh()
        guard status == .authorized || status == .provisional else {
            throw NSError(domain: "MasterReminder", code: 1, userInfo: [NSLocalizedDescriptionKey: "اسمح بالإشعارات أولًا من الإعدادات."])
        }
        let content = UNMutableNotificationContent()
        content.title = "Master Reminder"; content.body = "الإشعارات جاهزة. موعدك القادم في وقته."
        if shouldPlayForegroundSound() { content.sound = .default }
        try await center.add(UNNotificationRequest(identifier: "test-notification", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)))
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                           withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            if self.isPaused() { completion([]); return }
            // Runtime SoundManager owns due audio, avoiding the double sound of banner + overlay.
            let due = notification.request.identifier.hasSuffix("-due")
            completion(!due && self.shouldPlayForegroundSound() ? [.banner, .list, .sound] : [.banner, .list])
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                           withCompletionHandler completion: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["occurrenceID"] as? String
        let action = response.actionIdentifier
        Task { @MainActor in
            if let id { self.onAction?(id, action) }
            completion()
        }
    }
}
