import SwiftUI
import ReminderDesign
import ReminderCore

struct PrayerView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHeading(title: "الصلاة", subtitle: "طرابلس، ليبيا · Africa/Tripoli")
                Label(model.prayerProvider.sourceDescription, systemImage: "info.circle")
                    .font(Brand.font(16)).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                ForEach(model.data.prayers) { entry in
                    PrayerRow(entry: entry, save: model.setPrayer).id("\(entry.id)-\(entry.revision)")
                    Divider()
                }
                Text("بعد الحفظ يتكرر الوقت الذي أدخلته يوميًا. الشروق تذكير اختياري، وليس صلاة مفروضة. لا نطلب موقعك. التسجيلات التي تختارها تُنزّل مرة وتُحفظ على جهازك.")
                    .font(Brand.font(14)).foregroundStyle(.secondary)
            }.padding(32)
        }
    }
}

private struct PrayerRow: View {
    @State var entry: PrayerEntry
    let save: (PrayerEntry) -> Void
    @State private var time = Date()
    @State private var configured = false
    @State private var showAudio = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(entry.name, systemImage: entry.name == "الشروق" ? "sunrise" : "moon.stars").font(Brand.font(18)).frame(width: 100, alignment: .leading)
                if !configured { Text("غير محدد").font(Brand.font(14)).foregroundStyle(.secondary) }
                Spacer()
                Toggle("مفعّل", isOn: $entry.enabled).toggleStyle(.switch)
            }
            HStack {
                DatePicker("الوقت اليدوي", selection: $time, displayedComponents: .hourAndMinute).labelsHidden()
                    .environment(\.timeZone, TimeZone(identifier: "Africa/Tripoli")!)
                    .onChange(of: time) { _ in configured = true }
                Stepper("تعديل: \(entry.adjustment > 0 ? "+" : "")\(entry.adjustment) دقيقة", value: $entry.adjustment, in: -120...120).frame(maxWidth: 250)
                Spacer()
                Button("حفظ الوقت") {
                    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Africa/Tripoli")!
                    entry.hour = cal.component(.hour, from: time); entry.minute = cal.component(.minute, from: time)
                    configured = true; save(entry)
                }.buttonStyle(.bordered)
            }
            HStack {
                Label(entry.sound?.title ?? "صوت افتراضي", systemImage: entry.sound == SoundChoice.none ? "speaker.slash" : "speaker.wave.2").font(Brand.font(13)).foregroundStyle(.secondary)
                Spacer()
                Button("الصوت والمؤذّن…") { showAudio = true }
            }
        }.padding(.vertical, 6)
        .sheet(isPresented: $showAudio) {
            PrayerSoundEditor(entry: entry) { value in
                entry.sound = value.sound; entry.audio = value.audio; entry.customSoundFile = value.customSoundFile
                save(entry); showAudio = false
            }
        }
        .onAppear {
            configured = entry.hour != nil
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Africa/Tripoli")!
            time = cal.date(bySettingHour: entry.hour ?? 12, minute: entry.minute, second: 0, of: Date()) ?? Date()
        }
    }
}

private struct PrayerSoundEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var reminder: Reminder
    @State private var saving = false
    @State private var saveTask: Task<Void, Never>?
    @State private var error: String?
    private let onSave: (Reminder) -> Void
    init(entry: PrayerEntry, onSave: @escaping (Reminder) -> Void) {
        var value = Reminder(title: "صلاة \(entry.name)", date: Date().addingTimeInterval(3600))
        value.id = entry.id; value.type = .prayer; value.sound = entry.sound ?? .default
        value.audio = entry.audio; value.customSoundFile = entry.customSoundFile
        _reminder = State(initialValue: value); self.onSave = onSave
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(reminder.title + " · الصوت").font(Brand.font(23)); Spacer(); Button("إلغاء") { dismiss() } }.padding(24)
            Form { Section("الصوت والمؤذّن") { ReminderAudioView(reminder: $reminder) } }.formStyle(.grouped).disabled(saving)
            if let error { Text(error).font(Brand.font(13)).foregroundStyle(.red).padding(16) }
            HStack { Spacer(); Button(saving ? "جارٍ تجهيز الصوت…" : "حفظ الصوت") {
                saving = true; error = nil
                let value = reminder
                saveTask = Task { @MainActor in
                    do { try await model.sounds.prepare(value); try Task.checkCancellation(); onSave(value) }
                    catch is CancellationError { }
                    catch { self.error = error.localizedDescription }
                    saving = false
                }
            }.buttonStyle(BrandButton()).disabled(saving) }.padding(24)
        }.font(Brand.font(14)).frame(width: 660, height: 580).environment(\.layoutDirection, .rightToLeft)
        .onDisappear { saveTask?.cancel(); if model.sounds.currentID == reminder.id { model.sounds.stop() } }
    }
}
