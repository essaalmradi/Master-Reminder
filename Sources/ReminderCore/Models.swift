import Foundation

public enum ReminderType: String, Codable, CaseIterable, Identifiable {
    case prayer, meeting, dhikr, breakTime, task, custom, dua, quran, hadith, tasbih
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .prayer: return "صلاة"
        case .meeting: return "اجتماع"
        case .dhikr: return "ذكر"
        case .breakTime: return "استراحة"
        case .task: return "مهمة"
        case .custom: return "مخصص"
        case .dua: return "أدعية"
        case .quran: return "قرآن"
        case .hadith: return "أحاديث"
        case .tasbih: return "تسبيح"
        }
    }
    public var symbol: String {
        switch self {
        case .prayer: return "moon.stars"
        case .meeting: return "person.2"
        case .dhikr: return "sparkle"
        case .breakTime: return "cup.and.saucer"
        case .task: return "checkmark.circle"
        case .custom: return "bell"
        case .dua: return "hands.sparkles"
        case .quran: return "book.closed"
        case .hadith: return "text.book.closed"
        case .tasbih: return "circle.dotted"
        }
    }
}

public enum RepeatRule: String, Codable, CaseIterable, Identifiable {
    case once, daily, weekdays, weekly
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .once: return "مرة واحدة"
        case .daily: return "يوميًا"
        case .weekdays: return "أيام محددة"
        case .weekly: return "أسبوعيًا"
        }
    }
}

public enum SoundChoice: String, Codable, CaseIterable, Identifiable {
    case none, `default`, bell, soft, custom, dhikr, adhan, quran, library, speech
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .none: return "بدون صوت"
        case .default: return "افتراضي"
        case .bell: return "جرس"
        case .soft: return "هادئ"
        case .custom: return "ملف مخصص"
        case .dhikr: return "ذكر مسجّل · سبحان الله وبحمده"
        case .adhan: return "أذان · اختر المؤذّن"
        case .quran: return "تلاوة · اختر القارئ"
        case .library: return "تسجيل الذكر أو الدعاء"
        case .speech: return "قراءة النص بصوت عربي"
        }
    }
}

public struct Reminder: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var revision = 0
    public var title: String
    public var detail = ""
    public var type: ReminderType = .custom
    public var date: Date
    public var repeatRule: RepeatRule = .once
    /// Foundation weekday numbers: Sunday = 1.
    public var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    public var preAlertMinutes = 5
    public var sound: SoundChoice = .default
    public var customSoundFile: String? = nil
    /// Optional so profiles created before selectable voices decode unchanged.
    public var audio: ReminderAudio? = nil
    public var overlay = true
    /// Zero means until dismissed. A visible Escape button always remains available.
    public var overlayDuration = 0
    public var snoozeAllowed = true
    public var enabled = true
    /// nil follows the Mac's local time zone; manual prayers use Africa/Tripoli.
    public var timeZoneID: String? = nil
    public var isTemporary = false
    public init(title: String, date: Date) { self.title = title; self.date = date }

    public func validated() throws -> Reminder {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 200, detail.count <= 4000, date.timeIntervalSince1970.isFinite,
              revision >= 0, (0...1440).contains(preAlertMinutes),
              (0...3600).contains(overlayDuration),
              weekdays.allSatisfy({ (1...7).contains($0) }),
              repeatRule != .weekdays || !weekdays.isEmpty,
              timeZoneID == nil || TimeZone(identifier: timeZoneID!) != nil,
              customSoundFile == nil || (customSoundFile! == URL(fileURLWithPath: customSoundFile!).lastPathComponent && !customSoundFile!.contains("..")),
              audio?.isValid ?? true
        else { throw DataError.invalidData }
        return self
    }
}

public enum Appearance: String, Codable, CaseIterable { case system, light, dark }

public struct AppSettings: Codable, Equatable {
    public var appearance: Appearance = .system
    public var overlayEnabled = true
    public var allScreens = true
    public var overlayOpacity = 0.88
    public var soundEnabled = true
    public var volume = 0.6
    public var defaultPreAlert = 5
    public var defaultSnooze = 5
    public var graceMinutes = 15
    public var pausedUntil: Date? = nil
    public var suppressedThrough: Date? = nil
    public var onboardingComplete = false
    public init() {}
    public func isPaused(at date: Date) -> Bool { (pausedUntil ?? .distantPast) > date }
    public mutating func normalize() {
        overlayOpacity = overlayOpacity.isFinite ? min(0.95, max(0.75, overlayOpacity)) : 0.88
        volume = volume.isFinite ? min(1, max(0, volume)) : 0.6
        defaultPreAlert = min(1440, max(0, defaultPreAlert))
        defaultSnooze = [5, 10, 15].contains(defaultSnooze) ? defaultSnooze : 5
        graceMinutes = min(240, max(1, graceMinutes))
    }
}

