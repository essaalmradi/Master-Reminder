import SwiftUI
import ReminderDesign
import ReminderCore

struct PrayerView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHeading(title: "الصلاة", subtitle: "طرابلس، ليبيا · Africa/Tripoli")
                Label(model.prayerProvider.sourceDescription, systemImage: "info.circle")
                    .font(Brand.font(16)).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                ForEach(model.data.prayers) { entry in
                    PrayerRow(entry: entry, save: model.setPrayer).id("\(entry.id)-\(entry.revision)")
                    Divider()
                }
                Text("بعد الحفظ يتكرر الوقت الذي أدخلته يوميًا. الشروق تذكير اختياري، وليس صلاة مفروضة. لا نطلب موقعك ولا نتصل بخدمة خارجية.")
                    .font(Brand.font(14)).foregroundStyle(.secondary)
            }.padding(32)
        }
    }
}

private struct PrayerRow: View {
    @State var entry: PrayerEntry
    let save: (PrayerEntry) -> Void
    @State private var time = Date()
    @State private var configured = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(entry.name, systemImage: entry.name == "الشروق" ? "sunrise" : "moon.stars").font(Brand.font(18)).frame(width: 100, alignment: .leading)
                if !configured { Text("غير محدد").font(Brand.font(14)).foregroundStyle(.secondary) }
                Spacer()
                Toggle("مفعّل", isOn: $entry.enabled).toggleStyle(.switch)
            }
            HStack {
                DatePicker("الوقت اليدوي", selection: $time, displayedComponents: .hourAndMinute).labelsHidden()
                    .environment(\.timeZone, TimeZone(identifier: "Africa/Tripoli")!)
                    .onChange(of: time) { _ in configured = true }
                Stepper("تعديل: \(entry.adjustment > 0 ? "+" : "")\(entry.adjustment) دقيقة", value: $entry.adjustment, in: -120...120).frame(maxWidth: 250)
                Spacer()
                Button("حفظ الوقت") {
                    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Africa/Tripoli")!
                    entry.hour = cal.component(.hour, from: time); entry.minute = cal.component(.minute, from: time)
                    configured = true; save(entry)
                }.buttonStyle(.bordered)
            }
        }.padding(.vertical, 6)
        .onAppear {
            configured = entry.hour != nil
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Africa/Tripoli")!
            time = cal.date(bySettingHour: entry.hour ?? 12, minute: entry.minute, second: 0, of: Date()) ?? Date()
        }
    }
}
