import SwiftUI
import UIKit
import ReminderCore
import ReminderDesign

@main struct MasterReminderPhone: App {
    @StateObject private var model = PhoneModel()
    @Environment(\.scenePhase) private var scenePhase
    init() {
        Brand.registerFonts()
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.titleTextAttributes = [.font: UIFont(name: Brand.arabicName, size: 21)!]
        appearance.largeTitleTextAttributes = [.font: UIFont(name: Brand.arabicName, size: 34)!]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UITabBarItem.appearance().setTitleTextAttributes([.font: UIFont(name: Brand.arabicName, size: 12)!], for: .normal)
    }
    var body: some Scene {
        WindowGroup {
            PhoneRoot().environmentObject(model)
                .environment(\.layoutDirection, .rightToLeft).environment(\.locale, Locale(identifier: "ar_LY"))
                .font(Brand.font(17)).tint(Brand.ocean)
                .onOpenURL { url in if url.scheme == "masterreminder" { model.selectedTab = 2 } }
                .task { await model.refreshMissingAlarms() }
                .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refreshMissingAlarms() } } }
        }
    }
}

struct PhoneRoot: View {
    @EnvironmentObject var model: PhoneModel
    var body: some View {
        TabView(selection: $model.selectedTab) {
            NavigationStack { PhoneHome() }.tabItem { Label("اليوم", systemImage: "square.grid.2x2") }.tag(0)
            NavigationStack { PhoneReminders() }.tabItem { Label("التذكيرات", systemImage: "bell") }.tag(1)
            NavigationStack {
                LibraryBrowser { model.editing = $0.reminder }.padding(18).navigationTitle("المكتبة")
                    
            }.tabItem { Label("المكتبة", systemImage: "books.vertical") }.tag(2)
            NavigationStack { TasbihView().navigationTitle("التسبيح") }.tabItem { Label("التسبيح", systemImage: "circle.dotted") }.tag(3)
            NavigationStack { PhoneSettings() }.tabItem { Label("المزيد", systemImage: "ellipsis.circle") }.tag(4)
        }
        .sheet(isPresented: $model.creating) { PhoneWizard().environmentObject(model) }
        .sheet(item: $model.editing) { reminder in NavigationStack { PhoneEditor(reminder: reminder).environmentObject(model) } }
        .alert("نحتاج انتباهك", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("حسنًا") { model.error = nil } } message: { Text(model.error ?? "") }
    }
}

struct PhoneHome: View {
    @EnvironmentObject var model: PhoneModel
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack { VStack(alignment: .leading, spacing: 5) { Text("مساحة هادئة ليومك").font(Brand.font(29)); Text("لحظة تطمئن فيها").font(Brand.font(16)).foregroundStyle(.secondary) }; Spacer(); BrandIcon(size: 50) }
                SpiritualWidgetView(kind: .next, nextTitle: model.upcoming.first?.reminder.title, nextDate: model.upcoming.first?.date).frame(height: 235)
                Button { model.creating = true } label: { Label("أضف تذكيرًا", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(BrandButton()).accessibilityIdentifier("new-reminder")
                Text("رفيق يومك").font(Brand.font(23))
                HStack(spacing: 12) {
                    Button { model.selectedTab = 2 } label: { quick("المكتبة", detail: "6,545 نصًا", icon: "books.vertical") }.buttonStyle(.plain)
                    Button { model.selectedTab = 3 } label: { quick("التسبيح", detail: "لحظة ذكر", icon: "circle.dotted") }.buttonStyle(.plain)
                }
                SpiritualWidgetView(kind: .verse).frame(height: 245)
                BrandCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("اسمع التجربة", systemImage: "waveform").font(Brand.font(22))
                        Text("تسجيل من حصن المسلم، متاح بدون إنترنت.").font(Brand.font(15)).foregroundStyle(.secondary)
                        HStack { Button("تشغيل الذكر") { if let sample = SpiritualLibrary.shared.audioSample { model.audio.play(sample) } }.buttonStyle(BrandButton()); Button("إيقاف") { model.audio.stop() }.font(Brand.font(15)) }
                    }
                }
            }.padding(20)
        }.background(Brand.page(scheme)).toolbar(.hidden, for: .navigationBar)
    }
    private func quick(_ title: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) { Image(systemName: icon).font(.title2).foregroundStyle(Brand.accent(scheme)); Text(title).font(Brand.font(21)); Text(detail).font(Brand.font(14)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(Brand.panel(scheme), in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(Brand.line(scheme)))
    }
}

struct PhoneReminders: View {
    @EnvironmentObject var model: PhoneModel
    @State private var deleting: Reminder?
    var body: some View {
        List {
            if model.data.reminders.isEmpty { Text("أضف ذكرًا أو موعدًا تحب أن تتذكره.").font(Brand.font(18)).padding(.vertical, 24) }
            ForEach(model.data.reminders) { reminder in
                Button { model.editing = reminder } label: {
                    HStack(spacing: 14) {
                        Image(systemName: reminder.type.symbol).foregroundStyle(Brand.ocean)
                        VStack(alignment: .leading, spacing: 6) { Text(reminder.title).font(Brand.font(19)); Text(reminder.repeatRule.title).font(Brand.font(14)).foregroundStyle(.secondary) }
                        Spacer(); Text(reminder.date, style: .time).font(Brand.number(17))
                    }.opacity(reminder.enabled ? 1 : 0.5).padding(.vertical, 8)
                }.buttonStyle(.plain).swipeActions { Button("حذف", role: .destructive) { deleting = reminder } }
            }
        }.navigationTitle("تذكيراتك").toolbar { Button { model.creating = true } label: { Image(systemName: "plus") } }
            .confirmationDialog("حذف التذكير؟", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) { Button("حذف", role: .destructive) { if let reminder = deleting { Task { await model.delete(reminder) } }; deleting = nil } }
    }
}

