import XCTest
@testable import ReminderCore

final class LibraryTests: XCTestCase {
    func testCompleteAttributedLibraryLoadsOffline() throws {
        let library = SpiritualLibrary.shared
        XCTAssertNil(library.loadError)
        XCTAssertEqual(library.entries.count, 6545)
        XCTAssertEqual(library.search("", category: .quran).count, 6236)
        XCTAssertEqual(library.surahs.count, 114)
        XCTAssertEqual(library.search("", category: .hadith).count, 42)
        XCTAssertEqual(library.entries.filter { $0.id.hasPrefix("hisn-") }.count, 267)
        XCTAssertEqual(Set(library.entries.map(\.id)).count, library.entries.count)
        for item in library.entries {
            XCTAssertFalse(item.text.isEmpty)
            XCTAssertTrue(item.sourceURL.hasPrefix("https://"))
            XCTAssertFalse(item.reference.isEmpty)
        }
    }
    func testQuranTextIsVerbatimAndSurahsAreComplete() throws {
        let raw = try String(contentsOf: XCTUnwrap(AppResources.url("quran-tanzil", "txt")), encoding: .utf8)
        let library = SpiritualLibrary.shared
        for line in raw.components(separatedBy: .newlines) {
            let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, Int(parts[0]) != nil else { continue }
            XCTAssertEqual(library.entry("quran-\(parts[0])-\(parts[1])")?.text, String(parts[2]))
        }
        XCTAssertEqual(library.search("", category: .quran, chapter: 1).count, 7)
        XCTAssertEqual(library.search("", category: .quran, chapter: 2).count, 286)
        XCTAssertEqual(library.search("", category: .quran, chapter: 114).count, 6)
    }
    func testArabicSearchIgnoresDiacriticsWithoutChangingDisplay() {
        let library = SpiritualLibrary.shared
        XCTAssertFalse(library.search("الاعمال بالنيات", category: .hadith).isEmpty)
        XCTAssertFalse(library.search("بسم الله الرحمن الرحيم", category: .quran).isEmpty)
        XCTAssertTrue(library.entry("quran-1-1")!.text.contains("ِ"))
    }
    func testSourceAndAudioRemainAttachedToReminder() throws {
        let sample = try XCTUnwrap(SpiritualLibrary.shared.audioSample)
        XCTAssertEqual(sample.reminder.sound, .dhikr)
        XCTAssertTrue(sample.reminder.detail.contains(sample.reference))
        XCTAssertNotNil(AppResources.url("dhikr-sample", "mp3"))
        _ = try sample.reminder.validated()
        XCTAssertNotNil(AppResources.url("TheYearofHandicrafts-Regular", "otf"))
    }
    func testNewContentKindsRoundTripWithoutChangingDataSchema() throws {
        var data = AppData()
        for type in [ReminderType.dua, .quran, .hadith, .tasbih, .dhikr, .prayer, .custom] {
            var reminder = Reminder(title: type.title, date: Date().addingTimeInterval(120))
            reminder.type = type; reminder.sound = .dhikr; data.upsert(reminder)
        }
        let restored = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(restored, data)
        XCTAssertEqual(restored.schemaVersion, 1)
    }
}
