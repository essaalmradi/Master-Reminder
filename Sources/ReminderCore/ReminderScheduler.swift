import Foundation

public enum DueDecision: Equatable { case future, fire, missed, duplicate, paused }
public enum NotificationKind: String { case pre, due }
public struct PlannedNotification: Identifiable, Equatable {
    public var occurrence: Occurrence
    public var kind: NotificationKind
    public var date: Date
    public var id: String { "mr-\(occurrence.id)-\(kind.rawValue)" }
}

/// Pure calendar logic, independently testable without AppKit or notification permissions.
public enum ReminderScheduler {
    public static func calendar(for reminder: Reminder, base: Calendar) -> Calendar {
        var value = base
        if let id = reminder.timeZoneID, let zone = TimeZone(identifier: id) { value.timeZone = zone }
        return value
    }

    public static func occurrences(for reminder: Reminder, from start: Date, through end: Date,
                                   calendar base: Calendar = .current) -> [Occurrence] {
        guard reminder.enabled, start <= end else { return [] }
        if reminder.repeatRule == .once {
            return (start...end).contains(reminder.date) ? [Occurrence(reminder: reminder, date: reminder.date)] : []
        }
        let cal = calendar(for: reminder, base: base)
        let components = cal.dateComponents([.hour, .minute, .second], from: reminder.date)
        let firstWeekday = cal.component(.weekday, from: reminder.date)
        var day = cal.startOfDay(for: max(start, reminder.date))
        var result: [Occurrence] = []
        // Bound work even for malformed or excessively broad date ranges.
        for _ in 0..<370 {
            if day > end { break }
            let weekday = cal.component(.weekday, from: day)
            let matches = reminder.repeatRule == .daily ||
                (reminder.repeatRule == .weekly && weekday == firstWeekday) ||
                (reminder.repeatRule == .weekdays && reminder.weekdays.contains(weekday))
            if matches, let date = cal.date(bySettingHour: components.hour ?? 0,
                                            minute: components.minute ?? 0, second: components.second ?? 0,
                                            of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first),
               date >= reminder.date, date >= start, date <= end {
                result.append(Occurrence(reminder: reminder, date: date))
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return result
    }

    public static func decision(_ occurrence: Occurrence, now: Date, settings: AppSettings,
                                ledger: [String: EventRecord]) -> DueDecision {
        if ledger[occurrence.id] != nil { return .duplicate }
        if occurrence.date > now { return .future }
        if let boundary = settings.suppressedThrough, occurrence.date <= boundary { return .paused }
        if settings.isPaused(at: now) { return .paused }
        if now.timeIntervalSince(occurrence.date) > TimeInterval(settings.graceMinutes * 60) { return .missed }
        return .fire
    }

    public static func upcoming(reminders: [Reminder], snoozes: [SnoozeEvent], now: Date,
                                days: Int = 7, ledger: [String: EventRecord] = [:],
                                calendar: Calendar = .current) -> [Occurrence] {
        let end = calendar.date(byAdding: .day, value: days, to: now) ?? now.addingTimeInterval(604800)
        return (reminders.flatMap { occurrences(for: $0, from: now, through: end, calendar: calendar) }
                + snoozes.filter { $0.date >= now && $0.date <= end }.map(\.occurrence))
            .filter { ledger[$0.id] == nil }
            .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }

    public static func notificationPlan(occurrences: [Occurrence], now: Date, settings: AppSettings,
                                        limit: Int = 60) -> [PlannedNotification] {
        var items: [String: PlannedNotification] = [:]
        for occurrence in occurrences {
            let due = PlannedNotification(occurrence: occurrence, kind: .due, date: occurrence.date)
            if due.date > now, due.date >= (settings.pausedUntil ?? .distantPast) { items[due.id] = due }
            if occurrence.reminder.preAlertMinutes > 0 && !occurrence.isSnooze {
                let pre = PlannedNotification(occurrence: occurrence, kind: .pre,
                    date: occurrence.date.addingTimeInterval(TimeInterval(-occurrence.reminder.preAlertMinutes * 60)))
                if pre.date > now, pre.date >= (settings.pausedUntil ?? .distantPast) { items[pre.id] = pre }
            }
        }
        return Array(items.values.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }.prefix(max(0, limit)))
    }
}