struct PhoneWizard: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var model: PhoneModel
    @State private var category: SpiritualCategory?
    @State private var editing: Reminder?
    var body: some View {
        NavigationStack {
            Group {
                if let editing { PhoneEditor(reminder: editing) }
                else if let category {
                    LibraryBrowser(category: category) { editing = $0.reminder }.padding(18).navigationTitle(category.title)
                        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("رجوع") { self.category = nil } } }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("ماذا تريد أن تتذكر؟").font(Brand.font(29))
                            Text("اختر النوع، ثم المحتوى والوقت.").font(Brand.font(16)).foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(SpiritualCategory.allCases) { item in
                                    CategoryTile(item) {
                                        if item == .custom || item == .prayer { var r = Reminder(title: item == .prayer ? "موعد الصلاة" : "", date: Date().addingTimeInterval(3600)); r.type = item.type; r.preAlertMinutes = 0; editing = r }
                                        else { category = item }
                                    }.accessibilityIdentifier("category-" + item.rawValue)
                                }
                            }
                        }.padding(20)
                    }.navigationTitle("تذكير جديد").navigationBarTitleDisplayMode(.inline)
                }
            }.toolbar { ToolbarItem(placement: .topBarTrailing) { Button("إلغاء") { dismiss() } } }
        }.environment(\.layoutDirection, .rightToLeft).font(Brand.font()).tint(Brand.ocean)
    }
}

struct PhoneEditor: View {
    @EnvironmentObject var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @State var reminder: Reminder
    private let weekdays = ["الأحد", "الإثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"]
    var body: some View {
        Form {
            Section("المحتوى") {
                TextField("عنوان التذكير", text: $reminder.title).accessibilityIdentifier("reminder-title")
                TextField("النص", text: $reminder.detail, axis: .vertical).lineLimit(3...10)
            }
            Section("الوقت") {
                DatePicker("الموعد", selection: $reminder.date)
                Picker("التكرار", selection: $reminder.repeatRule) { ForEach(RepeatRule.allCases) { Text($0.title).tag($0) } }
                if reminder.repeatRule == .weekdays {
                    ForEach(1...7, id: \.self) { day in Toggle(weekdays[day - 1], isOn: Binding(get: { reminder.weekdays.contains(day) }, set: { if $0 { reminder.weekdays.insert(day) } else { reminder.weekdays.remove(day) } })) }
                }
            }
            Section("المنبّه") {
                Picker("الصوت", selection: $reminder.sound) { Text("منبّه النظام").tag(SoundChoice.default); Text("ذكر مسجّل").tag(SoundChoice.dhikr) }
                Toggle("تأجيل لمدة 5 دقائق", isOn: $reminder.snoozeAllowed)
                Toggle("التذكير مفعّل", isOn: $reminder.enabled)
                Text("سيطلب الآيفون إذن المنبّهات عند حفظ أول تذكير. أوقات الصلاة التي تضيفها هنا يدوية.").font(Brand.font(14)).foregroundStyle(.secondary)
            }
            Section {
                Button { Task { if await model.save(reminder) { dismiss() } } } label: { HStack { Spacer(); if model.isSaving { ProgressView() } else { Text("حفظ التذكير") }; Spacer() } }
                    .disabled(model.isSaving || reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("save-reminder")
            }
        }.font(Brand.font(17)).navigationTitle("الوقت والتنبيه").navigationBarTitleDisplayMode(.inline)
    }
}

struct PhoneSettings: View {
    @EnvironmentObject var model: PhoneModel
    var body: some View {
        List {
            Section("جرّب التنبيه") { Button("منبّه بعد 10 ثوانٍ") { Task { await model.testAlarm() } }; Text("يعمل عبر منبّهات iOS بعد منح الإذن.").font(Brand.font(14)).foregroundStyle(.secondary) }
            Section("الويدجت") {
                Text("اضغط مطولًا على الشاشة الرئيسية، ثم تحرير ← إضافة ويدجت، وابحث عن Master Reminder.").font(Brand.font(16)).lineSpacing(5)
                Text("متاح: التاريخ، ذكر اليوم، وآية للتدبر. تتحدث وفق جدول iOS.").font(Brand.font(14)).foregroundStyle(.secondary)
            }
            Section("المصادر") {
                Link("القرآن · مشروع تنزيل", destination: URL(string: "https://tanzil.net/")!)
                Link("حصن المسلم", destination: URL(string: "https://www.hisnmuslim.com/")!)
                Link("الأربعون النووية", destination: URL(string: "https://sunnah.com/nawawi40")!)
                Text("القرآن محفوظ كما ورد في مصدره. تخريج الأحاديث داخل نصوصها. الملفات والتراخيص مرفقة بالتطبيق.").font(Brand.font(14)).foregroundStyle(.secondary)
            }
            Section("Master Reminder") { Text("0.2.0 · محفوظ على جهازك"); Text("المزامنة مع الماك غير مفعّلة في هذه النسخة.").font(Brand.font(14)).foregroundStyle(.secondary) }
        }.font(Brand.font(16)).navigationTitle("على طريقتك")
    }
}
