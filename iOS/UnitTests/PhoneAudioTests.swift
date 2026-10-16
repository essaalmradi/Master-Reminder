import XCTest
import AVFoundation
import UserNotifications
import ReminderCore
@testable import MasterReminderPhone

@MainActor final class PhoneAudioTests: XCTestCase {
    private var directory: URL!
    private var audio: PhoneAudio!
    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        audio = PhoneAudio(root: directory)
    }
    override func tearDown() async throws { audio.stop(); try? FileManager.default.removeItem(at: directory) }
    func testBundledSoundConvertsAndPersistsWithDifferentVolume() async throws {
        var reminder = Reminder(title: "تجربة", date: Date().addingTimeInterval(120)); reminder.sound = .dhikr
        let prepared = try await audio.prepareAlarm(reminder)
        let name = try XCTUnwrap(prepared)
        let player = try AVAudioPlayer(contentsOf: audio.soundsDirectory.appendingPathComponent(name))
        XCTAssertGreaterThan(player.duration, 1); XCTAssertLessThanOrEqual(player.duration, 29.01)
        let again = try await audio.prepareAlarm(reminder); XCTAssertEqual(name, again)
        var selection = ReminderAudio(); selection.volume = 0.25; reminder.audio = selection
        let quieter = try await audio.prepareAlarm(reminder); XCTAssertNotEqual(name, quieter)
        reminder.sound = .none; let silent = try await audio.prepareAlarm(reminder); XCTAssertNil(silent)
    }
    func testRealRecordingsConvertWithoutReplacingSelectedVoice() async throws {
        var prayer = Reminder(title: "صلاة", date: Date().addingTimeInterval(120)); prayer.type = .prayer; prayer.sound = .adhan
        var selection = ReminderAudio(); selection.recordingID = "alafasy"; prayer.audio = selection
        let verse = PhoneModel.libraryReminder(try XCTUnwrap(SpiritualLibrary.shared.entry("quran-1-1")))
        let dhikr = PhoneModel.libraryReminder(try XCTUnwrap(SpiritualLibrary.shared.entries.first { $0.audioURL != nil && $0.bundledAudio == nil }))
        var names = Set<String>()
        for reminder in [prayer, verse, dhikr] {
            let prepared = try await audio.prepareAlarm(reminder)
        let name = try XCTUnwrap(prepared); names.insert(name)
            let file = try AVAudioFile(forReading: audio.soundsDirectory.appendingPathComponent(name))
            XCTAssertGreaterThan(file.length, 0)
            XCTAssertLessThanOrEqual(Double(file.length) / file.processingFormat.sampleRate, 29.01)
            let restarted = PhoneAudio(root: directory)
            let cached = try await restarted.prepareAlarm(reminder); XCTAssertEqual(name, cached)
        }
        XCTAssertEqual(names.count, 3)
    }
    func testImportRemainsUsableAfterOriginalIsRemoved() async throws {
        let original = directory.appendingPathComponent("selected.mp3")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: XCTUnwrap(AppResources.url("dhikr-sample", "mp3")), to: original)
        var reminder = Reminder(title: "ملفي", date: Date().addingTimeInterval(120)); reminder.sound = .custom
        reminder.customSoundFile = try audio.importFile(original)
        try FileManager.default.removeItem(at: original)
        let name = try await audio.prepareAlarm(reminder); XCTAssertNotNil(name)
    }
    func testMissingSelectionAndCorruptFileAreRejected() async throws {
        var reminder = Reminder(title: "اختبار", date: Date().addingTimeInterval(120)); reminder.sound = .quran
        do { _ = try await audio.prepareAlarm(reminder); XCTFail("Missing verse accepted") } catch { }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bad = directory.appendingPathComponent("bad.mp3"); try Data("not audio".utf8).write(to: bad)
        XCTAssertThrowsError(try audio.importFile(bad))
    }
    func testArabicSpeechIsRenderedToAnOfflineAlert() async throws {
        guard !audio.arabicVoices.isEmpty else { throw XCTSkip("Runner has no Arabic voice; verify on physical phone") }
        var reminder = Reminder(title: "سبحان الله وبحمده", date: Date().addingTimeInterval(120)); reminder.sound = .speech
        let name = try await audio.prepareAlarm(reminder); XCTAssertNotNil(name)
    }
    func testSilentWeekdayRequestsDoNotContainASound() {
        var reminder = Reminder(title: "بدون صوت", date: Date().addingTimeInterval(120)); reminder.sound = .none
        reminder.repeatRule = .weekdays; reminder.weekdays = [1, 3, 5]
        let requests = PhoneNotifications.requests(for: reminder)
        XCTAssertEqual(requests.count, 3); XCTAssertEqual(Set(requests.map(\.identifier)).count, 3)
        for request in requests {
            XCTAssertNil(request.content.sound)
            let trigger = request.trigger as! UNCalendarNotificationTrigger
            XCTAssertTrue(trigger.repeats); XCTAssertTrue(reminder.weekdays.contains(trigger.dateComponents.weekday!))
        }
        reminder.repeatRule = .once
        let once = PhoneNotifications.requests(for: reminder)
        XCTAssertEqual(once.count, 1); XCTAssertFalse(once[0].trigger!.repeats)
    }
    func testLibraryPreservesRecordingCategory() throws {
        let verse = PhoneModel.libraryReminder(try XCTUnwrap(SpiritualLibrary.shared.entry("quran-1-1")))
        XCTAssertEqual(verse.sound, .quran); XCTAssertEqual(verse.audio?.reciterID, "alafasy")
        let entry = try XCTUnwrap(SpiritualLibrary.shared.entries.first { $0.audioURL != nil })
        XCTAssertEqual(PhoneModel.libraryReminder(entry).sound, .library)
    }
}
