import SwiftUI
import WidgetKit
import ActivityKit
import AlarmKit
import ReminderCore
import ReminderDesign

struct SpiritualEntry: TimelineEntry { let date: Date }
struct SpiritualProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpiritualEntry { SpiritualEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (SpiritualEntry) -> Void) { completion(SpiritualEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SpiritualEntry>) -> Void) {
        let now = Date()
        let next = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(86400)
        completion(Timeline(entries: [SpiritualEntry(date: now), SpiritualEntry(date: next)], policy: .after(next)))
    }
}
struct DailySpiritualWidget: Widget {
    let kind: SpiritualWidgetKind
    init() { kind = .date }
    init(kind: SpiritualWidgetKind) { self.kind = kind }
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "master-" + kind.rawValue, provider: SpiritualProvider()) { entry in
            SpiritualWidgetView(kind: kind, date: entry.date, compact: true)
                .containerBackground(for: .widget) { Brand.gradient }
                .widgetURL(URL(string: "masterreminder://library"))
        }.configurationDisplayName(kind.title).description("لحظة تطمئن فيها، على شاشتك الرئيسية.")
            .supportedFamilies(kind == .verse ? [.systemMedium, .systemLarge] : [.systemSmall, .systemMedium])
            .contentMarginsDisabled()
    }
}
struct ReminderLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<ReminderAlarmMetadata>.self) { context in
            VStack(alignment: .leading, spacing: 14) {
                HStack { Image(systemName: "bell.badge"); Text(context.attributes.metadata?.title ?? "Master Reminder").font(Brand.font(21)); Spacer() }
                HStack {
                    AlarmCountdown(state: context.state).font(Brand.number(32))
                    Spacer()
                    switch context.state.mode {
                    case .countdown:
                        Button(intent: PauseReminderAlarm(id: context.state.alarmID.uuidString)) { Image(systemName: "pause.fill") }
                    case .paused:
                        Button(intent: ResumeReminderAlarm(id: context.state.alarmID.uuidString)) { Image(systemName: "play.fill") }
                    default: EmptyView()
                    }
                    Button(intent: StopReminderAlarm(id: context.state.alarmID.uuidString)) { Label("إيقاف", systemImage: "stop.fill").font(Brand.font(15)) }
                }.buttonStyle(.bordered).tint(.white)
            }.padding(20).foregroundStyle(.white).activityBackgroundTint(Brand.night).environment(\.layoutDirection, .rightToLeft)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "bell.badge").foregroundStyle(Brand.sky) }
                DynamicIslandExpandedRegion(.trailing) { AlarmCountdown(state: context.state).font(Brand.number(24)) }
                DynamicIslandExpandedRegion(.bottom) { Text(context.attributes.metadata?.title ?? "لحظة ذكر").font(Brand.font(21)).environment(\.layoutDirection, .rightToLeft) }
            } compactLeading: { Image(systemName: "bell.fill").foregroundStyle(Brand.sky) }
              compactTrailing: { AlarmCountdown(state: context.state).frame(maxWidth: 48).font(Brand.number(13)) }
              minimal: { Image(systemName: "bell.fill").foregroundStyle(Brand.sky) }
        }
    }
}
struct AlarmCountdown: View {
    let state: AlarmPresentationState
    var body: some View {
        Group {
            switch state.mode {
            case .countdown(let value):
                Text(timerInterval: Date.now...max(Date.now, value.fireDate), countsDown: true)
            case .paused(let value):
                Text(Duration.seconds(max(0, value.totalCountdownDuration - value.previouslyElapsedDuration)).formatted(.time(pattern: .minuteSecond)))
            default: Text("حان الوقت").font(Brand.font(15))
            }
        }.monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
    }
}
@main struct MasterReminderWidgets: WidgetBundle {
    var body: some Widget {
        DailySpiritualWidget(kind: .date)
        DailySpiritualWidget(kind: .dhikr)
        DailySpiritualWidget(kind: .verse)
        ReminderLiveActivity()
    }
}
