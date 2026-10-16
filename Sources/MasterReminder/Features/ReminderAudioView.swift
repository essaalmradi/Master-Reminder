import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import ReminderCore
import ReminderDesign

struct ReminderAudioView: View {
    @EnvironmentObject var model: AppModel
    @Binding var reminder: Reminder
    @State private var previous: SoundChoice = .default
    @State private var task: Task<Void, Never>?
    @State private var busy = false
    @State private var message: String?
    @State private var failure: String?
    @State private var library = false
    private var audio: ReminderAudio { reminder.audio ?? ReminderAudio() }
    private var entry: LibraryEntry? { audio.libraryEntryID.flatMap { SpiritualLibrary.shared.entry($0) } }
    private var voices: [AVSpeechSynthesisVoice] { model.sounds.arabicVoices }
    private func binding<T>(_ key: WritableKeyPath<ReminderAudio, T>) -> Binding<T> {
        Binding(get: { audio[keyPath: key] }, set: { value in var next = audio; next[keyPath: key] = value; reminder.audio = next })
    }
    var body: some View {
        Group {
            Toggle("تشغيل صوت مع التذكير", isOn: Binding(get: { reminder.sound != .none }, set: { enabled in
                if enabled { reminder.sound = previous == .none ? AudioCatalog.suggestedSound(for: reminder) : previous; configure() }
                else { previous = reminder.sound; var next = audio; next.mutedChoice = reminder.sound; reminder.audio = next; reminder.sound = .none }
            })).toggleStyle(.switch).accessibilityIdentifier("audio.enabled")
            if reminder.sound == .none {
                Text("سيظهر النص بدون صوت.").font(Brand.font(13)).foregroundStyle(.secondary)
            } else {
                Picker("نوع الصوت", selection: $reminder.sound) {
                    ForEach(AudioCatalog.choices(for: reminder).filter { $0 != .none }) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("audio.kind")
                if reminder.sound == .adhan {
                    Picker("المؤذّن", selection: Binding(get: { audio.recordingID ?? "alafasy" }, set: { value in var next = audio; next.recordingID = value; reminder.audio = next })) {
                        ForEach(AudioCatalog.adhans) { Text($0.title).tag($0.id) }
                    }.accessibilityIdentifier("audio.muezzin")
                    Text("التسجيل الكامل للمؤذّن المختار. يمكنك اختيار ملف من جهازك لأذان الفجر أو لأي مؤذّن آخر.").font(Brand.font(12)).foregroundStyle(.secondary)
                } else if reminder.sound == .quran {
                    Picker("القارئ", selection: Binding(get: { audio.reciterID ?? "alafasy" }, set: { value in var next = audio; next.reciterID = value; reminder.audio = next })) {
                        ForEach(AudioCatalog.reciters) { Text($0.name).tag($0.id) }
                    }.accessibilityIdentifier("audio.reciter")
                    HStack { Text(entry?.title ?? "اختر الآية التي تريد سماعها").font(Brand.font(13)); Spacer(); Button("اختيار آية…") { library = true } }
                    Text("التلاوة للآية المحددة بصوت القارئ المختار.").font(Brand.font(12)).foregroundStyle(.secondary)
                } else if reminder.sound == .library {
                    LabeledContent("الصوت", value: "حمد الدريهم · حصن المسلم")
                    Text(entry?.title ?? "اختر الذكر أو الدعاء من المكتبة").font(Brand.font(13)).foregroundStyle(.secondary)
                    Text("تسجيل النص المحدد؛ اختر «ملف مخصص» إذا تبي أداءً آخر.").font(Brand.font(12)).foregroundStyle(.secondary)
                    Button("اختيار ذكر أو دعاء…") { library = true }
                } else if reminder.sound == .speech {
                    Picker("الصوت العربي", selection: binding(\.voiceIdentifier)) {
                        Text("الصوت العربي المتاح تلقائيًا").tag(String?.none)
                        ForEach(voices, id: \.identifier) { voice in Text("\(voice.name) · \(voice.language)").tag(Optional(voice.identifier)) }
                    }.accessibilityIdentifier("audio.voice")
                    TextField("النص المسموع", text: Binding(get: { audio.spokenText ?? (reminder.detail.isEmpty ? reminder.title : reminder.detail) }, set: { value in var next = audio; next.spokenText = value; reminder.audio = next }), axis: .vertical).lineLimit(3...6)
                    Text("قراءة آلية بأصوات macOS العربية المتاحة على جهازك.").font(Brand.font(12)).foregroundStyle(.secondary)
                    if voices.isEmpty {
                        Text(AudioSelectionError.noVoice.localizedDescription).font(Brand.font(12)).foregroundStyle(.orange)
                        Button("إعدادات الأصوات") { if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess") { NSWorkspace.shared.open(url) } }
                    }
                } else if reminder.sound == .custom {
                    HStack {
                        Text(reminder.customSoundFile == nil ? "لم تختَر ملفًا بعد" : "ملف صوت محفوظ على الجهاز").font(Brand.font(13)).foregroundStyle(.secondary)
                        Spacer(); Button("اختيار ملف صوت…", action: chooseFile)
                    }
                }
                HStack {
                    Text("مستوى هذا التذكير").font(Brand.font(13))
                    Slider(value: Binding(get: { audio.volume ?? 1 }, set: { value in var next = audio; next.volume = value; reminder.audio = next }), in: 0...1)
                    Text("\(Int((audio.volume ?? 1) * 100))٪").font(Brand.number(12)).frame(width: 42)
                }
                if !model.settings.soundEnabled || model.settings.volume == 0 {
                    HStack { Text("الصوت العام متوقف.").font(Brand.font(13)); Spacer(); Button("تفعيل الصوت") { model.updateSettings { $0.soundEnabled = true; if $0.volume == 0 { $0.volume = 0.6 } } } }
                }
                HStack(spacing: 12) {
                    Button { preview() } label: { Label(busy ? "جارٍ تجهيز الصوت…" : "استمع للصوت المختار", systemImage: "play.circle") }.disabled(busy).accessibilityIdentifier("audio.preview")
                    Button("إيقاف") { stopPreview() }
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                }
                if let failure { Text(failure).font(Brand.font(12)).foregroundStyle(.red) }
                else { Text(message ?? (model.sounds.isPrepared(reminder) ? "جاهز على جهازك." : "يُنزل الصوت عند المعاينة أو الحفظ، ثم يعمل بدون إنترنت.")).font(Brand.font(12)).foregroundStyle(.secondary) }
                if let recording = try? AudioCatalog.recording(for: reminder) { Link("مصدر التسجيل", destination: recording.sourceURL).font(Brand.font(12)) }
            }
        }.onAppear { previous = audio.mutedChoice ?? reminder.sound; configure() }
        .onChange(of: reminder.sound) { _ in stopPreview(); configure() }
        .onChange(of: reminder.audio) { _ in stopPreview() }
        .onDisappear { stopPreview() }
        .sheet(isPresented: $library) {
            VStack(spacing: 16) {
                HStack { Text(reminder.sound == .quran ? "اختر الآية" : "اختر الذكر أو الدعاء").font(Brand.font(23)); Spacer(); Button("إغلاق") { library = false } }
                LibraryBrowser(category: reminder.sound == .quran ? .quran : nil) { selected in
                    var next = audio; next.libraryEntryID = selected.id; next.reciterID = selected.selectedReciterID ?? next.reciterID; next.spokenText = selected.text
                    reminder.audio = next; reminder.title = selected.title; reminder.detail = selected.text + "\n\n" + selected.reference
                    reminder.sound = selected.category == "quran" ? .quran : (selected.audioURL != nil ? .library : .speech)
                    library = false; configure()
                }
            }.padding(24).frame(width: 650, height: 590).environment(\.layoutDirection, .rightToLeft)
        }
    }
    private func configure() {
        var next = audio
        if reminder.sound == .adhan && next.recordingID == nil { next.recordingID = "alafasy" }
        if reminder.sound == .quran && next.reciterID == nil { next.reciterID = "alafasy" }
        if reminder.audio != next { reminder.audio = next }
    }
    private func stopPreview() {
        task?.cancel(); task = nil; busy = false; message = nil; failure = nil
        if model.sounds.currentID == reminder.id { model.sounds.stop() }
    }
    private func preview() {
        stopPreview(); busy = true
        var value = reminder
        if value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { value.title = "معاينة الصوت" }
        task = Task { @MainActor in
            do {
                try await model.sounds.prepare(value); try Task.checkCancellation()
                guard model.settings.soundEnabled && model.settings.volume > 0 else { busy = false; message = "فعّل الصوت العام للاستماع."; return }
                try model.sounds.play(value, settings: model.settings)
                message = "الصوت المختار جاهز على جهازك."; busy = false
            } catch is CancellationError { }
            catch { busy = false; failure = error.localizedDescription }
        }
    }
    private func chooseFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { reminder.customSoundFile = try model.sounds.importFile(url); message = "تم حفظ ملفك الصوتي." }
        catch { failure = error.localizedDescription }
    }
}
