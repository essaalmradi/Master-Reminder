import XCTest
@testable import ReminderCore

class ClockTestCase: XCTestCase {
    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!; return cal
    }
    func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }
    var noon: Date { date("2026-10-15T12:00:00Z") }
    func reminder(at time: Date? = nil) -> Reminder { Reminder(title: "اجتماع", date: time ?? noon) }
}

final class ReminderSchedulerTests: ClockTestCase {
    func testPreAlertCalculation() {
        let item = reminder(); let occurrence = Occurrence(reminder: item, date: item.date)
        let plan = ReminderScheduler.notificationPlan(occurrences: [occurrence], now: noon.addingTimeInterval(-600), settings: AppSettings())
        XCTAssertEqual(plan.first?.kind, .pre); XCTAssertEqual(plan.first?.date, noon.addingTimeInterval(-300))
    }
    func testDueCalculation() {
        let item = reminder()
        XCTAssertEqual(ReminderScheduler.occurrences(for: item, from: noon.addingTimeInterval(-1), through: noon, calendar: calendar).first?.date, noon)
    }
    func testFuture() {
        XCTAssertEqual(ReminderScheduler.decision(Occurrence(reminder: reminder(), date: noon), now: noon.addingTimeInterval(-1), settings: AppSettings(), ledger: [:]), .future)
    }
    func testWakeWithinGrace() {
        XCTAssertEqual(ReminderScheduler.decision(Occurrence(reminder: reminder(), date: noon), now: noon.addingTimeInterval(240), settings: AppSettings(), ledger: [:]), .fire)
    }
    func testGraceBoundaryIncluded() {
        XCTAssertEqual(ReminderScheduler.decision(Occurrence(reminder: reminder(), date: noon), now: noon.addingTimeInterval(900), settings: AppSettings(), ledger: [:]), .fire)
    }
    func testMissedReminder() {
        XCTAssertEqual(ReminderScheduler.decision(Occurrence(reminder: reminder(), date: noon), now: noon.addingTimeInterval(901), settings: AppSettings(), ledger: [:]), .missed)
    }
    func testWakeHoursLaterIsMissed() {
        XCTAssertEqual(ReminderScheduler.decision(Occurrence(reminder: reminder(), date: noon), now: noon.addingTimeInterval(10800), settings: AppSettings(), ledger: [:]), .missed)
    }
    func testDailyRecurring() {
        var item = reminder(); item.repeatRule = .daily
        let values = ReminderScheduler.occurrences(for: item, from: noon, through: noon.addingTimeInterval(2 * 86400), calendar: calendar)
        XCTAssertEqual(values.count, 3); XCTAssertEqual(values[2].date, noon.addingTimeInterval(2 * 86400))
    }
    func testWeeklyRecurring() {
        var item = reminder(); item.repeatRule = .weekly
        let values = ReminderScheduler.occurrences(for: item, from: noon, through: noon.addingTimeInterval(8 * 86400), calendar: calendar)
        XCTAssertEqual(values.map(\.date), [noon, noon.addingTimeInterval(7 * 86400)])
    }
    func testSelectedWeekdays() {
        var item = reminder(); item.repeatRule = .weekdays; item.weekdays = [6] // Friday
        let values = ReminderScheduler.occurrences(for: item, from: noon, through: noon.addingTimeInterval(7 * 86400), calendar: calendar)
        XCTAssertEqual(values.count, 1); XCTAssertEqual(calendar.component(.weekday, from: values[0].date), 6)
    }
    func testDoesNotFireBeforeStartDate() {
        var item = reminder(); item.repeatRule = .daily
        XCTAssertTrue(ReminderScheduler.occurrences(for: item, from: noon.addingTimeInterval(-86400), through: noon.addingTimeInterval(-1), calendar: calendar).isEmpty)
    }
    func testDisabledReminder() {
        var item = reminder(); item.enabled = false
        XCTAssertTrue(ReminderScheduler.occurrences(for: item, from: noon, through: noon, calendar: calendar).isEmpty)
    }
    func testNoLatePreAlert() {
        let item = reminder()
        let values = ReminderScheduler.notificationPlan(occurrences: [Occurrence(reminder: item, date: noon)], now: noon.addingTimeInterval(-60), settings: AppSettings())
        XCTAssertEqual(values.count, 1); XCTAssertEqual(values[0].kind, .due)
    }
    func testSnoozeDoesNotChangeOriginal() {
        let item = reminder(); var data = AppData(); data.reminders = [item]
        let occurrence = Occurrence(reminder: item, date: noon)
        let result = data.snooze(occurrence, now: noon, minutes: 5)
        XCTAssertEqual(result?.date, noon.addingTimeInterval(300)); XCTAssertEqual(data.reminders[0].date, noon)
        XCTAssertTrue(result!.occurrence.isSnooze)
        XCTAssertEqual(data.ledger[occurrence.id]?.status, .snoozed)
    }
    func testSnoozeHasNoPreAlert() {
        let item = reminder(); let snooze = SnoozeEvent(occurrence: Occurrence(reminder: item, date: noon), now: noon, minutes: 10)
        let values = ReminderScheduler.notificationPlan(occurrences: [snooze.occurrence], now: noon, settings: AppSettings())
        XCTAssertEqual(values.map(\.kind), [.due])
    }
    func testSnoozeDisabled() {
        var item = reminder(); item.snoozeAllowed = false; var data = AppData()
        XCTAssertNil(data.snooze(Occurrence(reminder: item, date: noon), now: noon, minutes: 5))
    }
    func testPauseDropsCurrentAlertsButSchedulesAfterResume() {
        var settings = AppSettings(); settings.pausedUntil = noon.addingTimeInterval(3600)
        let occurrence = Occurrence(reminder: reminder(), date: noon)
        XCTAssertEqual(ReminderScheduler.decision(occurrence, now: noon, settings: settings, ledger: [:]), .paused)
        let future = Occurrence(reminder: reminder(), date: noon.addingTimeInterval(7200))
        let values = ReminderScheduler.notificationPlan(occurrences: [occurrence, future], now: noon.addingTimeInterval(-1), settings: settings)
        XCTAssertEqual(values.count, 2); XCTAssertTrue(values.allSatisfy { $0.date > settings.pausedUntil! })
    }
    func testResumeDoesNotReplayPausedOccurrence() {
        var settings = AppSettings(); settings.suppressedThrough = noon.addingTimeInterval(60)
        XCTAssertEqual(ReminderScheduler.decision(Occurrence(reminder: reminder(), date: noon), now: noon.addingTimeInterval(120), settings: settings, ledger: [:]), .paused)
    }
    func testDSTKeepsLocalHourAndSingleOccurrence() {
        var cal = calendar; cal.timeZone = TimeZone(identifier: "America/New_York")!
        var item = reminder(at: date("2026-10-31T05:30:00Z")); item.repeatRule = .daily
        let values = ReminderScheduler.occurrences(for: item, from: item.date, through: date("2026-11-02T12:00:00Z"), calendar: cal)
        XCTAssertEqual(values.count, 3); XCTAssertTrue(values.allSatisfy { cal.component(.hour, from: $0.date) == 1 })
    }
    func testSpringDSTMissingTimeMovesForward() {
        var cal = calendar; cal.timeZone = TimeZone(identifier: "America/New_York")!
        var item = reminder(at: date("2026-03-07T07:30:00Z")); item.repeatRule = .daily
        let values = ReminderScheduler.occurrences(for: item, from: item.date, through: date("2026-03-09T12:00:00Z"), calendar: cal)
        XCTAssertEqual(values.count, 3); XCTAssertEqual(Set(values.map(\.id)).count, 3)
    }
    func testTemporaryTenSecondHelper() {
        var item = reminder(at: noon.addingTimeInterval(10)); item.isTemporary = true; item.preAlertMinutes = 0
        XCTAssertEqual(ReminderScheduler.notificationPlan(occurrences: [Occurrence(reminder: item, date: item.date)], now: noon, settings: AppSettings()).first?.date, noon.addingTimeInterval(10))
    }
}

