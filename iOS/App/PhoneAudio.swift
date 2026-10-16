import Foundation
import AVFoundation
import CryptoKit
import ReminderCore

/// Full recordings for listening; <=29-second PCM clips for system alerts.
@MainActor final class PhoneAudio {
    private let files = FileManager.default
    private let root: URL
    let soundsDirectory: URL
    private var player: AVAudioPlayer?
    private var downloads: [String: Task<URL, Error>] = [:]
    var arabicVoices: [AVSpeechSynthesisVoice] { AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("ar") } }
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MasterReminder/Audio")
        soundsDirectory = root?.appendingPathComponent("Sounds") ?? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Sounds")
    }
    func stop() {
        player?.stop(); player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func preview(_ reminder: Reminder, alertClip: Bool = false) async throws {
        stop(); guard reminder.sound != .none else { return }
        let url: URL
        if alertClip, let name = try await prepareAlarm(reminder) { url = soundsDirectory.appendingPathComponent(name) }
        else { url = try await source(for: reminder) }
        try Task.checkCancellation()
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
        player = try validPlayer(url); player?.volume = alertClip ? 1 : Float(reminder.audio?.volume ?? 1)
        guard player?.play() == true else { throw AudioSelectionError.invalidAudio }
    }
    /// nil means system default. Silent reminders use UserNotifications instead.
    func prepareAlarm(_ reminder: Reminder) async throws -> String? {
        guard reminder.sound != .none, reminder.sound != .default else { return nil }
        let source = try await source(for: reminder); try Task.checkCancellation()
        let gain = reminder.audio?.volume ?? 1
        let output = soundsDirectory.appendingPathComponent(digest(source.lastPathComponent + "|\(gain)|pcm29-v1") + ".caf")
        if files.fileExists(atPath: output.path), (try? validPlayer(output)) != nil { return output.lastPathComponent }
        try files.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
        let temporary = soundsDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        defer { try? files.removeItem(at: temporary) }
        try makeAlert(source: source, output: temporary, gain: Float(gain)); _ = try validPlayer(temporary)
        try files.moveItem(at: temporary, to: output)
        try files.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: output.path)
        return output.lastPathComponent
    }
    func importFile(_ url: URL) throws -> String {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard (1...50_000_000).contains(size) else { throw AudioSelectionError.invalidAudio }
        _ = try validPlayer(url)
        let folder = root.appendingPathComponent("Imported"); try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = UUID().uuidString + "." + url.pathExtension.lowercased()
        try files.copyItem(at: url, to: folder.appendingPathComponent(name)); return name
    }
    func source(for reminder: Reminder) async throws -> URL {
        if reminder.sound == .speech { return try await speechFile(reminder) }
        if reminder.sound == .custom {
            guard let name = reminder.customSoundFile, name == URL(fileURLWithPath: name).lastPathComponent, !name.contains("..") else { throw AudioSelectionError.invalidAudio }
            let url = root.appendingPathComponent("Imported").appendingPathComponent(name); _ = try validPlayer(url); return url
        }
        if reminder.sound == .dhikr {
            guard let url = AppResources.url("dhikr-sample", "mp3") else { throw AudioSelectionError.missingDownload }; return url
        }
        if reminder.sound == .library, let id = reminder.audio?.libraryEntryID,
           let name = SpiritualLibrary.shared.entry(id)?.bundledAudio, let url = AppResources.url(name, "mp3") { return url }
        if let recording = try AudioCatalog.recording(for: reminder) { return try await download(recording) }
        return try tone(soft: reminder.sound == .soft)
    }
    private func download(_ recording: AudioRecording) async throws -> URL {
        let directory = root.appendingPathComponent("Recordings")
        let destination = directory.appendingPathComponent(digest(recording.url.absoluteString) + ".mp3")
        if files.fileExists(atPath: destination.path), (try? validPlayer(destination)) != nil { return destination }
        let key = destination.lastPathComponent
        if let task = downloads[key] { return try await task.value }
        let task = Task { @MainActor in
            let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 90
            let session = URLSession(configuration: config); defer { session.finishTasksAndInvalidate() }
            let temporary: URL; let response: URLResponse
            do { (temporary, response) = try await session.download(from: recording.url) }
            catch { try Task.checkCancellation(); (temporary, response) = try await session.download(from: recording.url) }
            defer { try? self.files.removeItem(at: temporary) }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), response.url?.scheme == "https" else { throw AudioSelectionError.downloadFailed }
            let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard (1...50_000_000).contains(size) else { throw AudioSelectionError.invalidAudio }
            _ = try self.validPlayer(temporary, hint: AVFileType.mp3.rawValue)
            try self.files.createDirectory(at: directory, withIntermediateDirectories: true)
            if self.files.fileExists(atPath: destination.path) { try self.files.removeItem(at: destination) }
            try self.files.moveItem(at: temporary, to: destination); return destination
        }
        downloads[key] = task; defer { downloads[key] = nil }
        let url = try await task.value; try Task.checkCancellation(); return url
    }
    private func speechFile(_ reminder: Reminder) async throws -> URL {
        let text = (reminder.audio?.spokenText ?? (reminder.detail.isEmpty ? reminder.title : reminder.detail)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 4000 else { throw AudioSelectionError.emptyText }
        let voice: AVSpeechSynthesisVoice?
        if let id = reminder.audio?.voiceIdentifier { voice = AVSpeechSynthesisVoice(identifier: id) } else { voice = arabicVoices.first }
        guard let voice, voice.language.hasPrefix("ar") else { throw PhoneError.noVoice }
        let directory = root.appendingPathComponent("Speech")
        let destination = directory.appendingPathComponent(digest(voice.identifier + "|" + text) + ".caf")
        if files.fileExists(atPath: destination.path), (try? validPlayer(destination)) != nil { return destination }
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(UUID().uuidString + ".caf")
        let synth = AVSpeechSynthesizer(); synth.usesApplicationAudioSession = false
        let sink = SpeechFileSink(url: temporary)
        let utterance = AVSpeechUtterance(string: text); utterance.voice = voice; utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.86
        let timeout = Task { try await Task.sleep(for: .seconds(60)); sink.finish(.failure(PhoneError.speechFailed)) }
        defer { timeout.cancel(); synth.stopSpeaking(at: .immediate); try? files.removeItem(at: temporary) }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                sink.attach(continuation); synth.write(utterance) { sink.consume($0) }
            }
        } onCancel: { sink.finish(.failure(CancellationError())) }
        try Task.checkCancellation(); _ = try validPlayer(temporary)
        if files.fileExists(atPath: destination.path) { try files.removeItem(at: destination) }
        try files.moveItem(at: temporary, to: destination); return destination
    }
    private func tone(soft: Bool) throws -> URL {
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(soft ? "soft.caf" : "bell.caf")
        if files.fileExists(atPath: url.path) { return url }
        let rate = 44100.0, count = AVAudioFrameCount(88200)
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!; buffer.frameLength = count
        for i in 0..<Int(count) {
            let t = Double(i) / rate
            buffer.floatChannelData![0][i] = Float(sin(2 * .pi * (soft ? 440 : 880) * t) * exp(-t * 3) * min(t * 100, 1) * 0.4)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer); return url
    }
    private func makeAlert(source: URL, output: URL, gain: Float) throws {
        let reader = try AVAudioFile(forReading: source)
        let format = reader.processingFormat
        guard format.sampleRate > 0, format.channelCount > 0, format.channelCount <= 2 else { throw AudioSelectionError.invalidAudio }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let writer = try AVAudioFile(forWriting: output, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        let limit = min(reader.length, AVAudioFramePosition(format.sampleRate * 29))
        var frames: AVAudioFramePosition = 0
        while frames < limit {
            try reader.read(into: buffer, frameCount: AVAudioFrameCount(min(4096, limit - frames)))
            guard buffer.frameLength > 0 else { break }
            if let channels = buffer.floatChannelData {
                for channel in 0..<Int(format.channelCount) { for index in 0..<Int(buffer.frameLength) {
                    let remaining = Double(limit - frames - Int64(index)) / format.sampleRate
                    let fade = reader.length > limit ? min(1, remaining / 0.12) : 1
                    channels[channel][index] *= gain * Float(fade)
                } }
            }
            try writer.write(from: buffer); frames += Int64(buffer.frameLength)
        }
        guard frames > 0 else { throw AudioSelectionError.invalidAudio }
    }
    private func validPlayer(_ url: URL, hint: String? = nil) throws -> AVAudioPlayer {
        let player = try AVAudioPlayer(contentsOf: url, fileTypeHint: hint)
        guard player.duration.isFinite, player.duration > 0 else { throw AudioSelectionError.invalidAudio }; return player
    }
    private func digest(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
}

/// Speech callbacks can arrive off the main actor; resolve once, even on cancellation.
private final class SpeechFileSink: @unchecked Sendable {
    private let lock = NSLock(), url: URL
    private var file: AVAudioFile?
    private var continuation: CheckedContinuation<Void, Error>?
    private var result: Result<Void, Error>?
    init(url: URL) { self.url = url }
    func attach(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        if let result { lock.unlock(); continuation.resume(with: result) }
        else { self.continuation = continuation; lock.unlock() }
    }
    func consume(_ value: AVAudioBuffer) {
        lock.lock(); guard result == nil else { lock.unlock(); return }
        guard let buffer = value as? AVAudioPCMBuffer else { lock.unlock(); finish(.failure(PhoneError.speechFailed)); return }
        guard buffer.frameLength > 0 else { lock.unlock(); finish(.success(())); return }
        do {
            if file == nil { file = try AVAudioFile(forWriting: url, settings: buffer.format.settings) }
            try file?.write(from: buffer); lock.unlock()
        } catch { lock.unlock(); finish(.failure(error)) }
    }
    func finish(_ result: Result<Void, Error>) {
        lock.lock(); guard self.result == nil else { lock.unlock(); return }
        self.result = result; file = nil
        let callback = continuation; continuation = nil; lock.unlock(); callback?.resume(with: result)
    }
}
