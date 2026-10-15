import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @State private var step = 0
    private let titles = ["مرحبًا بك في\nMaster Reminder", "توقف في الوقت المناسب", "قبل الموعد بلحظات", "معك من بداية اليوم", "لنبدأ بموعد واحد"]
    private let descriptions = [
        "مساعد هادئ لصلاتك، عملك، والوقت الذي تحتاجه لنفسك.",
        "تنبيه بسيط قبل الموعد، وشاشة واضحة عند حلوله. يمكنك إغلاقها أو تأجيلها دائمًا.",
        "Master Reminder يحتاج الإشعارات لتنبيهك قبل المواعيد.",
        "يمكن تشغيل التطبيق تلقائيًا عند الدخول. انقله إلى Applications قبل تفعيل هذا الخيار.",
        "أضف أول تذكير، أو جرّب التنبيه لتتعرف على التجربة."
    ]
    private let icons = ["bell.badge", "clock", "app.badge", "power", "plus.circle"]
    var body: some View {
        VStack(spacing: 26) {
            Image(systemName: icons[step]).font(.system(size: 54, weight: .ultraLight)).foregroundStyle(.teal)
            Text(titles[step]).font(.system(size: 31, weight: .semibold)).multilineTextAlignment(.center)
            Text(descriptions[step]).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            if step == 2 { Button("السماح بالإشعارات") { model.allowNotifications() }.buttonStyle(.borderedProminent) }
            if step == 3 { Button(model.login.enabled ? "التشغيل عند الدخول مفعّل" : "تفعيل التشغيل عند الدخول") { model.setLogin(true) }.disabled(model.login.enabled) }
            HStack(spacing: 7) { ForEach(0..<5) { index in Capsule().fill(index == step ? Color.teal : Color.secondary.opacity(0.2)).frame(width: index == step ? 22 : 7, height: 6) } }.padding(.top, 12)
            HStack {
                Button("لاحقًا") { model.updateSettings { $0.onboardingComplete = true } }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                if step > 0 { Button("رجوع") { step -= 1 } }
                Button(step == 4 ? "إضافة أول تذكير" : "متابعة") {
                    if step < 4 { step += 1 }
                    else {
                        model.updateSettings { $0.onboardingComplete = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.newReminder() }
                    }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(44).frame(width: 530, height: 460).environment(\.layoutDirection, .rightToLeft).tint(.teal)
    }
}
