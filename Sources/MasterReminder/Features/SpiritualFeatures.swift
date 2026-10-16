import SwiftUI
import ReminderCore
import ReminderDesign

struct SpiritualLibraryPage: View {
    @EnvironmentObject var model: AppModel
    @State private var credits = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                SectionHeading(title: "المكتبة", subtitle: "القرآن كاملًا · حصن المسلم · الأربعون النووية")
                Button { credits = true } label: { Label("المصادر", systemImage: "checkmark.seal") }.font(Brand.font(14))
            }
            LibraryBrowser(onAdd: model.reminderFromLibrary)
        }.padding(30)
        .sheet(isPresented: $credits) { ContentCreditsView() }
    }
}

struct ContentCreditsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("المصادر والحقوق").font(Brand.font(27)); Spacer(); Button("إغلاق") { dismiss() } }
            ScrollView { Text(credits).font(Brand.font(16)).lineSpacing(8).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            Link("مشروع تنزيل", destination: URL(string: "https://tanzil.net/")!)
        }.padding(28).frame(width: 640, height: 680).environment(\.layoutDirection, .rightToLeft)
    }
    private var credits: String { AppResources.url("ContentCredits", "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "تعذّر قراءة ملف المصادر." }
}

struct ReminderWizard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var category: SpiritualCategory?
    @State private var value: Reminder?
    @State private var step = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if step < 2 {
                HStack { Text(step == 0 ? "ماذا تريد أن تتذكر؟" : "اختر ما يلامس قلبك").font(Brand.font(26)); Spacer(); Button("إلغاء") { dismiss() }.font(Brand.font(15)) }
                HStack(spacing: 9) { progress("النوع", number: 0); progress("المحتوى", number: 1); progress("الوقت والتنبيه", number: 2) }
                if step == 0 {
                    Text("ابدأ بالنوع، ثم اختر النص والوقت المناسبين لك.").font(Brand.font(16)).foregroundStyle(.secondary)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                            ForEach(SpiritualCategory.allCases) { item in CategoryTile(item) { choose(item) } }
                        }
                    }
                } else if let category {
                    LibraryBrowser(category: category) { entry in value = entry.reminder; step = 2 }
                    HStack { Button("رجوع للأنواع") { step = 0 }.font(Brand.font(15)); Spacer(); Button("اكتب نصك بنفسك") { var reminder = Reminder(title: "", date: Date().addingTimeInterval(3600)); reminder.type = category.type; value = reminder; step = 2 }.font(Brand.font(15)) }
                }
            } else if let value {
                HStack { Button("رجوع") { step = category == .custom || category == .prayer ? 0 : 1 }.font(Brand.font(14)); Spacer(); Text("الخطوة الأخيرة · الوقت والتنبيه").font(Brand.font(14)).foregroundStyle(.secondary) }
                ReminderEditor(reminder: value, embedded: true).environmentObject(model).id(value.id)
            }
        }.padding(step == 2 ? 14 : 28).frame(width: 700, height: 670)
            .background(Brand.page(scheme)).environment(\.layoutDirection, .rightToLeft).tint(Brand.ocean)
            .onAppear { if let initial = model.creationCategory, category == nil { choose(initial) } }
    }
    private func choose(_ item: SpiritualCategory) {
        category = item
        if item == .custom || item == .prayer {
            var reminder = Reminder(title: item == .prayer ? "موعد الصلاة" : "", date: Date().addingTimeInterval(3600))
            reminder.type = item.type; reminder.preAlertMinutes = model.settings.defaultPreAlert
            if item == .prayer { reminder.repeatRule = .daily }
            value = reminder; step = 2
        } else { step = 1 }
    }
    private func progress(_ title: String, number: Int) -> some View {
        HStack(spacing: 8) { Text("\(number + 1)").font(Brand.number(11)).frame(width: 22, height: 22).background(number == step ? Brand.ocean : Brand.sky.opacity(0.16), in: Circle()).foregroundStyle(number == step ? .white : Brand.accent(scheme)); Text(title).font(Brand.font(13)).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WidgetGallery: View {
    @ObservedObject var model: AppModel
    @ObservedObject var widgets: DesktopWidgetManager
    init(model: AppModel) { self.model = model; widgets = model.widgets }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHeading(title: "الويدجت", subtitle: "ويدجت مستقلة على سطح المكتب، حتى بعد إغلاق نافذة التطبيق.")
                BrandCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("إبقاء الويدجت فوق النوافذ", isOn: Binding(get: { widgets.floatOnTop }, set: widgets.setFloating)).toggleStyle(.switch)
                        Text("فعّل البطاقة ثم اسحب خلفيتها إلى المكان الذي تحب. تُحفظ مواقعها تلقائيًا. تستمر ما دام التطبيق يعمل من شريط القوائم.").font(Brand.font(14)).foregroundStyle(.secondary).lineSpacing(4)
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 22) {
                    ForEach(SpiritualWidgetKind.allCases) { kind in
                        VStack(alignment: .leading, spacing: 14) {
                            SpiritualWidgetView(kind: kind, nextTitle: model.upcoming.first?.reminder.title, nextDate: model.upcoming.first?.date, compact: true).frame(height: 220)
                            Toggle(kind.title, isOn: Binding(get: { widgets.enabled.contains(kind) }, set: { widgets.set(kind, visible: $0) })).toggleStyle(.switch).font(Brand.font(17))
                        }
                    }
                }
            }.padding(30)
        }
    }
}
