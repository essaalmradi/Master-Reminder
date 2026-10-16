import SwiftUI
import AlarmKit
import ActivityKit
import AVFoundation
import UserNotifications
import ReminderCore
import ReminderDesign

@MainActor final class PhoneModel: ObservableObject {
    @Published private(set) var data = AppData()
    @Published var error: String?
    @Published var isSaving = false
    @Published var creating = false
    @Published var editing: Reminder?
    @Published var selectedTab = 0
    private var canSave = true
    private let storage: StorageManager
    private let alarms = AlarmManager.shared
    let audio = AudioPreview()
    let sounds = PhoneAudio()
    private let notifications = UNUserNotificationCenter.current()
    private let notificationDelegate = PhoneNotificationDelegate()
    var isSmoke: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") }
    var upcoming: [Occurrence] { ReminderScheduler.upcoming(reminders: data.reminders, snoozes: [], now: Date(), ledger: [:]) }
    init() {
        Brand.registerFonts()
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(ProcessInfo.processInfo.arguments.contains("--ui-testing") ? "MasterReminder-Tests" : "MasterReminder")
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--reset-test-data") { try? FileManager.default.removeItem(at: directory) }
        storage = StorageManager(url: directory.appendingPathComponent("data.json"))
        do { data = try storage.load() } catch { canSave = false; self.error = "تعذّر قراءة بياناتك. لم نغيّر الملف الأصلي: " + error.localizedDescription }
        notifications.delegate = notificationDelegate
        notificationDelegate.open = { [weak self] id in
            guard let self else { return }; self.selectedTab = 1; self.editing = self.data.reminders.first { $0.id == id }
        }
    }
    func save(_ value: Reminder) async -> Bool {
        guard !isSaving, canSave else { return false }
        isSaving = true; defer { isSaving = false }
        let previous = data.reminders.first { $0.id == value.id }
        do {
            let reminder = try value.validated()
            if reminder.enabled { try await requestPermission(silent: reminder.sound == .none) }
            try await schedule(reminder)
            var updated = data; updated.upsert(reminder)
            do { try storage.save(updated) }
            catch { try? await cancel(reminder); if let previous { try? await schedule(previous) }; throw error }
            data = updated; creating = false; editing = nil; return true
        } catch {
            if let previous { try? await schedule(previous) } else { try? await cancel(value) }
            self.error = "لم يُحفظ التنبيه: " + error.localizedDescription; return false
        }
    }
    func delete(_ reminder: Reminder) async {
        guard canSave, !isSaving else { return }
        isSaving = true; defer { isSaving = false }
        do {
            try await cancel(reminder)
            var updated = data; updated.delete(reminder.id)
            do { try storage.save(updated) } catch { try? await schedule(reminder); throw error }
            data = updated
        } catch { self.error = "تعذّر حذف التنبيه: " + error.localizedDescription }
    }
    func requestPermission(silent: Bool = false) async throws {
        guard !isSmoke else { return }
        if silent {
            guard try await notifications.requestAuthorization(options: [.alert]) else { throw PhoneError.notifications }
            return
        }
        let state = try await alarms.requestAuthorization()
        guard state == .authorized else { throw PhoneError.permission }
    }
    func refreshMissingAlarms() async {
        guard !isSmoke, !isSaving, canSave else { return }
        do {
            let audibleAllowed = alarms.authorizationState == .authorized
            let existing = audibleAllowed ? Set(try alarms.alarms.map(\.id)) : Set<UUID>()
            let pending = Set(await notifications.pendingNotificationRequests().map(\.identifier))
            let settings = await notifications.notificationSettings()
            for reminder in data.reminders where reminder.enabled && (reminder.repeatRule != .once || reminder.date > Date()) {
                if reminder.sound == .none {
                    let expected = Set(PhoneNotifications.requests(for: reminder).map(\.identifier))
                    if settings.authorizationStatus == .authorized && !expected.isSubset(of: pending) { try await schedule(reminder) }
                } else if audibleAllowed && !existing.contains(reminder.id) { try await schedule(reminder) }
            }
        } catch { self.error = "تعذّرت استعادة بعض المنبهات: " + error.localizedDescription }
    }
    static func libraryReminder(_ entry: LibraryEntry) -> Reminder {
        var value = entry.reminder
        if entry.category == "quran" { value.sound = .quran }
        else if entry.audioURL != nil { value.sound = .library }
        else { value.sound = .speech }
        return value
    }
    private func cancel(_ reminder: Reminder) async throws {
        guard !isSmoke else { return }
        if alarms.authorizationState == .authorized, try alarms.alarms.contains(where: { $0.id == reminder.id }) { try alarms.cancel(id: reminder.id) }
        let ids = await notifications.pendingNotificationRequests().map(\.identifier).filter { PhoneNotifications.belongs($0, to: reminder.id) }
        notifications.removePendingNotificationRequests(withIdentifiers: ids)
    }
    private func scheduleSilent(_ reminder: Reminder) async throws {
        let requests = PhoneNotifications.requests(for: reminder)
        let existing = await notifications.pendingNotificationRequests()
        let old = existing.map(\.identifier).filter { PhoneNotifications.belongs($0, to: reminder.id) }
        guard existing.count - old.count + requests.count <= 60 else { throw PhoneError.tooManyNotifications }
        for request in requests { try await notifications.add(request) }
        if alarms.authorizationState == .authorized, try alarms.alarms.contains(where: { $0.id == reminder.id }) { try alarms.cancel(id: reminder.id) }
        let retained = Set(requests.map(\.identifier))
        notifications.removePendingNotificationRequests(withIdentifiers: old.filter { !retained.contains($0) })
    }
    func testAlarm() async {
        do {
            try await requestPermission()
            var reminder = Reminder(title: "لحظة ذكر · تجربة", date: Date().addingTimeInterval(10))
            reminder.preAlertMinutes = 0; reminder.type = .dhikr; reminder.sound = .dhikr
            // A fixed test ID replaces the previous experiment instead of accumulating alarms.
            reminder.id = UUID(uuidString: "0B752C8E-1A99-4FF1-88AA-810984B613A2")!
            try await schedule(reminder)
        } catch { self.error = "تعذّرت تجربة المنبّه: " + error.localizedDescription }
    }
    private func schedule(_ reminder: Reminder) async throws {
        guard !isSmoke else { return }
        guard reminder.enabled else { try await cancel(reminder); return }
        guard reminder.repeatRule != .once || reminder.date > Date() else { throw PhoneError.past }
        if reminder.sound == .none { try await scheduleSilent(reminder); return }
        // Finish downloading/conversion before touching the previous working alarm.
        let soundName = try await sounds.prepareAlarm(reminder)
        let sound: AlertConfiguration.AlertSound = soundName.map { .named($0) } ?? .default
        if try alarms.alarms.contains(where: { $0.id == reminder.id }) { try alarms.cancel(id: reminder.id) }
        let cal = Calendar.current
        let schedule: Alarm.Schedule
        if reminder.repeatRule == .once { schedule = .fixed(reminder.date) }
        else {
            let weekdays: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
            let days: [Locale.Weekday]
            switch reminder.repeatRule {
            case .weekdays: days = reminder.weekdays.sorted().map { weekdays[$0 - 1] }
            case .weekly: days = [weekdays[cal.component(.weekday, from: reminder.date) - 1]]
            default: days = weekdays
            }
            schedule = .relative(.init(time: .init(hour: cal.component(.hour, from: reminder.date), minute: cal.component(.minute, from: reminder.date)), repeats: .weekly(days)))
        }
        let stop = AlarmButton(text: "إيقاف", textColor: .white, systemImageName: "stop.circle")
        let snooze = AlarmButton(text: "تأجيل", textColor: .white, systemImageName: "zzz")
        let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: reminder.title), stopButton: stop,
            secondaryButton: reminder.snoozeAllowed ? snooze : nil, secondaryButtonBehavior: reminder.snoozeAllowed ? .countdown : nil)
        let presentation: AlarmPresentation
        if reminder.snoozeAllowed {
            presentation = AlarmPresentation(alert: alert,
                countdown: .init(title: LocalizedStringResource(stringLiteral: reminder.title), pauseButton: .init(text: "إيقاف مؤقت", textColor: .white, systemImageName: "pause")),
                paused: .init(title: "متوقف مؤقتًا", resumeButton: .init(text: "استئناف", textColor: .white, systemImageName: "play")))
        } else { presentation = AlarmPresentation(alert: alert) }
        let attributes = AlarmAttributes(presentation: presentation, metadata: ReminderAlarmMetadata(title: reminder.title), tintColor: Brand.ocean)
        let configuration = AlarmManager.AlarmConfiguration<ReminderAlarmMetadata>(
            countdownDuration: reminder.snoozeAllowed ? .init(preAlert: nil, postAlert: 300) : nil,
            schedule: schedule, attributes: attributes, sound: sound)
        _ = try await alarms.schedule(id: reminder.id, configuration: configuration)
        let silentIDs = await notifications.pendingNotificationRequests().map(\.identifier).filter { PhoneNotifications.belongs($0, to: reminder.id) }
        notifications.removePendingNotificationRequests(withIdentifiers: silentIDs)
    }
}

enum PhoneError: LocalizedError {
    case permission, past, notifications, noVoice, speechFailed, tooManyNotifications
    var errorDescription: String? {
        switch self { case .permission: return "اسمح بالمنبّهات من إعدادات Master Reminder حتى تعمل التذكيرات."; case .past: return "اختر وقتًا في المستقبل."
        case .notifications: return "اسمح بالإشعارات من إعدادات Master Reminder لعرض التذكير الصامت."
        case .noVoice: return "لا يوجد الصوت العربي المختار على الجهاز. نزّل صوتًا عربيًا من تسهيلات الاستخدام في إعدادات الآيفون، أو اختر تسجيلًا."
        case .speechFailed: return "تعذّر تجهيز القراءة الصوتية. تأكد من تنزيل الصوت العربي وحاول مجددًا."
        case .tooManyNotifications: return "وصلت إلى عدد التذكيرات الصامتة المتاحة. احذف أو عطّل بعض التذكيرات أولًا." }
    }
}
