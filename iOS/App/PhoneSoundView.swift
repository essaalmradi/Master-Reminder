import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import ReminderCore
import ReminderDesign

struct PhoneSoundView: View {
    @EnvironmentObject var model: PhoneModel
    @Binding var reminder: Reminder
    @State private var task: Task<Void, Never>?
    @State private var busy = false
    @State private var failure: String?
    @State private var library = false
    @State private var importing = false
    private var audio: ReminderAudio { reminder.audio ?? ReminderAudio() }
    private var entry: LibraryEntry? { audio.libraryEntryID.flatMap { SpiritualLibrary.shared.entry($0) } }
    private func binding<T>(_ key: WritableKeyPath<ReminderAudio, T>) -> Binding<T> {
        Binding(get: { audio[keyPath: key] }, set: { value in var next = audio; next[keyPath: key] = value; reminder.audio = next })
    }
    var body: some View {
        Form {
            Section {
                Toggle("تشغيل صوت", isOn: Binding(get: { reminder.sound != .none }, set: { enabled in
                    if enabled { reminder.sound = audio.mutedChoice ?? AudioCatalog.suggestedSound(for: reminder); configure() }
                    else { var next = audio; next.mutedChoice = reminder.sound; reminder.audio = next; reminder.sound = .none }
                })).accessibilityIdentifier("audio.enabled")
                if reminder.sound == .none {
                    Text("إشعار بالنص بدون صوت. ظهوره يخضع لإعدادات الإشعارات والتركيز؛ التأجيل متاح للمنبّهات الصوتية.").foregroundStyle(.secondary)
                } else {
                    Picker("نوع الصوت", selection: $reminder.sound) {
                        ForEach(AudioCatalog.choices(for: reminder).filter { $0 != .none }) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("audio.kind")
                }
            }
            if reminder.sound != .none {
                Section("اختيارك") {
                    if reminder.sound == .adhan {
                        Picker("المؤذّن", selection: binding(\.recordingID)) {
                            ForEach(AudioCatalog.adhans) { Text($0.title).tag(Optional($0.id)) }
                        }.accessibilityIdentifier("audio.muezzin")
                    } else if reminder.sound == .quran {
                        Picker("القارئ", selection: binding(\.reciterID)) {
                            ForEach(AudioCatalog.reciters) { Text($0.name).tag(Optional($0.id)) }
                        }.accessibilityIdentifier("audio.reciter")
                        Text(entry?.title ?? "لم تختَر آية بعد").foregroundStyle(.secondary)
                        Button("اختيار آية من المكتبة") { library = true }
                    } else if reminder.sound == .library {
                        Text("حمد الدريهم · حصن المسلم")
                        Text(entry?.title ?? "اختر الذكر أو الدعاء").foregroundStyle(.secondary)
                        Button("اختيار ذكر أو دعاء") { library = true }
                    } else if reminder.sound == .speech {
                        Picker("الصوت العربي", selection: binding(\.voiceIdentifier)) {
                            Text("الصوت المتاح تلقائيًا").tag(String?.none)
                            ForEach(model.sounds.arabicVoices, id: \.identifier) { Text("\($0.name) · \($0.language)").tag(Optional($0.identifier)) }
                        }.accessibilityIdentifier("audio.voice")
                        TextField("النص المسموع", text: Binding(get: { audio.spokenText ?? (reminder.detail.isEmpty ? reminder.title : reminder.detail) }, set: { var next = audio; next.spokenText = $0; reminder.audio = next }), axis: .vertical).lineLimit(3...8)
                        Text("قراءة آلية بالصوت العربي المختار، تُحفظ كملف قبل جدولة التنبيه.").foregroundStyle(.secondary)
                    } else if reminder.sound == .custom {
                        Text(reminder.customSoundFile == nil ? "لم تختَر ملفًا بعد" : "ملفك محفوظ على الجهاز").foregroundStyle(.secondary)
                        Button("اختيار ملف صوت من الملفات") { importing = true }
                    }
                    if reminder.sound != .default {
                        HStack {
                            Text("مستوى المقطع")
                            Slider(value: Binding(get: { audio.volume ?? 1 }, set: { var next = audio; next.volume = $0; reminder.audio = next }), in: 0.1...1)
                            Text("\(Int((audio.volume ?? 1) * 100))٪").font(Brand.number(13))
                        }
                        Text("المستوى النهائي يتأثر أيضًا بمستوى صوت الآيفون.").font(Brand.font(14)).foregroundStyle(.secondary)
                    }
                }
                Section("استمع قبل الحفظ") {
                    if reminder.sound != .default {
                        Button { preview(clip: false) } label: { Label("استمع للتسجيل الكامل", systemImage: "play.circle") }.disabled(busy).accessibilityIdentifier("audio.preview")
                        Button { preview(clip: true) } label: { Label("معاينة مقطع التنبيه", systemImage: "bell.waveform") }.disabled(busy)
                        Button("إيقاف") { stop() }
                        if busy { HStack { ProgressView(); Text("جارٍ تجهيز الصوت…") } }
                        if let failure { Text(failure).foregroundStyle(.red).accessibilityIdentifier("audio.failure") }
                        Text("التنبيه يستخدم أول 29 ثانية كحد أقصى من اختيارك. التسجيل الكامل متاح للاستماع هنا. يُنزّل عند المعاينة أو الحفظ، ثم يعمل بدون إنترنت.").font(Brand.font(14)).foregroundStyle(.secondary)
                        if let recording = try? AudioCatalog.recording(for: reminder) { Link("مصدر التسجيل", destination: recording.sourceURL) }
                    } else {
                        Text("منبّه iOS الافتراضي. يمكنك تجربته من صفحة «المزيد».").foregroundStyle(.secondary)
                    }
                }
            }
        }.font(Brand.font(16)).navigationTitle("الصوت").navigationBarTitleDisplayMode(.inline)
        .onAppear { configure() }.onDisappear { stop() }
        .onChange(of: reminder.sound) { _, _ in stop(); configure() }
        .onChange(of: reminder.audio) { _, _ in stop() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            do { reminder.customSoundFile = try model.sounds.importFile(result.get()) } catch { failure = error.localizedDescription }
        }
        .sheet(isPresented: $library) {
            NavigationStack {
                LibraryBrowser(category: reminder.sound == .quran ? .quran : nil) { selected in
                    var next = audio; next.libraryEntryID = selected.id; next.reciterID = selected.selectedReciterID ?? next.reciterID; next.spokenText = selected.text
                    reminder.audio = next; reminder.title = selected.title; reminder.detail = selected.text + "\n\n" + selected.reference
                    reminder.sound = selected.category == "quran" ? .quran : (selected.audioURL == nil ? .speech : .library)
                    library = false; configure()
                }.padding(18).navigationTitle("المكتبة")
                    .toolbar { Button("إغلاق") { library = false } }
            }.environment(\.layoutDirection, .rightToLeft)
        }
    }
    private func configure() {
        var next = audio
        if reminder.sound == .adhan && next.recordingID == nil { next.recordingID = "alafasy" }
        if reminder.sound == .quran && next.reciterID == nil { next.reciterID = "alafasy" }
        if reminder.audio != next { reminder.audio = next }
    }
    private func stop() { task?.cancel(); task = nil; model.sounds.stop(); busy = false; failure = nil }
    private func preview(clip: Bool) {
        stop(); busy = true
        let value = reminder
        task = Task { @MainActor in
            do { try await model.sounds.preview(value, alertClip: clip); try Task.checkCancellation(); busy = false }
            catch is CancellationError { }
            catch { busy = false; failure = error.localizedDescription }
        }
    }
}