public struct Occurrence: Identifiable, Equatable {
    public var id: String
    public var reminder: Reminder
    public var date: Date
    public var isSnooze = false
    public init(reminder: Reminder, date: Date, id: String? = nil, isSnooze: Bool = false) {
        self.reminder = reminder; self.date = date; self.isSnooze = isSnooze
        self.id = id ?? "\(reminder.id.uuidString)-r\(reminder.revision)-\(Int(date.timeIntervalSince1970))"
    }
}

public enum EventStatus: String, Codable { case fired, dismissed, snoozed, missed, paused }
public struct EventRecord: Codable, Equatable {
    public var status: EventStatus
    public var date: Date
    public init(_ status: EventStatus, at date: Date) { self.status = status; self.date = date }
}
public struct SnoozeEvent: Codable, Identifiable, Equatable {
    public var id: String
    public var parentID: String
    public var reminder: Reminder
    public var date: Date
    public init(occurrence: Occurrence, now: Date, minutes: Int) {
        parentID = occurrence.id
        id = "\(occurrence.id)-snooze-\(Int(now.timeIntervalSince1970 * 1000))"
        reminder = occurrence.reminder
        date = now.addingTimeInterval(TimeInterval(minutes * 60))
    }
    public var occurrence: Occurrence { Occurrence(reminder: reminder, date: date, id: id, isSnooze: true) }
}

public struct AppData: Codable, Equatable {
    public var schemaVersion = 1
    public var reminders: [Reminder] = []
    public var settings = AppSettings()
    public var ledger: [String: EventRecord] = [:]
    public var snoozes: [SnoozeEvent] = []
    public var prayers = PrayerEntry.defaults
    public var lastReconciled: Date? = nil
    public init() {}
    public mutating func validate() throws {
        guard schemaVersion == 1, reminders.count <= 5000, snoozes.count <= 5000,
              Set(reminders.map(\.id)).count == reminders.count,
              Set(snoozes.map(\.id)).count == snoozes.count,
              Set(prayers.map(\.name)).count == prayers.count,
              prayers.allSatisfy({ $0.isValid }) else { throw DataError.invalidData }
        for reminder in reminders { _ = try reminder.validated() }
        for snooze in snoozes { _ = try snooze.reminder.validated() }
        settings.normalize()
    }
    public mutating func upsert(_ reminder: Reminder) {
        var revised = reminder
        if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
            revised.revision = reminders[index].revision + 1
            reminders[index] = revised
        } else { reminders.append(revised) }
        snoozes.removeAll { $0.reminder.id == reminder.id }
    }
    public mutating func delete(_ id: UUID) {
        reminders.removeAll { $0.id == id }
        snoozes.removeAll { $0.reminder.id == id }
        ledger = ledger.filter { !$0.key.hasPrefix(id.uuidString + "-") }
    }
    /// Returns nil for repeated button presses, even across restart.
    @discardableResult public mutating func snooze(_ occurrence: Occurrence, now: Date, minutes: Int) -> SnoozeEvent? {
        guard occurrence.reminder.snoozeAllowed, [5, 10, 15].contains(minutes),
              ledger[occurrence.id]?.status != .snoozed,
              ledger[occurrence.id]?.status != .dismissed,
              !snoozes.contains(where: { $0.parentID == occurrence.id }) else { return nil }
        let event = SnoozeEvent(occurrence: occurrence, now: now, minutes: minutes)
        ledger[occurrence.id] = EventRecord(.snoozed, at: now)
        snoozes.append(event)
        return event
    }
}

public enum DataError: LocalizedError {
    case invalidData, fileTooLarge
    public var errorDescription: String? {
        switch self {
        case .invalidData: return "بيانات الملف غير صالحة أو إصدارها غير مدعوم."
        case .fileTooLarge: return "حجم الملف أكبر من الحد المسموح (10 MB)."
        }
    }
}
