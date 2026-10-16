import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ReminderCore
import ReminderDesign

struct RemindersView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    @State private var deleting: Reminder?
    var filtered: [Reminder] {
        model.data.reminders.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
            .sorted { $0.date < $1.date }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                SectionHeading(title: "تذكيراتك", subtitle: "الأشياء المهمة، في مكان واحد.")
                Button { model.newReminder() } label: { Label("إضافة", systemImage: "plus") }.buttonStyle(.borderedProminent)
            }
            TextField("ابحث عن تذكير", text: $query).textFieldStyle(.roundedBorder)
            if filtered.isEmpty {
                Spacer()
                VStack(spacing: 14) { Image(systemName: "bell").font(.system(size: 40, weight: .light)).foregroundStyle(Brand.ocean); Text("لا توجد تذكيرات هنا بعد").font(Brand.font(21)); Text("أضف شيئًا تريد أن تتذكره.").foregroundStyle(.secondary) }.frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    ForEach(filtered) { reminder in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                ReminderRow(reminder: reminder, date: model.upcoming.first(where: { $0.reminder.id == reminder.id })?.date ?? reminder.date)
                                Toggle("مفعّل", isOn: Binding(get: { reminder.enabled }, set: { var value = reminder; value.enabled = $0; model.saveReminder(value) })).labelsHidden().toggleStyle(.switch)
                                Button { model.editing = reminder } label: { Image(systemName: "pencil") }.help("تعديل")
                                Button(role: .destructive) { deleting = reminder } label: { Image(systemName: "trash") }.help("حذف")
                            }
                            if !reminder.detail.isEmpty { Text(reminder.detail).font(Brand.font(14)).foregroundStyle(.secondary).lineLimit(2) }
                            HStack(spacing: 12) {
                                Text(reminder.date, style: .date)
                                Text(reminder.preAlertMinutes == 0 ? "بدون تنبيه مسبق" : "قبل \(reminder.preAlertMinutes) دقائق")
                                Label(reminder.sound.title, systemImage: "speaker.wave.2")
                                if reminder.overlay { Label(model.settings.overlayEnabled ? "على الشاشة" : "الشاشة متوقفة من الإعدادات", systemImage: "rectangle") }
                                if reminder.repeatRule == .once && reminder.date < Date() { Text("انتهى الموعد").foregroundStyle(.secondary) }
                            }.font(Brand.font(12)).foregroundStyle(.secondary)
                        }.padding(.vertical, 8).opacity(reminder.enabled ? 1 : 0.55)
                    }
                }.listStyle(.inset)
            }
            Text("تذكيرات مواقيت الصلاة تُدار من قسم الصلاة.").font(Brand.font(14)).foregroundStyle(.secondary)
        }.padding(32)
        .alert("حذف التذكير؟", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("حذف", role: .destructive) { if let deleting { model.deleteReminder(deleting) }; deleting = nil }
            Button("إلغاء", role: .cancel) { deleting = nil }
        } message: { Text("سيُحذف التذكير وتنبيهاته المؤجلة.") }
    }
}

