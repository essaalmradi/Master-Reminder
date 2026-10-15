import SwiftUI
import ReminderCore
import ReminderDesign

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    private var colorScheme: ColorScheme? {
        switch model.settings.appearance { case .system: return nil; case .dark: return .dark; case .light: return .light }
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 218)
            Rectangle().fill(Brand.line(scheme)).frame(width: 1)
            VStack(spacing: 0) {
                if let notice = model.notice {
                    HStack { Text(notice).font(Brand.font(15)); Spacer(); Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                        .padding(14).background(Brand.sky.opacity(0.1))
                }
                Group {
                    switch model.page {
                    case .dashboard: DashboardView()
                    case .reminders: RemindersView()
                    case .library: SpiritualLibraryPage()
                    case .tasbih: TasbihView()
                    case .widgets: WidgetGallery(model: model)
                    case .prayer: PrayerView()
                    case .settings: SettingsView(model: model)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(Brand.page(scheme))
        }
        .font(Brand.font(17)).foregroundStyle(Brand.ink(scheme)).tint(Brand.ocean)
        .environment(\.layoutDirection, .rightToLeft).environment(\.locale, Locale(identifier: "ar_LY"))
        .preferredColorScheme(colorScheme)
        .sheet(item: $model.editing) { reminder in ReminderEditor(reminder: reminder).environmentObject(model) }
        .sheet(isPresented: $model.isCreating) { ReminderWizard().environmentObject(model) }
        .sheet(isPresented: Binding(get: { !model.settings.onboardingComplete && !model.isSmoke }, set: { value in if !value { model.updateSettings { $0.onboardingComplete = true } } })) { OnboardingView(model: model) }
        .alert("نحتاج انتباهك", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("حسنًا") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 12) { BrandIcon(size: 48); VStack(alignment: .leading, spacing: 3) { Text("Master").font(Brand.latin(21)); Text("Reminder").font(Brand.latin(15)).foregroundStyle(Brand.muted(scheme)) } }.padding(.top, 20)
            Text("لحظة تطمئن فيها").font(Brand.font(17)).foregroundStyle(Brand.muted(scheme))
            Button { model.newReminder() } label: { Label("تذكير جديد", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(BrandButton())
            VStack(spacing: 6) {
                ForEach(Page.allCases) { page in
                    Button { model.page = page } label: {
                        HStack(spacing: 12) { Image(systemName: page.symbol).frame(width: 20); Text(page.title).font(Brand.font(16)); Spacer(); if model.page == page { Circle().fill(Brand.accent(scheme)).frame(width: 5, height: 5) } }
                            .padding(.horizontal, 14).padding(.vertical, 11)
                            .background(model.page == page ? Brand.sky.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 13))
                            .foregroundStyle(model.page == page ? Brand.accent(scheme) : Brand.muted(scheme))
                    }.buttonStyle(.plain)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 10) {
                Label(model.settings.isPaused(at: Date()) ? "متوقف مؤقتًا" : "معك في الخلفية", systemImage: "circle.fill").font(Brand.font(12)).foregroundStyle(Brand.muted(scheme))
                Text("0.2.0 · محفوظ على جهازك").font(Brand.font(12)).foregroundStyle(Brand.muted(scheme))
            }
        }.padding(20).background(Brand.panel(scheme))
    }
}

struct SectionHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(Brand.font(32))
            Text(subtitle).font(Brand.font(15)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReminderRow: View {
    let reminder: Reminder
    let date: Date
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: reminder.type.symbol).font(.system(size: 20, weight: .light)).foregroundStyle(Brand.accent(scheme))
                .frame(width: 44, height: 44).background(Brand.sky.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title).font(Brand.font(18)).lineLimit(1)
                Text("\(reminder.type.title) · \(reminder.repeatRule.title)").font(Brand.font(13)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(date, style: .time).font(Brand.number(19))
        }.padding(.vertical, 8)
    }
}
