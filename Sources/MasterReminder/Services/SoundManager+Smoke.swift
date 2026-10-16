import Foundation
import AVFoundation
import ReminderCore

extension SoundManager {
    /// Runs only from the installed-app CI smoke flag, with isolated temporary storage.
    func verifySelectionsForSmoke() async -> [String: Bool] {
        var results: [String: Bool] = [:]
        var candidates: [(String, Reminder)] = []
        for adhan in AudioCatalog.adhans {
            var value = Reminder(title: "اختبار الأذان", date: Date().addingTimeInterval(3600))
            value.type = .prayer; value.sound = .adhan; value.audio = ReminderAudio(); value.audio?.recordingID = adhan.id
            candidates.append(("adhan-" + adhan.id, value))
        }
        for reciter in AudioCatalog.reciters {
            var value = SpiritualLibrary.shared.entry("quran-1-1")!.reminder
            value.audio?.reciterID = reciter.id
            candidates.append(("quran-" + reciter.id, value))
        }
        if let entry = SpiritualLibrary.shared.entries.first(where: { $0.audioURL != nil && $0.bundledAudio == nil }) {
            candidates.append(("dhikr-matching-recording", entry.reminder))
        }
        for (name, value) in candidates {
            do {
                try await prepare(value)
                // Fresh engine using only the cache: play() has no network/download path.
                let restored = SoundManager(directory: directory)
                try restored.play(value, settings: AppSettings())
                try? await Task.sleep(nanoseconds: 150_000_000)
                results[name + "-download-decode-cache-play"] = restored.isPrepared(value) && restored.isPlaying && restored.currentID == value.id && restored.activeChoice == value.sound
                restored.stop()
                results[name + "-stop"] = !restored.isPlaying && restored.currentID == nil
            } catch { results[name + "-download-decode-cache-play"] = false; print("SMOKE AUDIO FAILED: \(name) \(error)") }
        }
        if var value = candidates.first?.1 {
            do {
                value.sound = .none; try play(value, settings: AppSettings())
                results["perReminderMute"] = !isPlaying && currentID == nil
                value.sound = .adhan
                var settings = AppSettings(); settings.soundEnabled = false; try play(value, settings: settings)
                results["globalMute"] = !isPlaying && currentID == nil
                settings.soundEnabled = true; value.audio?.volume = 0; try play(value, settings: settings)
                results["perReminderZeroVolume"] = !isPlaying && currentID == nil
            } catch { results["muteControls"] = false }
        }
        var spoken = Reminder(title: "تجربة صوت عربي", date: Date().addingTimeInterval(3600))
        spoken.sound = .speech; spoken.audio = ReminderAudio(); spoken.audio?.spokenText = "حان وقت الاستراحة. خذ نفسًا بهدوء واشرب بعض الماء."
        if let voice = arabicVoices.first {
            spoken.audio?.voiceIdentifier = voice.identifier
            do {
                try await prepare(spoken); try play(spoken, settings: AppSettings())
                try? await Task.sleep(nanoseconds: 600_000_000)
                results["selectedArabicSpeechStarts"] = isPlaying && activeChoice == .speech
                stop(); results["arabicSpeechStops"] = !isPlaying
            } catch { results["selectedArabicSpeechStarts"] = false }
        } else {
            do { try await prepare(spoken); results["missingArabicVoiceReported"] = false }
            catch { results["missingArabicVoiceReported"] = true }
        }
        spoken.audio?.voiceIdentifier = "not-an-installed-arabic-voice"
        do { try await prepare(spoken); results["invalidVoiceRejected"] = false }
        catch { results["invalidVoiceRejected"] = true }
        stop()
        return results
    }
}
