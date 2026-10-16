import AppKit
import AVFoundation
import Combine
import CryptoKit
import ReminderCore

@MainActor final class SoundManager: NSObject, ObservableObject, AVAudioPlayerDelegate, NSSoundDelegate, AVSpeechSynthesizerDelegate {
    private var player: AVAudioPlayer?
    private var sound: NSSound?
    private let speech = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private var downloads: [String: Task<URL, Error>] = [:]
    var onPlaybackEnd: (() -> Void)?
    @Published private(set) var currentID: UUID?
    @Published private(set) var activeChoice: SoundChoice?
    var isPlaying: Bool { player?.isPlaying == true || sound?.isPlaying == true || speech.isSpeaking }
    let directory: URL
    var cacheDirectory: URL { directory.appendingPathComponent("Recordings", isDirectory: true) }
    var arabicVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("ar") }.sorted { $0.name < $1.name }
    }
    init(directory: URL) { self.directory = directory; super.init(); speech.delegate = self }
    func stop() {
        player?.stop(); sound?.stop(); speech.stopSpeaking(at: .immediate)
        player = nil; sound = nil; currentUtterance = nil; currentID = nil; activeChoice = nil
    }
    func cachedURL(for recording: AudioRecording) -> URL {
        let hash = SHA256.hash(data: Data(recording.url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(hash + ".mp3")
    }
    func isPrepared(_ reminder: Reminder) -> Bool {
        guard let recording = try? AudioCatalog.recording(for: reminder) else {
            if reminder.sound == .speech { return (try? voice(for: reminder)) != nil }
            if reminder.sound == .custom { return reminder.customSoundFile.map { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) } ?? false }
            return ![SoundChoice.adhan, .quran, .library].contains(reminder.sound)
        }
        if reminder.sound == .library, let id = reminder.audio?.libraryEntryID,
           let name = SpiritualLibrary.shared.entry(id)?.bundledAudio, AppResources.url(name, "mp3") != nil { return true }
        return FileManager.default.fileExists(atPath: cachedURL(for: recording).path)
    }
    /// Called before saving an audible reminder. Due-time playback never depends on the network.
    func prepare(_ reminder: Reminder) async throws {
        _ = try reminder.validated()
        if reminder.sound == .speech { _ = try voice(for: reminder); guard !spokenText(reminder).isEmpty else { throw AudioSelectionError.emptyText }; return }
        if reminder.sound == .custom { _ = try validatedPlayer(customURL(reminder)); return }
        guard let recording = try AudioCatalog.recording(for: reminder) else { return }
        if reminder.sound == .library, let id = reminder.audio?.libraryEntryID,
           let name = SpiritualLibrary.shared.entry(id)?.bundledAudio, let url = AppResources.url(name, "mp3") { _ = try validatedPlayer(url); return }
        let destination = cachedURL(for: recording)
        if FileManager.default.fileExists(atPath: destination.path) {
            if (try? validatedPlayer(destination)) != nil { return }
            try? FileManager.default.removeItem(at: destination)
        }
        if let task = downloads[destination.lastPathComponent] { _ = try await task.value; return }
        let task = Task { @MainActor in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 90
            let session = URLSession(configuration: configuration)
            defer { session.finishTasksAndInvalidate() }
            let (temporary, response) = try await session.download(from: recording.url)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  response.url?.scheme == "https" else { throw AudioSelectionError.downloadFailed }
            let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard (1...50_000_000).contains(size) else { throw AudioSelectionError.invalidAudio }
            _ = try self.validatedPlayer(temporary)
            try FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
            // A complete validated file is moved into place atomically.
            try FileManager.default.moveItem(at: temporary, to: destination)
            return destination
        }
        downloads[destination.lastPathComponent] = task
        defer { downloads[destination.lastPathComponent] = nil }
        do { _ = try await task.value; try Task.checkCancellation() }
        catch is CancellationError { throw CancellationError() }
        catch { throw AudioSelectionError.downloadFailed }
    }
    func play(_ reminder: Reminder, settings: AppSettings) throws {
        stop()
        guard settings.soundEnabled, reminder.sound != .none, settings.volume > 0 else { return }
        let volume = Float(settings.volume * (reminder.audio?.volume ?? 1))
        guard volume > 0 else { return }
        if reminder.sound == .speech {
            let utterance = AVSpeechUtterance(string: spokenText(reminder))
            guard !utterance.speechString.isEmpty else { throw AudioSelectionError.emptyText }
            utterance.voice = try voice(for: reminder); utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.86; utterance.volume = volume
            currentUtterance = utterance; speech.speak(utterance)
        } else if reminder.sound == .dhikr {
            guard let url = AppResources.url("dhikr-sample", "mp3") else { throw DataError.invalidData }
            try playFile(url, volume: volume)
        } else if reminder.sound == .custom {
            try playFile(customURL(reminder), volume: volume)
        } else if let recording = try AudioCatalog.recording(for: reminder) {
            var url = cachedURL(for: recording)
            if reminder.sound == .library, let id = reminder.audio?.libraryEntryID,
               let name = SpiritualLibrary.shared.entry(id)?.bundledAudio, let bundled = AppResources.url(name, "mp3") { url = bundled }
            guard FileManager.default.fileExists(atPath: url.path) else { throw AudioSelectionError.missingDownload }
            try playFile(url, volume: volume)
        } else {
            let name = reminder.sound == .bell ? "Glass" : (reminder.sound == .soft ? "Pop" : "Tink")
            sound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound
            sound?.volume = volume; sound?.delegate = self
            guard sound?.play() == true else { throw playbackError }
        }
        currentID = reminder.id; activeChoice = reminder.sound
        Log.sound.debug("Started selected reminder audio")
    }
    private func playFile(_ url: URL, volume: Float) throws {
        player = try validatedPlayer(url); player?.delegate = self; player?.volume = volume
        player?.prepareToPlay(); guard player?.play() == true else { throw playbackError }
    }
    private func validatedPlayer(_ url: URL) throws -> AVAudioPlayer {
        let player = try AVAudioPlayer(contentsOf: url)
        guard player.duration.isFinite && player.duration > 0 else { throw AudioSelectionError.invalidAudio }
        return player
    }
    private func customURL(_ reminder: Reminder) throws -> URL {
        guard let file = reminder.customSoundFile, file == URL(fileURLWithPath: file).lastPathComponent, !file.contains("..") else { throw AudioSelectionError.invalidAudio }
        return directory.appendingPathComponent(file)
    }
    private func spokenText(_ reminder: Reminder) -> String {
        (reminder.audio?.spokenText ?? (reminder.detail.isEmpty ? reminder.title : reminder.detail)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func voice(for reminder: Reminder) throws -> AVSpeechSynthesisVoice {
        if let id = reminder.audio?.voiceIdentifier {
            guard let voice = AVSpeechSynthesisVoice(identifier: id), voice.language.hasPrefix("ar") else { throw AudioSelectionError.noVoice }
            return voice
        }
        guard let voice = arabicVoices.first else { throw AudioSelectionError.noVoice }
        return voice
    }
    private func completed() { currentID = nil; activeChoice = nil; onPlaybackEnd?() }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in if self.player === player { self.completed() } }
    }
    nonisolated func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        Task { @MainActor in if self.sound === sound { self.completed() } }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in if self.currentUtterance === utterance { self.completed() } }
    }
    private var playbackError: Error { NSError(domain: "MasterReminder.Sound", code: 2, userInfo: [NSLocalizedDescriptionKey: "تعذّر بدء الصوت. راجع جهاز إخراج الصوت ومستواه في macOS."]) }
    func importFile(_ url: URL) throws -> String {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard (1...50_000_000).contains(size) else { throw AudioSelectionError.invalidAudio }
        _ = try validatedPlayer(url)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = UUID().uuidString + "." + url.pathExtension.lowercased()
        try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(name))
        return name
    }
}