struct ReminderEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var reminder: Reminder
    var embedded = false
    @State private var preSelection = 5
    @State private var localError: String?
    private let weekdays = ["الأحد", "الإثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"]
    var body: some View {
        VStack(spacing: 0) {
            if !embedded { HStack { Text("تفاصيل التذكير").font(Brand.font(23)); Spacer(); Button("إلغاء") { dismiss() } }.padding(20) }
            Form {
                Section("الموعد") {
                    TextField("العنوان", text: $reminder.title)
                    TextField("الوصف", text: $reminder.detail, axis: .vertical).lineLimit(2...4)
                    Picker("النوع", selection: $reminder.type) { ForEach(ReminderType.allCases) { Text($0.title).tag($0) } }
                    DatePicker("التاريخ والوقت", selection: $reminder.date)
                    HStack(spacing: 8) {
                        Text("موعد سريع").font(Brand.font(12)).foregroundStyle(.secondary)
                        Button("بعد 30 ثانية") { reminder.date = Date().addingTimeInterval(30); reminder.preAlertMinutes = 0; preSelection = 0 }
                        Button("بعد 5 دقائق") { reminder.date = Date().addingTimeInterval(300) }
                        Button("بعد ساعة") { reminder.date = Date().addingTimeInterval(3600) }
                    }.font(Brand.font(12)).buttonStyle(.bordered)
                    Picker("التكرار", selection: $reminder.repeatRule) { ForEach(RepeatRule.allCases) { Text($0.title).tag($0) } }
                    if reminder.repeatRule == .weekdays {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
                            ForEach(1...7, id: \.self) { day in
                                Toggle(weekdays[day - 1], isOn: Binding(get: { reminder.weekdays.contains(day) }, set: { if $0 { reminder.weekdays.insert(day) } else { reminder.weekdays.remove(day) } })).toggleStyle(.checkbox)
                            }
                        }
                    }
                }
                Section("التنبيه") {
                    Picker("التنبيه المسبق", selection: $preSelection) {
                        Text("بدون").tag(0)
                        ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) دقائق").tag($0) }
                        Text("مخصص").tag(-1)
                    }.onChange(of: preSelection) { value in if value >= 0 { reminder.preAlertMinutes = value } }
                    if preSelection == -1 { Stepper("قبل \(reminder.preAlertMinutes) دقيقة", value: $reminder.preAlertMinutes, in: 1...1440) }
                    Picker("الصوت", selection: $reminder.sound) { ForEach(SoundChoice.allCases) { Text($0.title).tag($0) } }
                    if reminder.sound == .custom {
                        HStack { Text(reminder.customSoundFile == nil ? "لم يُحدد ملف" : "ملف صوت جاهز").foregroundStyle(.secondary); Spacer(); Button("اختيار صوت…", action: chooseSound) }
                    }
                    Button("تجربة الصوت") { do { try model.sounds.play(reminder, settings: model.settings) } catch { localError = error.localizedDescription } }
                    Toggle("إظهار شاشة التنبيه", isOn: $reminder.overlay)
                    if reminder.overlay {
                        Stepper(reminder.overlayDuration == 0 ? "تبقى الشاشة حتى إغلاقها" : "إغلاق تلقائي بعد \(reminder.overlayDuration) ثانية", value: $reminder.overlayDuration, in: 0...3600, step: 15)
                    }
                    Toggle("السماح بالتأجيل", isOn: $reminder.snoozeAllowed)
                    Toggle("التذكير مفعّل", isOn: $reminder.enabled)
                }
                
            }.formStyle(.grouped)
            if let localError { Text(localError).font(Brand.font(13)).foregroundStyle(.red).padding(.horizontal, 20).padding(.vertical, 8) }
            Divider()
            HStack {
                Button("معاينة على الشاشة") { model.previewReminder(reminder) }.font(Brand.font(12)).buttonStyle(.plain)
                Spacer()
                Button("حفظ التذكير") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(20)
        }.font(Brand.font(14)).frame(width: embedded ? 650 : 680, height: embedded ? 570 : 650).environment(\.layoutDirection, .rightToLeft).tint(Brand.ocean)
        .onAppear { preSelection = [0, 5, 10, 15, 30].contains(reminder.preAlertMinutes) ? reminder.preAlertMinutes : -1 }
        .onDisappear { model.sounds.stop() }
    }
    private func chooseSound() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { reminder.customSoundFile = try model.sounds.importFile(url) } catch { localError = error.localizedDescription }
    }
    private func save() {
        guard reminder.repeatRule != .once || reminder.date > Date() else { localError = "اختر موعدًا في المستقبل للتذكير مرة واحدة."; return }
        guard reminder.sound != .custom || reminder.customSoundFile != nil else { localError = "اختر ملف الصوت أو غيّر نوع الصوت."; return }
        do { _ = try reminder.validated(); model.saveReminder(reminder) } catch { localError = error.localizedDescription }
    }
}
