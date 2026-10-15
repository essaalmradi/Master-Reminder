import SwiftUI
import ReminderCore

struct RootView: View {
    @EnvironmentObject var model: AppModel
    private var colorScheme: ColorScheme? {
        switch model.settings.appearance { case .system: return nil; case .dark: return .dark; case .light: return .light }
    }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "bell.badge").font(.system(size: 27, weight: .light)).foregroundStyle(.teal)
                    Text("Master\nReminder").font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text("مساحة لوقتك").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.top, 22)
                VStack(spacing: 7) {
                    ForEach(Page.allCases) { page in
                        Button { model.page = page } label: {
                            Label(page.title, systemImage: page.symbol)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(11)
                                .background(model.page == page ? Color.teal.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 9))
                                .foregroundStyle(model.page == page ? Color.teal : Color.primary)
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
                Label(model.settings.isPaused(at: Date()) ? "متوقف مؤقتًا" : "معك في الخلفية", systemImage: "circle.fill")
                    .font(.caption).foregroundStyle(model.settings.isPaused(at: Date()) ? Color.orange : Color.secondary)
                Text("0.1.0 · على جهازك فقط").font(.caption2).foregroundStyle(.tertiary)
            }.padding(20).navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 240)
        } detail: {
            VStack(spacing: 0) {
                if let notice = model.notice {
                    HStack { Text(notice).font(.callout); Spacer(); Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                        .padding(12).background(Color.teal.opacity(0.1))
                }
                Group {
                    switch model.page {
                    case .dashboard: DashboardView()
                    case .reminders: RemindersView()
                    case .prayer: PrayerView()
                    case .settings: SettingsView(model: model)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .tint(.teal).environment(\.layoutDirection, .rightToLeft).environment(\.locale, Locale(identifier: "ar"))
        .preferredColorScheme(colorScheme)
        .sheet(item: $model.editing) { reminder in ReminderEditor(reminder: reminder).environmentObject(model) }
        .sheet(isPresented: Binding(get: { !model.settings.onboardingComplete && !model.isSmoke }, set: { value in if !value { model.updateSettings { $0.onboardingComplete = true } } })) {
            OnboardingView(model: model)
        }
        .alert("نحتاج انتباهك", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("حسنًا") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

struct SectionHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 30, weight: .semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReminderRow: View {
    let reminder: Reminder
    let date: Date
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: reminder.type.symbol).font(.title3).foregroundStyle(.teal)
                .frame(width: 42, height: 42).background(Color.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(reminder.title).font(.headline)
                Text("\(reminder.type.title) · \(reminder.repeatRule.title)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(date, style: .time).font(.system(.title3, design: .rounded)).monospacedDigit()
        }.padding(.vertical, 8)
    }
}
