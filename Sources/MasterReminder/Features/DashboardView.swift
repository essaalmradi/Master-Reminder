import SwiftUI
import ReminderCore

struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    SectionHeading(title: "وقتك يستحق انتباهك", subtitle: Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    Button { model.newReminder() } label: { Label("تذكير جديد", systemImage: "plus") }.buttonStyle(.borderedProminent)
                }
                nextCard
                HStack(spacing: 14) {
                    StatusCard(title: "الإشعارات", symbol: "bell", value: model.notifications.statusText)
                    StatusCard(title: "التشغيل عند الدخول", symbol: "power", value: model.login.statusText)
                    StatusCard(title: "الحالة", symbol: "checkmark.circle", value: model.settings.isPaused(at: Date()) ? "متوقف مؤقتًا" : "جاهز للتذكير")
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("بقية اليوم").font(.title3.weight(.semibold)); Spacer(); Button("كل التذكيرات") { model.page = .reminders }.buttonStyle(.plain).foregroundStyle(.teal) }
                    let today = model.upcoming.filter { Calendar.current.isDateInToday($0.date) }
                    if today.isEmpty { Text("لا توجد مواعيد أخرى اليوم. خذ وقتك.").foregroundStyle(.secondary).padding(.vertical, 24) }
                    ForEach(Array(today.prefix(8))) { item in ReminderRow(reminder: item.reminder, date: item.date); Divider() }
                }
                HStack {
                    Button("تجربة التذكير بعد 10 ثوانٍ") { model.testReminder() }
                    Button("تجربة الإشعار") { model.testNotification() }
                    Button("تجربة الشاشة") { model.testOverlay() }
                }.controlSize(.regular)
                Text("أغلق النافذة وواصل عملك. التذكيرات تبقى بجانب الساعة.").font(.caption).foregroundStyle(.secondary)
            }.padding(32)
        }
        .onReceive(model.notifications.objectWillChange) { _ in model.objectWillChange.send() }
        .onReceive(model.login.objectWillChange) { _ in model.objectWillChange.send() }
    }
    private var nextCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("الموعد القادم", systemImage: "clock").font(.subheadline).foregroundStyle(.secondary)
            if let next = model.upcoming.first {
                HStack {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(next.reminder.title).font(.system(size: 34, weight: .medium))
                        HStack { Text("متبقٍ"); Text(next.date, style: .relative).monospacedDigit() }.font(.title3).foregroundStyle(.teal)
                        Text(next.reminder.type.title).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: next.reminder.type.symbol).font(.system(size: 64, weight: .ultraLight)).foregroundStyle(.teal.opacity(0.7)).padding(12)
                }
            } else {
                Text("ابدأ بموعد واحد").font(.largeTitle.weight(.medium))
                Text("صلاة، اجتماع، أو استراحة صغيرة. سنذكّرك في وقتها.").foregroundStyle(.secondary)
                Button("إضافة أول تذكير") { model.newReminder() }
            }
            if model.settings.isPaused(at: Date()), let until = model.settings.pausedUntil {
                HStack { Text("متوقف حتى"); Text(until, style: .time); Spacer(); Button("استئناف الآن") { model.resume() } }.font(.callout)
            }
        }.padding(28).frame(maxWidth: .infinity, minHeight: 210, alignment: .leading)
            .background(Color.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.teal.opacity(0.15), lineWidth: 1))
    }
}

private struct StatusCard: View {
    let title: String
    let symbol: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium))
        }.frame(maxWidth: .infinity, minHeight: 58, alignment: .leading).padding(16)
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}
