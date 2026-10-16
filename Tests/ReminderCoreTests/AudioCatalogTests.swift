import XCTest
@testable import ReminderCore

final class AudioCatalogTests: XCTestCase {
    func testOldProfilesDecodeWithoutAudioKeys() throws {
        var data = AppData(); data.reminders = [Reminder(title: "قديم", date: Date())]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(data)) as? [String: Any])
        var reminders = try XCTUnwrap(json["reminders"] as? [[String: Any]])
        reminders[0].removeValue(forKey: "audio"); json["reminders"] = reminders
        var prayers = try XCTUnwrap(json["prayers"] as? [[String: Any]])
        for i in prayers.indices { for key in ["sound", "audio", "customSoundFile"] { prayers[i].removeValue(forKey: key) } }
        json["prayers"] = prayers
        let restored = try JSONDecoder().decode(AppData.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.reminders[0].audio); XCTAssertEqual(restored.reminders[0].sound, .default)
        XCTAssertTrue(restored.prayers.allSatisfy { $0.audio == nil && $0.sound == nil })
    }
    func testEveryVerseAndReciterResolveToMatchingFile() throws {
        for entry in SpiritualLibrary.shared.entries where entry.category == "quran" {
            let parts = entry.id.split(separator: "-")
            let filename = String(format: "%03d%03d.mp3", Int(parts[1])!, Int(parts[2])!)
            for reciter in AudioCatalog.reciters {
                var value = entry.reminder; value.audio?.reciterID = reciter.id
                let recording = try XCTUnwrap(AudioCatalog.recording(for: value))
                XCTAssertEqual(recording.url.lastPathComponent, filename)
                XCTAssertEqual(recording.url.deletingLastPathComponent().lastPathComponent, reciter.directory)
                XCTAssertEqual(recording.url.host, "everyayah.com")
            }
        }
    }
    func testDhikrKeepsItsOwnRecording() throws {
        for entry in SpiritualLibrary.shared.entries where entry.audioURL != nil {
            let value = entry.reminder
            XCTAssertEqual(value.sound, .library)
            XCTAssertEqual(try AudioCatalog.recording(for: value)?.url.absoluteString, entry.audioURL)
        }
    }
    func testInvalidSelectionsCannotResolveArbitraryAudio() throws {
        var value = try XCTUnwrap(SpiritualLibrary.shared.entry("quran-1-1")).reminder
        value.audio?.libraryEntryID = "quran-1-999"; XCTAssertThrowsError(try AudioCatalog.recording(for: value))
        value.audio?.libraryEntryID = "quran-1-1"; value.audio?.reciterID = "../../foreign"
        XCTAssertThrowsError(try AudioCatalog.recording(for: value))
        value.sound = .adhan; value.audio?.recordingID = "https://example.com/audio.mp3"
        XCTAssertThrowsError(try AudioCatalog.recording(for: value))
    }
    func testPrayerVoiceAndMuteSurviveProvider() throws {
        var entries = PrayerEntry.defaults
        for i in 0...1 { entries[i].enabled = true; entries[i].hour = 12 }
        entries[0].sound = .adhan; entries[0].audio = ReminderAudio(); entries[0].audio?.recordingID = "nafees"
        entries[1].sound = SoundChoice.none
        let values = ManualPrayerTimesProvider().reminders(entries: entries, settings: AppSettings())
        XCTAssertEqual(values[0].sound, .adhan); XCTAssertEqual(values[0].audio, entries[0].audio)
        XCTAssertEqual(try AudioCatalog.recording(for: values[0])?.url.lastPathComponent, "a1.mp3")
        XCTAssertEqual(values[1].sound, .none)
    }
    func testSelectedVoiceSurvivesStorageAndSnooze() throws {
        var value = try XCTUnwrap(SpiritualLibrary.shared.entry("quran-13-28")).reminder
        value.audio?.reciterID = "husary"; value.audio?.volume = 0.4
        var data = AppData(); data.upsert(value)
        data.snooze(Occurrence(reminder: value, date: value.date), now: value.date, minutes: 5)
        let restored = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(restored.reminders[0].audio, value.audio)
        XCTAssertEqual(restored.snoozes[0].reminder.audio, value.audio)
        XCTAssertEqual(restored.snoozes[0].reminder.sound, .quran)
    }
    func testInvalidVolumeAndSpeechLengthAreRejected() {
        var value = Reminder(title: "صوت", date: Date()); value.audio = ReminderAudio()
        for volume in [-1.0, 1.1, Double.infinity, Double.nan] {
            value.audio?.volume = volume; XCTAssertThrowsError(try value.validated())
        }
        value.audio?.volume = 0.5; value.audio?.spokenText = String(repeating: "أ", count: 4001)
        XCTAssertThrowsError(try value.validated())
    }
    func testMuteKeepsSelectionAndEveryTypeOffersCustomAudio() throws {
        var value = try XCTUnwrap(SpiritualLibrary.shared.entry("quran-1-1")).reminder
        value.audio?.mutedChoice = value.sound
        let selected = value.audio; value.sound = .none
        let restored = try JSONDecoder().decode(Reminder.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(restored.sound, .none); XCTAssertEqual(restored.audio, selected)
        XCTAssertEqual(restored.audio?.mutedChoice, .quran)
        for type in ReminderType.allCases {
            value.type = type
            XCTAssertTrue(AudioCatalog.choices(for: value).contains(.none))
            XCTAssertTrue(AudioCatalog.choices(for: value).contains(.custom))
        }
    }
}