final class DeduplicationTests: ClockTestCase {
    func testDuplicateNotificationPrevention() {
        let occurrence = Occurrence(reminder: reminder(), date: noon)
        let values = ReminderScheduler.notificationPlan(occurrences: [occurrence, occurrence], now: noon.addingTimeInterval(-600), settings: AppSettings())
        XCTAssertEqual(values.count, 2); XCTAssertEqual(Set(values.map(\.id)).count, 2)
    }
    func testStableIDsAcrossReconcile() {
        let item = reminder(); let occurrence = Occurrence(reminder: item, date: noon)
        let a = ReminderScheduler.notificationPlan(occurrences: [occurrence], now: noon.addingTimeInterval(-600), settings: AppSettings())
        let b = ReminderScheduler.notificationPlan(occurrences: [occurrence], now: noon.addingTimeInterval(-500), settings: AppSettings())
        XCTAssertEqual(a.map(\.id), b.map(\.id))
    }
    func testPersistentClaimPreventsOverlayAfterRestart() {
        let occurrence = Occurrence(reminder: reminder(), date: noon)
        XCTAssertEqual(ReminderScheduler.decision(occurrence, now: noon, settings: AppSettings(), ledger: [occurrence.id: EventRecord(.fired, at: noon)]), .duplicate)
    }
    func testEditRescheduleInvalidatesOldIDsAndSnoozes() {
        var item = reminder(); var data = AppData(); data.upsert(item)
        let old = Occurrence(reminder: item, date: noon)
        data.snooze(old, now: noon, minutes: 5)
        item.date = noon.addingTimeInterval(3600); data.upsert(item)
        let updated = data.reminders[0]
        XCTAssertEqual(updated.id, item.id); XCTAssertEqual(updated.revision, 1)
        XCTAssertNotEqual(old.id, Occurrence(reminder: updated, date: updated.date).id)
        XCTAssertTrue(data.snoozes.isEmpty)
    }
    func testDeleteCleanup() {
        let item = reminder(); var data = AppData(); data.upsert(item)
        data.snooze(Occurrence(reminder: item, date: noon), now: noon, minutes: 5)
        data.delete(item.id)
        XCTAssertTrue(data.reminders.isEmpty); XCTAssertTrue(data.snoozes.isEmpty); XCTAssertTrue(data.ledger.isEmpty)
        XCTAssertTrue(ReminderScheduler.notificationPlan(occurrences: [], now: noon, settings: data.settings).isEmpty)
    }
    func testDoubleSnoozeIsOneEvent() {
        var data = AppData(); let occurrence = Occurrence(reminder: reminder(), date: noon)
        XCTAssertNotNil(data.snooze(occurrence, now: noon, minutes: 5))
        XCTAssertNil(data.snooze(occurrence, now: noon.addingTimeInterval(1), minutes: 5))
        XCTAssertEqual(data.snoozes.count, 1)
    }
    func testNotificationQueueIsBounded() {
        let items = (1...100).map { Occurrence(reminder: reminder(), date: noon.addingTimeInterval(Double($0 * 600))) }
        XCTAssertEqual(ReminderScheduler.notificationPlan(occurrences: items, now: noon, settings: AppSettings()).count, 60)
    }
}

final class SortingTests: ClockTestCase {
    func testUpcomingOrderedCorrectlyWithSnoozes() {
        let first = reminder(at: noon.addingTimeInterval(600)); let last = reminder(at: noon.addingTimeInterval(3600))
        let snooze = SnoozeEvent(occurrence: Occurrence(reminder: reminder(), date: noon), now: noon, minutes: 15)
        let values = ReminderScheduler.upcoming(reminders: [last, first], snoozes: [snooze], now: noon, calendar: calendar)
        XCTAssertEqual(values.map(\.date), [first.date, snooze.date, last.date])
    }
    func testConsumedOccurrencesExcluded() {
        let item = reminder(); let occurrence = Occurrence(reminder: item, date: noon)
        XCTAssertTrue(ReminderScheduler.upcoming(reminders: [item], snoozes: [], now: noon, ledger: [occurrence.id: EventRecord(.dismissed, at: noon)], calendar: calendar).isEmpty)
    }
}
