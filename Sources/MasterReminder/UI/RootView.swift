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
            sidebar.frame(width: 202).padding(12)
            VStack(spacing: 0) {
                if let notice = model.notice {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle")
                        Text(notice).font(Brand.font(13))
                        Spacer()
                        Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    }.padding(12).background(Brand.sky.opacity(0.09), in: RoundedRectangle(cornerRadius: 12)).padding([.horizontal, .top], 24)
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
            }
        }
        .background {
            ZStack {
                Brand.page(scheme)
                LinearGradient(colors: [Brand.sky.opacity(scheme == .dark ? 0.06 : 0.07), .clear, Brand.ice.opacity(0.035)], startPoint: .topTrailing, endPoint: .bottomLeading)
            }
        }
        .font(Brand.font(15)).foregroundStyle(Brand.ink(scheme)).tint(Brand.accent(scheme))
        .environment(\.layoutDirection, .rightToLeft).environment(\.locale, Locale(identifier: "ar_LY"))
        .preferredColorScheme(colorScheme)
        .sheet(item: $model.editing) { reminder in ReminderEditor(reminder: reminder).environmentObject(model) }
        .sheet(isPresented: $model.isCreating) { ReminderWizard().environmentObject(model) }
        .sheet(isPresented: Binding(get: { !model.settings.onboardingComplete && !model.isSmoke }, set: { value in if !value { model.updateSettings { $0.onboardingComplete = true } } })) { OnboardingView(model: model) }
        .alert("نحتاج انتباهك", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("حسنًا") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                BrandIcon(size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Master").font(Brand.latin(17))
                    Text("Reminder").font(Brand.latin(12)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 8).padding(.top, 10)
            VStack(spacing: 4) {
                ForEach(Page.allCases.filter { $0 != .settings }) { page in navItem(page) }
            }
            Spacer(minLength: 16)
            Button { model.newReminder() } label: { Label("تذكير جديد", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(BrandButton()).accessibilityIdentifier("newReminder")
            VStack(spacing: 12) {
                Divider().opacity(0.45)
                navItem(.settings)
                HStack(spacing: 7) {
                    Circle().fill(model.settings.isPaused(at: Date()) ? Color.secondary : Brand.accent(scheme)).frame(width: 5, height: 5)
                    Text(model.settings.isPaused(at: Date()) ? "متوقف مؤقتًا" : "يعمل في الخلفية").font(Brand.font(11)).foregroundStyle(.secondary)
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "").font(Brand.number(10)).foregroundStyle(.tertiary)
                }.padding(.horizontal, 8)
            }
        }.padding(14).brandGlass(radius: 22)
    }
    private func navItem(_ page: Page) -> some View {
        Button { model.page = page } label: {
            HStack(spacing: 11) {
                Image(systemName: page.symbol).font(.system(size: 16, weight: .regular)).frame(width: 20)
                Text(page.title).font(Brand.font(15))
                Spacer()
            }.padding(.horizontal, 12).padding(.vertical, 11)
                .foregroundStyle(model.page == page ? Brand.accent(scheme) : Brand.ink(scheme).opacity(0.75))
                .background(model.page == page ? Brand.sky.opacity(scheme == .dark ? 0.13 : 0.12) : .clear, in: RoundedRectangle(cornerRadius: 11))
                .contentShape(RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain).accessibilityIdentifier("page.\(page.rawValue)")
    }
}

struct SectionHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(Brand.font(27))
            Text(subtitle).font(Brand.font(13)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReminderRow: View {
    let reminder: Reminder
    let date: Date
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: reminder.type.symbol).font(.system(size: 18, weight: .light)).foregroundStyle(Brand.accent(scheme))
                .frame(width: 34, height: 34).background(Brand.sky.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(reminder.title).font(Brand.font(16)).lineLimit(1)
                Text("\(reminder.type.title) · \(reminder.repeatRule.title)").font(Brand.font(12)).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(date, style: .time).font(Brand.number(17))
                if !Calendar.current.isDateInToday(date) { Text(date, format: .dateTime.day().month(.abbreviated)).font(Brand.font(11)).foregroundStyle(.secondary) }
            }
        }.padding(.vertical, 8)
    }
}
