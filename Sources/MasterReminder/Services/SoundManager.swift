import AppKit
import AVFoundation
import ReminderCore

@MainActor final class SoundManager {
    private var player: AVAudioPlayer?
    private var sound: NSSound?
    var isPlaying: Bool { player?.isPlaying == true || sound?.isPlaying == true }
    let directory: URL
    init(directory: URL) { self.directory = directory }
    func stop() { player?.stop(); sound?.stop(); player = nil; sound = nil }
    func play(_ reminder: Reminder, settings: AppSettings) throws {
        stop()
        guard settings.soundEnabled, reminder.sound != .none else { return }
        if reminder.sound == .dhikr {
            guard let url = AppResources.url("dhikr-sample", "mp3") else { throw DataError.invalidData }
            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = Float(settings.volume); player?.prepareToPlay()
            guard player?.play() == true else { throw playbackError }
        } else if reminder.sound == .custom {
            guard let file = reminder.customSoundFile else {
                throw NSError(domain: "sound", code: 1, userInfo: [NSLocalizedDescriptionKey: "اختر ملف الصوت المخصص أولًا."])
            }
            player = try AVAudioPlayer(contentsOf: directory.appendingPathComponent(file))
            player?.volume = Float(settings.volume); player?.prepareToPlay()
            guard player?.play() == true else { throw playbackError }
        } else {
            let name = reminder.sound == .bell ? "Glass" : (reminder.sound == .soft ? "Pop" : "Tink")
            sound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound
            sound?.volume = Float(settings.volume)
            guard sound?.play() == true else { throw playbackError }
        }
        Log.sound.debug("Started reminder audio")
    }
    private var playbackError: Error { NSError(domain: "MasterReminder.Sound", code: 2, userInfo: [NSLocalizedDescriptionKey: "تعذّر بدء الصوت. راجع جهاز إخراج الصوت ومستواه في macOS."]) }
    func importFile(_ url: URL) throws -> String {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size < 50_000_000 else { throw DataError.fileTooLarge }
        // Validate before copying; a renamed arbitrary file is not accepted as audio.
        _ = try AVAudioPlayer(contentsOf: url)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = UUID().uuidString + "." + url.pathExtension.lowercased()
        try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(name))
        return name
    }
}
