import XCTest
@testable import ReminderCore

final class StorageTests: XCTestCase {
    var directory: URL!
    var storage: StorageManager!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        storage = StorageManager(url: directory.appendingPathComponent("data.json"))
    }
    override func tearDownWithError() throws { if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) } }
    func sample() -> Reminder { Reminder(title: "صلاة العصر", date: Date(timeIntervalSince1970: 1_800_000_000)) }
    func testMissingFileReturnsDefaults() throws { XCTAssertEqual(try storage.load(), AppData()) }
    func testSaveAndLoadArabic() throws {
        var data = AppData(); data.upsert(sample()); try storage.save(data)
        XCTAssertEqual(try storage.load(), data)
    }
    func testUpdate() throws {
        var data = AppData(); var item = sample(); data.upsert(item); try storage.save(data)
        item.title = "الاجتماع"; data.upsert(item); try storage.save(data)
        XCTAssertEqual(try storage.load().reminders[0].title, "الاجتماع"); XCTAssertEqual(try storage.load().reminders.count, 1)
    }
    func testDelete() throws {
        var data = AppData(); let item = sample(); data.upsert(item); try storage.save(data)
        data.delete(item.id); try storage.save(data); XCTAssertTrue(try storage.load().reminders.isEmpty)
    }
    func testPersistenceAcrossNewStorageInstance() throws {
        var data = AppData(); data.upsert(sample()); try storage.save(data)
        XCTAssertEqual(try StorageManager(url: storage.url).load(), data)
    }
    func testSnoozeAndLedgerSurviveRestart() throws {
        let item = sample(); var data = AppData(); data.upsert(item)
        let occurrence = Occurrence(reminder: item, date: item.date)
        data.snooze(occurrence, now: item.date, minutes: 10); try storage.save(data)
        var restored = try storage.load()
        XCTAssertEqual(restored.snoozes.count, 1); XCTAssertNil(restored.snooze(occurrence, now: item.date, minutes: 10))
    }
    func testTemporaryReminderNotPersisted() throws {
        var item = sample(); item.isTemporary = true; var data = AppData(); data.reminders = [item]
        data.snooze(Occurrence(reminder: item, date: item.date), now: item.date, minutes: 5)
        try storage.save(data); XCTAssertTrue(try storage.load().reminders.isEmpty); XCTAssertTrue(try storage.load().snoozes.isEmpty)
    }
    func testInvalidFileDoesNotOverwriteExistingData() throws {
        var data = AppData(); data.upsert(sample()); try storage.save(data)
        XCTAssertThrowsError(try storage.decode(Data("bad json".utf8)))
        XCTAssertEqual(try storage.load(), data)
    }
    func testRejectsDuplicateReminderIDs() throws {
        var data = AppData(); let item = sample(); data.reminders = [item, item]
        XCTAssertThrowsError(try storage.save(data))
    }
    func testRejectsPathTraversalInCustomSound() {
        var item = sample(); item.customSoundFile = "../../secret"
        XCTAssertThrowsError(try item.validated())
    }
    func testRejectsUnsupportedSchema() {
        var data = AppData(); data.schemaVersion = 99; XCTAssertThrowsError(try storage.save(data))
    }
}

final class SettingsTests: XCTestCase {
    func testDefaultGracePeriod() { XCTAssertEqual(AppSettings().graceMinutes, 15) }
    func testDefaultSnooze() { XCTAssertEqual(AppSettings().defaultSnooze, 5) }
    func testInvalidValuesNormalize() {
        var settings = AppSettings(); settings.graceMinutes = -1; settings.defaultSnooze = 7; settings.volume = 9; settings.overlayOpacity = 0.1
        settings.normalize()
        XCTAssertEqual(settings.graceMinutes, 1); XCTAssertEqual(settings.defaultSnooze, 5)
        XCTAssertEqual(settings.volume, 1); XCTAssertEqual(settings.overlayOpacity, 0.75)
    }
    func testPauseExpires() {
        var settings = AppSettings(); let now = Date(); settings.pausedUntil = now
        XCTAssertFalse(settings.isPaused(at: now)); XCTAssertTrue(settings.isPaused(at: now.addingTimeInterval(-1)))
    }
}

final class PrayerTests: XCTestCase {
    func testNoUnverifiedDefaultTimes() {
        XCTAssertTrue(ManualPrayerTimesProvider().reminders(entries: PrayerEntry.defaults, settings: AppSettings()).isEmpty)
    }
    func testManualAdjustmentAndTimeZone() {
        var entries = PrayerEntry.defaults; entries[3].hour = 15; entries[3].minute = 30; entries[3].adjustment = -1; entries[3].enabled = true
        let reminder = ManualPrayerTimesProvider().reminders(entries: entries, settings: AppSettings())[0]
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Africa/Tripoli")!
        XCTAssertEqual(cal.component(.hour, from: reminder.date), 15); XCTAssertEqual(cal.component(.minute, from: reminder.date), 29)
        XCTAssertEqual(reminder.repeatRule, .daily); XCTAssertEqual(reminder.timeZoneID, "Africa/Tripoli")
    }
    func testPrayerIdentityStableAcrossRestarts() {
        XCTAssertEqual(PrayerEntry.defaults.map(\.id), PrayerEntry.defaults.map(\.id))
    }
}
