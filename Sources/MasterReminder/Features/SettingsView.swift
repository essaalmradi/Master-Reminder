import SwiftUI
import ReminderDesign
import ReminderCore
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var notifications: NotificationManager
    @ObservedObject var login: LoginItemManager
    @State private var showReset = false
    init(model: AppModel) { self.model = model; notifications = model.notifications; login = model.login }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "على طريقتك", subtitle: "تفاصيل صغيرة تجعل التذكير مناسبًا لك.").padding(32)
            Form {
                Section("عام") {
                    Toggle("تشغيل Master Reminder عند الدخول", isOn: Binding(get: { login.enabled }, set: model.setLogin))
                    HStack { Text(login.statusText).foregroundStyle(.secondary); Spacer(); Button("إعدادات عناصر الدخول") { login.openSettings() } }
                    LabeledContent("اللغة", value: "العربية")
                    Picker("المظهر", selection: model.setting(\.appearance)) {
                        Text("النظام").tag(Appearance.system); Text("فاتح").tag(Appearance.light); Text("داكن").tag(Appearance.dark)
                    }
                    HStack {
                        if model.settings.isPaused(at: Date()) { Text("التذكيرات متوقفة مؤقتًا"); Spacer(); Button("استئناف الآن") { model.resume() } }
                        else { Text("التذكيرات نشطة"); Spacer(); PauseMenu(model: model) }
                    }
                }
                Section("الإشعارات") {
                    LabeledContent("الحالة", value: notifications.statusText)
                    if notifications.status == .notDetermined {
                        Text("Master Reminder يحتاج الإشعارات لتنبيهك قبل المواعيد.").foregroundStyle(.secondary)
                        Button("السماح بالإشعارات") { model.allowNotifications() }
                    }
                    if notifications.status == .denied { Button("فتح إعدادات النظام") { notifications.openSystemSettings() } }
                    Stepper("التنبيه المسبق الافتراضي: \(model.settings.defaultPreAlert) دقائق", value: model.setting(\.defaultPreAlert), in: 0...120, step: 5)
                    Button("تجربة الإشعار") { model.testNotification() }
                }
                Section("شاشة التنبيه") {
                    Toggle("تفعيل شاشة التنبيه", isOn: model.setting(\.overlayEnabled))
                    Picker("الشاشات", selection: model.setting(\.allScreens)) { Text("كل الشاشات").tag(true); Text("الشاشة الرئيسية فقط").tag(false) }
                    HStack { Text("عتامة الخلفية"); Slider(value: model.setting(\.overlayOpacity), in: 0.75...0.95); Text("\(Int(model.settings.overlayOpacity * 100))٪").monospacedDigit() }
                    Button("تجربة الشاشة") { model.testOverlay() }
                    Text("يمكنك دائمًا إغلاق التنبيه بزر تم أو Escape. الظهور فوق تطبيقات ملء الشاشة يخضع لسلوك macOS.").font(Brand.font(14)).foregroundStyle(.secondary)
                }
                Section("الصوت") {
                    Toggle("تفعيل الأصوات", isOn: model.setting(\.soundEnabled))
                    HStack { Text("مستوى صوت التطبيق"); Slider(value: model.setting(\.volume), in: 0...1); Text("\(Int(model.settings.volume * 100))٪").monospacedDigit() }
                    HStack { Button("تجربة الصوت") { model.testSound() }; Button("إيقاف الصوت") { model.sounds.stop() } }
                    Text("مستوى الصوت هنا يخص الصوت داخل التطبيق. صوت إشعار النظام يتبع إعدادات macOS.").font(Brand.font(14)).foregroundStyle(.secondary)
                }
                Section("التأجيل والمواعيد الفائتة") {
                    Picker("التأجيل الافتراضي", selection: model.setting(\.defaultSnooze)) { ForEach([5, 10, 15], id: \.self) { Text("\($0) دقائق").tag($0) } }
                    Stepper("مهلة التذكير بعد الاستيقاظ: \(model.settings.graceMinutes) دقيقة", value: model.setting(\.graceMinutes), in: 1...240)
                    Text("إذا مرّت هذه المهلة أثناء السكون، يُسجّل الموعد كفائت ولا يفتح شاشة قديمة.").font(Brand.font(14)).foregroundStyle(.secondary)
                }
                Section("البيانات") {
                    HStack { Button("تصدير البيانات…") { model.exportData() }; Button("استيراد البيانات…") { model.importData() } }
                    Button("إعادة ضبط بيانات التطبيق…", role: .destructive) { showReset = true }
                    Text("بياناتك محفوظة محليًا. لا حسابات، لا مزامنة سحابية، ولا تقويم متصل في هذا الإصدار.").font(Brand.font(14)).foregroundStyle(.secondary)
                }
                Section("Master Reminder") {
                    LabeledContent("الإصدار", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"))")
                    Text("صُنع لتتوقف في الوقت المناسب.").foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
        }.alert("إعادة ضبط التطبيق؟", isPresented: $showReset) {
            Button("إعادة الضبط", role: .destructive) { model.resetData() }
            Button("إلغاء", role: .cancel) { }
        } message: { Text("ستُزال التذكيرات والإعدادات الحالية. نحفظ نسخة محلية قبل الضبط، ولا نغيّر أذونات macOS أو عنصر الدخول.") }
    }
}
