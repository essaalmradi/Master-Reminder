import SwiftUI
import ReminderCore
import ReminderDesign

struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("اليوم").font(Brand.font(30))
                        Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide)).font(Brand.font(13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.testOverlay() } label: { Label("معاينة التنبيه", systemImage: "rectangle.on.rectangle").font(Brand.font(13)).padding(.horizontal, 14).padding(.vertical, 10) }
                        .buttonStyle(.plain).brandGlass(radius: 18).accessibilityIdentifier("previewOverlay")
                }
                HStack(alignment: .top, spacing: 20) {
                    nextReminder.frame(maxWidth: .infinity)
                    dailyVerse.frame(width: 245)
                }
                AlarmHealthView(model: model)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("مواعيدك القادمة").font(Brand.font(19))
                        Spacer()
                        Button("كل التذكيرات") { model.page = .reminders }.buttonStyle(.plain).font(Brand.font(12)).foregroundStyle(Brand.accent(scheme))
                    }
                    if model.upcoming.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar").foregroundStyle(.secondary)
                            Text("مساحة ليومك. أضف موعدًا عندما تحتاجه.").font(Brand.font(14)).foregroundStyle(.secondary)
                            Spacer()
                        }.padding(.vertical, 20)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(model.upcoming.prefix(3).enumerated()), id: \.element.id) { index, item in
                                Button { if !item.reminder.isTemporary { model.editing = item.reminder } } label: { ReminderRow(reminder: item.reminder, date: item.date) }.buttonStyle(.plain)
                                if index < min(2, model.upcoming.count - 1) { Divider().opacity(0.45) }
                            }
                        }
                    }
                }.padding(.horizontal, 4)
                Divider().opacity(0.5)
                HStack(spacing: 10) {
                    Text("لحظة لك").font(Brand.font(13)).foregroundStyle(.secondary)
                    Spacer()
                    quickAction("أذكار", symbol: "sparkle") { model.newReminder(category: .dhikr) }
                    quickAction("دعاء", symbol: "hands.sparkles") { model.newReminder(category: .dua) }
                    quickAction("قرآن", symbol: "book.closed") { model.newReminder(category: .quran) }
                    quickAction("تسبيح", symbol: "circle.dotted") { model.page = .tasbih }
                }
            }.padding(30).frame(maxWidth: 1100)
        }
    }
    private var nextReminder: some View {
        BrandCard {
            VStack(alignment: .leading, spacing: 18) {
                Label("التذكير القادم", systemImage: "bell").font(Brand.font(13)).foregroundStyle(.secondary)
                if let next = model.upcoming.first {
                    Text(next.reminder.title).font(Brand.font(26)).lineLimit(2)
                    HStack(alignment: .lastTextBaseline, spacing: 12) {
                        Text(next.date, style: .time).font(Brand.number(39))
                        Text(next.date, style: .relative).font(Brand.font(13)).foregroundStyle(.secondary)
                    }
                    HStack {
                        Label(next.reminder.overlay && model.settings.overlayEnabled ? "على الشاشة" : "إشعار فقط", systemImage: "rectangle").font(Brand.font(12)).foregroundStyle(.secondary)
                        Spacer()
                        Button("تعديل") { model.editing = next.reminder }.font(Brand.font(13)).buttonStyle(.plain).foregroundStyle(Brand.accent(scheme))
                    }
                } else {
                    Text("وقتٌ لما يهمّك").font(Brand.font(28))
                    Text("ذكر، صلاة، أو موعد صغير لنفسك.").font(Brand.font(14)).foregroundStyle(.secondary)
                    Button { model.newReminder() } label: { Label("أضف تذكيرًا", systemImage: "plus") }.buttonStyle(BrandButton()).padding(.top, 6)
                }
            }.frame(maxWidth: .infinity, minHeight: 182, alignment: .leading)
        }
    }
    private var dailyVerse: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Image(systemName: "quote.opening").font(.system(size: 20, weight: .light)); Spacer(); Text("آية اليوم").font(Brand.font(12)) }.foregroundStyle(Brand.accent(scheme).opacity(0.75))
            Text(SpiritualLibrary.shared.dailyVerse()?.text ?? "").font(Brand.font(21)).lineSpacing(8).frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            Text(SpiritualLibrary.shared.dailyVerse()?.reference ?? "").font(Brand.font(10)).foregroundStyle(.secondary).lineLimit(2)
            Button("تأمّل في المكتبة") { model.page = .library }.font(Brand.font(12)).buttonStyle(.plain).foregroundStyle(Brand.accent(scheme))
        }.padding(24).frame(height: 230).frame(maxWidth: .infinity)
            .background(Brand.sky.opacity(scheme == .dark ? 0.08 : 0.055), in: RoundedRectangle(cornerRadius: 20))
    }
    private func quickAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol).font(Brand.font(13)).padding(.horizontal, 12).padding(.vertical, 9) }.buttonStyle(.plain).brandGlass(radius: 15)
    }
}

struct AlarmHealthView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var notifications: NotificationManager
    @Environment(\.colorScheme) private var scheme
    init(model: AppModel) { self.model = model; notifications = model.notifications }
    private var paused: Bool { model.settings.isPaused(at: Date()) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: paused ? "pause.circle" : (model.settings.overlayEnabled ? "checkmark.circle" : "rectangle.slash"))
                    .foregroundStyle(Brand.accent(scheme))
                VStack(alignment: .leading, spacing: 3) {
                    Text(paused ? "التذكيرات متوقفة مؤقتًا" : (model.settings.overlayEnabled ? "شاشة التنبيه مفعّلة" : "شاشة التنبيه متوقفة")).font(Brand.font(14))
                    Text(paused ? "استأنفها ليظهر التنبيه في موعده." : (model.settings.overlayEnabled ? "تستمر بعد إغلاق النافذة من الزر الأحمر." : "فعّلها ليظهر التذكير فوق التطبيقات.")).font(Brand.font(11)).foregroundStyle(.secondary)
                }
                Spacer()
                if paused { Button("استئناف") { model.resume() }.buttonStyle(BrandButton()) }
                else if !model.settings.overlayEnabled { Button("تفعيل") { model.updateSettings { $0.overlayEnabled = true } }.buttonStyle(BrandButton()) }
                else { Button("اختبار بعد 10 ثوانٍ") { model.testReminder() }.font(Brand.font(12)).buttonStyle(.bordered).accessibilityIdentifier("testScheduledReminder") }
            }
            if notifications.status == .denied || notifications.status == .notDetermined {
                HStack {
                    Text("إشعارات macOS غير مفعّلة؛ شاشة التنبيه تعمل بشكل مستقل.").font(Brand.font(11)).foregroundStyle(.secondary)
                    Spacer()
                    Button("إعداد الإشعارات") { model.page = .settings }.font(Brand.font(11)).buttonStyle(.plain).foregroundStyle(Brand.accent(scheme))
                }
            }
        }.padding(16).background(Brand.panel(scheme).opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
    }
}
