import SwiftUI
import AlarmKit
import ActivityKit
import AVFoundation
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
    var isSmoke: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") }
    var upcoming: [Occurrence] { ReminderScheduler.upcoming(reminders: data.reminders, snoozes: [], now: Date(), ledger: [:]) }
    init() {
        Brand.registerFonts()
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(ProcessInfo.processInfo.arguments.contains("--ui-testing") ? "MasterReminder-Tests" : "MasterReminder")
        storage = StorageManager(url: directory.appendingPathComponent("data.json"))
        do { data = try storage.load() } catch { canSave = false; self.error = "تعذّر قراءة بياناتك. لم نغيّر الملف الأصلي: " + error.localizedDescription }
    }
    func save(_ value: Reminder) async -> Bool {
        guard !isSaving, canSave else { return false }
        isSaving = true; defer { isSaving = false }
        let previous = data.reminders.first { $0.id == value.id }
        do {
            let reminder = try value.validated()
            if reminder.enabled { try await requestPermission() }
            try await schedule(reminder)
            var updated = data; updated.upsert(reminder)
            do { try storage.save(updated) }
            catch { try? alarms.cancel(id: reminder.id); if let previous { try? await schedule(previous) }; throw error }
            data = updated; creating = false; editing = nil; return true
        } catch {
            if let previous { try? await schedule(previous) }
            self.error = "لم يُحفظ التنبيه: " + error.localizedDescription; return false
        }
    }
    func delete(_ reminder: Reminder) async {
        guard canSave, !isSaving else { return }
        isSaving = true; defer { isSaving = false }
        do {
            if try alarms.alarms.contains(where: { $0.id == reminder.id }) { try alarms.cancel(id: reminder.id) }
            var updated = data; updated.delete(reminder.id)
            do { try storage.save(updated) } catch { try? await schedule(reminder); throw error }
            data = updated
        } catch { self.error = "تعذّر حذف التنبيه: " + error.localizedDescription }
    }
    func requestPermission() async throws {
        guard !isSmoke else { return }
        let state = try await alarms.requestAuthorization()
        guard state == .authorized else { throw PhoneError.permission }
    }
    func refreshMissingAlarms() async {
        guard !isSmoke, alarms.authorizationState == .authorized, canSave else { return }
        do {
            let existing = Set(try alarms.alarms.map(\.id))
            for reminder in data.reminders where reminder.enabled && !existing.contains(reminder.id) {
                if reminder.repeatRule != .once || reminder.date > Date() { try await schedule(reminder) }
            }
        } catch { self.error = "تعذّرت استعادة بعض المنبهات: " + error.localizedDescription }
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
        let existing = try alarms.alarms.contains { $0.id == reminder.id }
        if existing { try alarms.cancel(id: reminder.id) }
        guard reminder.enabled else { return }
        guard reminder.repeatRule != .once || reminder.date > Date() else { throw PhoneError.past }
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
        var sound: AlertConfiguration.AlertSound = .default
        if reminder.sound == .dhikr, let source = AppResources.url("dhikr-sample", "mp3") {
            let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Sounds")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("dhikr-sample.mp3")
            if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.copyItem(at: source, to: destination) }
            sound = .named("dhikr-sample.mp3")
        }
        let configuration = AlarmManager.AlarmConfiguration<ReminderAlarmMetadata>(
            countdownDuration: reminder.snoozeAllowed ? .init(preAlert: nil, postAlert: 300) : nil,
            schedule: schedule, attributes: attributes, sound: sound)
        _ = try await alarms.schedule(id: reminder.id, configuration: configuration)
    }
}

enum PhoneError: LocalizedError {
    case permission, past
    var errorDescription: String? {
        switch self { case .permission: return "اسمح بالمنبّهات من إعدادات Master Reminder حتى تعمل التذكيرات."; case .past: return "اختر وقتًا في المستقبل." }
    }
}
