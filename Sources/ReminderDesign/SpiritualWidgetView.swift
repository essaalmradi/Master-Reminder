import SwiftUI
import ReminderCore

public enum SpiritualWidgetKind: String, CaseIterable, Identifiable, Codable {
    case date, dhikr, verse, next, year
    public var id: String { rawValue }
    public var title: String {
        switch self { case .date: return "اليوم والتاريخ"; case .dhikr: return "ذكر اليوم"; case .verse: return "آية للتدبر"; case .next: return "التذكير القادم"; case .year: return "رحلة العام" }
    }
    public var symbol: String {
        switch self { case .date: return "calendar"; case .dhikr: return "quote.opening"; case .verse: return "book.closed"; case .next: return "bell"; case .year: return "circle.grid.3x3" }
    }
    public var isWide: Bool { self == .verse || self == .year }
}

public struct SpiritualWidgetView: View {
    let kind: SpiritualWidgetKind
    let date: Date
    let nextTitle: String?
    let nextDate: Date?
    let compact: Bool
    public init(kind: SpiritualWidgetKind, date: Date = Date(), nextTitle: String? = nil, nextDate: Date? = nil, compact: Bool = false) {
        self.kind = kind; self.date = date; self.nextTitle = nextTitle; self.nextDate = nextDate; self.compact = compact
    }
    private func formatted(_ pattern: String, calendar: Calendar.Identifier = .gregorian) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ar_LY"); f.calendar = Calendar(identifier: calendar); f.dateFormat = pattern; return f.string(from: date)
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 14) {
            HStack {
                Label(kind.title, systemImage: kind.symbol).font(Brand.font(compact ? 12 : 14)).foregroundStyle(Brand.ice)
                Spacer()
                Image(systemName: "sparkle").font(.caption).foregroundStyle(Brand.sky.opacity(0.6))
            }
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
            if !compact {
                HStack { Text("Master Reminder").font(Brand.latin(10)); Spacer(); Text("لحظة تطمئن فيها").font(Brand.font(11)) }.foregroundStyle(.white.opacity(0.5))
            }
        }.padding(compact ? 16 : 24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Brand.night.opacity(0.94))

            .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.12), lineWidth: 1))
            .environment(\.layoutDirection, .rightToLeft)
    }
    @ViewBuilder private var content: some View {
        switch kind {
        case .date:
            VStack(alignment: .leading, spacing: 6) {
                Text(formatted("EEEE")).font(Brand.font(compact ? 36 : 54)).minimumScaleFactor(0.65).lineLimit(1)
                Text(formatted("d MMMM yyyy")).font(Brand.font(compact ? 14 : 18))
                Text(formatted("d MMMM yyyy", calendar: .islamicUmmAlQura)).font(Brand.font(compact ? 12 : 14)).foregroundStyle(Brand.ice)
            }
        case .dhikr, .verse:
            let entry = kind == .verse ? SpiritualLibrary.shared.dailyVerse(at: date) : SpiritualLibrary.shared.dailyDhikr(at: date)
            VStack(alignment: .leading, spacing: 12) {
                Text(entry?.text ?? "المكتبة غير متاحة").font(Brand.font(compact ? 18 : (kind == .verse ? 26 : 21)))
                    .lineSpacing(compact ? 3 : 7).minimumScaleFactor(0.6).multilineTextAlignment(.leading)
                Text(entry?.reference ?? "").font(Brand.font(compact ? 10 : 12)).foregroundStyle(Brand.ice).lineLimit(2)
            }
        case .next:
            VStack(alignment: .leading, spacing: 8) {
                Text(nextTitle ?? "وقت لذكر جديد").font(Brand.font(compact ? 20 : 25)).lineLimit(2)
                if let nextDate {
                    Text(nextDate, style: .time).font(Brand.number(compact ? 28 : 40))
                    Text(nextDate, style: .relative).font(Brand.font(14)).foregroundStyle(Brand.ice)
                } else { Text("أضف أول تذكير من التطبيق").font(Brand.font(15)).foregroundStyle(Brand.ice) }
            }
        case .year:
            let cal = Calendar.current
            let days = cal.range(of: .day, in: .year, for: date)?.count ?? 365
            let day = cal.ordinality(of: .day, in: .year, for: date) ?? 1
            VStack(spacing: 14) {
                HStack { Text("\(cal.component(.year, from: date))").font(Brand.number(24)); Spacer(); Text("\(Int(Double(day) / Double(days) * 100))٪").font(Brand.number(24)) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: compact ? 26 : 31), spacing: 5) {
                    ForEach(1...days, id: \.self) { index in Circle().fill(index <= day ? Brand.ice : .white.opacity(0.12)).frame(height: compact ? 3 : 5) }
                }
            }
        }
    }
}
