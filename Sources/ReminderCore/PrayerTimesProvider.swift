import Foundation

public struct PrayerEntry: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var hour: Int? = nil
    public var minute = 0
    public var adjustment = 0
    public var enabled = false
    public var revision = 0
    public var isValid: Bool {
        Self.names.contains(name) && (hour == nil || (0...23).contains(hour!)) &&
        (0...59).contains(minute) && (-120...120).contains(adjustment) && revision >= 0
    }
    public static let names = ["الفجر", "الشروق", "الظهر", "العصر", "المغرب", "العشاء"]
    public static var defaults: [PrayerEntry] {
        names.enumerated().map { index, name in
            PrayerEntry(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!, name: name)
        }
    }
}
public protocol PrayerTimesProvider {
    var sourceDescription: String { get }
    func reminders(entries: [PrayerEntry], settings: AppSettings) -> [Reminder]
}
public struct ManualPrayerTimesProvider: PrayerTimesProvider {
    public init() {}
    public let sourceDescription = "مواقيت يدوية — طرابلس، ليبيا. أدخل أوقاتًا موثوقة وحدّثها مع تغيّر الأيام؛ هذه ليست مواقيت محسوبة."
    public func reminders(entries: [PrayerEntry], settings: AppSettings) -> [Reminder] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Africa/Tripoli")!
        return entries.compactMap { entry in
            guard entry.enabled, let hour = entry.hour, entry.isValid,
                  let base = cal.date(from: DateComponents(year: 2020, month: 1, day: 1, hour: hour, minute: entry.minute)),
                  let adjusted = cal.date(byAdding: .minute, value: entry.adjustment, to: base) else { return nil }
            var reminder = Reminder(title: entry.name == "الشروق" ? "موعد الشروق" : "صلاة \(entry.name)", date: adjusted)
            reminder.id = entry.id; reminder.revision = entry.revision
            reminder.type = .prayer; reminder.detail = "خذ استراحة من العمل"
            reminder.repeatRule = .daily; reminder.timeZoneID = "Africa/Tripoli"
            reminder.preAlertMinutes = settings.defaultPreAlert
            return reminder
        }
    }
}

/// Reserved integration boundary. No EventKit access or permissions in version 0.1.
public protocol MeetingProvider {
    func meetings(from: Date, through: Date) async throws -> [Reminder]
}
