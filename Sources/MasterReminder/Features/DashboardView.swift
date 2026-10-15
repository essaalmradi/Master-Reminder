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
                    SectionHeading(title: "مساحة هادئة ليومك", subtitle: "ذكّر قلبك، ورتّب وقتك، وابدأ بلحظة.")
                    VStack(alignment: .trailing, spacing: 5) { Text(Date(), format: .dateTime.weekday(.wide)).font(Brand.font(22)); Text(Date(), format: .dateTime.day().month(.wide).year()).font(Brand.font(13)).foregroundStyle(.secondary) }
                }
                HStack(spacing: 18) {
                    hero.frame(maxWidth: .infinity)
                    SpiritualWidgetView(kind: .dhikr).frame(width: 258, height: 246)
                }
                HStack(spacing: 16) {
                    metric("تذكيرات مفعّلة", value: "\(model.allReminders.filter(\.enabled).count)", icon: "bell")
                    metric("نصوص في مكتبتك", value: "6,545", icon: "books.vertical")
                    metric("ويدجت على المكتب", value: "\(model.widgets.count)", icon: "rectangle.3.group")
                }
                HStack {
                    Text("ماذا تريد أن تتذكر؟").font(Brand.font(23))
                    Spacer()
                    Button("استكشف المكتبة") { model.page = .library }.buttonStyle(.plain).foregroundStyle(Brand.accent(scheme)).font(Brand.font(14))
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ForEach([SpiritualCategory.dhikr, .quran, .dua, .tasbih]) { category in
                        Button { if category == .tasbih { model.page = .tasbih } else { model.newReminder() } } label: {
                            HStack(spacing: 10) { Image(systemName: category.type.symbol).foregroundStyle(Brand.accent(scheme)); Text(category.title).font(Brand.font(16)); Spacer() }
                                .padding(16).frame(maxWidth: .infinity).background(Brand.panel(scheme), in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.line(scheme)))
                        }.buttonStyle(.plain)
                    }
                }
                BrandCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { Text("المواعيد القادمة").font(Brand.font(23)); Spacer(); Button("عرض الكل") { model.page = .reminders }.buttonStyle(.plain).font(Brand.font(14)).foregroundStyle(Brand.accent(scheme)) }
                        if model.upcoming.isEmpty {
                            HStack(spacing: 14) { Image(systemName: "calendar.badge.plus").font(.title).foregroundStyle(Brand.accent(scheme)); VStack(alignment: .leading, spacing: 5) { Text("ابدأ بتذكير تحبّه").font(Brand.font(19)); Text("ذكر الصباح، آية، أو دعاء في الوقت المناسب لك.").font(Brand.font(14)).foregroundStyle(.secondary) }; Spacer() }.padding(.vertical, 12)
                        } else { ForEach(Array(model.upcoming.prefix(3))) { item in ReminderRow(reminder: item.reminder, date: item.date) } }
                    }
                }
                HStack(spacing: 12) {
                    Image(systemName: "waveform").foregroundStyle(Brand.accent(scheme))
                    VStack(alignment: .leading, spacing: 4) { Text("اسمع التجربة").font(Brand.font(18)); Text("ذكر مسجّل من حصن المسلم، يعمل بدون إنترنت.").font(Brand.font(13)).foregroundStyle(.secondary) }
                    Spacer()
                    Button("استمع") { model.testSound() }.buttonStyle(BrandButton())
                    Button("إيقاف") { model.sounds.stop() }.font(Brand.font(14))
                }.padding(.horizontal, 6)
            }.padding(30)
        }
    }
    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(model.upcoming.isEmpty ? "لحظتك الأولى" : "التذكير القادم", systemImage: "sparkles").font(Brand.font(14)).foregroundStyle(Brand.ice)
            Text(model.upcoming.first?.reminder.title ?? "اجعل للذكر وقتًا").font(Brand.font(32)).lineLimit(2).minimumScaleFactor(0.7)
            if let next = model.upcoming.first {
                HStack { Text(next.date, style: .time).font(Brand.number(27)); Text("·"); Text(next.date, style: .relative).font(Brand.font(16)) }.foregroundStyle(Brand.ice)
            } else { Text("خطوة صغيرة، وأثر يبقى معك طوال اليوم.").font(Brand.font(16)).foregroundStyle(.white.opacity(0.8)) }
            Spacer(minLength: 0)
            HStack {
                Button { model.newReminder() } label: { Label("أضف تذكيرًا", systemImage: "plus").font(Brand.font(15)).padding(.horizontal, 18).padding(.vertical, 9).background(.white, in: Capsule()).foregroundStyle(Brand.ocean) }.buttonStyle(.plain)
                Spacer()
                Button("جرّب الآن") { model.testReminder() }.buttonStyle(.plain).font(Brand.font(15)).foregroundStyle(Brand.ice)
            }
        }.padding(26).frame(maxWidth: .infinity, minHeight: 246, maxHeight: 246, alignment: .leading).foregroundStyle(.white)
            .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 26))
    }
    private func metric(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) { Image(systemName: icon).foregroundStyle(Brand.accent(scheme)); VStack(alignment: .leading, spacing: 5) { Text(value).font(Brand.number(22)); Text(title).font(Brand.font(13)).foregroundStyle(.secondary) }; Spacer(minLength: 0) }
            .padding(18).frame(maxWidth: .infinity).background(Brand.panel(scheme), in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Brand.line(scheme)))
    }
}
