# Master Reminder

تطبيق macOS أصلي وخفيف لتذكيرات الصلاة والاجتماعات والأذكار والاستراحات والمهام. اللغة عربية واتجاه الواجهة RTL، بخطوط النظام وSF Symbols ودعم مظهر النظام/الفاتح/الداكن.

**الإصدار:** 0.1.0 (1) · **الجهاز المستهدف:** Apple Silicon M3 · **الحد الأدنى:** macOS 13.

## الاستخدام

- افتح التطبيق من Applications. معالج البداية يشرح الإشعارات والتشغيل عند الدخول ويمكن تخطيه.
- أضف تذكيرًا بعنوان ووقت ونوع وتكرار وتنبيه مسبق وصوت وشاشة تنبيه وخيارات تأجيل.
- إغلاق النافذة يبقي التطبيق في شريط القوائم. الإنهاء الكامل من قائمة الجرس → إنهاء Master Reminder.
- جرّب زر **تجربة التذكير بعد 10 ثوانٍ**. التذكير التجريبي مؤقت ولا يُضاف إلى بياناتك المحفوظة.
- الشاشة تغطي الرئيسية أو كل الشاشات، مع زر تم وتأجيل 5/10/15 دقيقة وEscape. لا تُقفل الجهاز ولا تطلب Accessibility أو Screen Recording.
- أوقف التذكيرات 30 دقيقة/ساعة/ساعتين/حتى الغد، أو استأنف الآن.
- قسم الصلاة يستخدم **أوقاتًا يدوية فقط بتوقيت طرابلس**. لا توجد مواقيت افتراضية مفترضة، ويلزم تحديث الأوقات مع تغيّر الأيام. يمكن ضبط كل وقت ±120 دقيقة.

## تثبيت البناء السحابي

1. افتح [GitHub Actions](https://github.com/essaalmradi/Master-Reminder/actions/workflows/build-macos.yml).
2. اختر آخر تشغيل ناجح ثم نزّل Artifact باسم `Master-Reminder-0.1.0-macOS-arm64` (يتطلب الدخول إلى GitHub).
3. فك ZIP وافتح `Master-Reminder-0.1.0.dmg` ثم اسحب **Master Reminder.app** إلى **Applications**.
4. افتح التطبيق واسمح بالإشعارات إذا أردت. لا تحتاج Xcode على جهازك.

التطبيق موقّع بـ Developer ID Application لكنه **غير Notarized، وهذا مقصود للاستخدام الشخصي الحالي**. قد يمنع Gatekeeper الفتح الأول؛ بعد محاولة الفتح استخدم إعدادات النظام → الخصوصية والأمان → فتح على أي حال، عند توفرها. لا تعطل Gatekeeper ولا تمسح إعدادات الأمان على مستوى النظام. سيبقى قرار السماح النهائي لـ macOS وسياسات جهازك.

## البناء وGitHub Actions

الملف `.github/workflows/build-macos.yml` يعمل عند push إلى `main` أو عبر **Run workflow** يدويًا. الخطوات:

1. macOS 15 runner، بناء Release لـ arm64.
2. اختبارات XCTest لوحدة `ReminderCore`.
3. إنشاء `.app` حقيقي وInfo.plist وأيقونة محلية.
4. استيراد P12 إلى keychain مؤقت واكتشاف هوية Developer ID الخاصة بالفريق.
5. توقيع hardened runtime والتحقق عبر `codesign --verify --deep --strict --verbose=2` وقراءة TeamIdentifier.
6. تشغيل اختبار runtime داخل التطبيق الحقيقي: النافذة، Overlay، الحفظ والتعديل والحذف، الإغلاق وإعادة الفتح.
7. إنشاء DMG بـ hdiutil والتحقق منه وحساب SHA-256 ثم رفعه مع أدلة البناء.
8. حذف الشهادة وkeychain المؤقت في نهاية التوقيع وخطوة `always()`.

الـSecrets المطلوبة فقط في Repository → Settings → Secrets and variables → Actions:

| الاسم | المحتوى |
|---|---|
| `MACOS_CERTIFICATE_P12` | ملف P12 مشفّر Base64 ويشمل المفتاح الخاص وشهادة Developer ID Application |
| `MACOS_CERTIFICATE_PASSWORD` | كلمة مرور P12 كنصها الأصلي، بدون Base64 |

الفريق المتوقع: `KTA6FSZK9V`. لا تُحفظ الشهادة أو كلمات المرور في git ولا تُطبع في السجلات. لا يطلب المشروع Apple ID أو 2FA أو مفاتيح App Store Connect. لا ينشئ GitHub Release.

للمطور على جهاز macOS مجهّز بأدوات Swift (ليس مطلوبًا على جهاز المستخدم):

```sh
swift build -c release --arch arm64
swift test --parallel
bash scripts/bundle.sh
```

التوقيع في CI فقط عبر Secrets. يفضّل تشغيل النسخة داخل حزمة `.app` لا executable منفصل، لتعمل هوية الإشعارات وعناصر الدخول كما ينبغي.

## البنية

```text
Sources/
  ReminderCore/
    Models.swift                 # بيانات قابلة لـ Codable والتحقق منها
    ReminderScheduler.swift      # حساب التكرار والمواعيد وخطة الإشعارات
    StorageManager.swift         # JSON محلي، كتابة atomic، إصدار schema
    PrayerTimesProvider.swift    # Provider يدوي + حد تكامل الاجتماعات
  MasterReminder/
    App/                         # نقطة الدخول، MenuBarExtra، AppModel
    Services/                    # الإشعارات والصوت والشاشات وLogin وWake
    Features/                    # اليوم، التذكيرات، الصلاة، الإعدادات والبداية
    UI/                          # واجهة التنقل والمكونات المشتركة
    Resources/
Tests/ReminderCoreTests/
scripts/                         # app bundle والتوقيع وDMG واختبار runtime
```

`ReminderCore` مستقل عن واجهة macOS. `AppModel` ينسّق الخدمات على MainActor ويمنع تداخل عمليات reconciliation. التخزين `Codable + JSON` متوافق مع macOS 13، بدون backend أو مكتبات خارجية.

## موثوقية الجدولة

- UUID ثابت لكل تذكير وrevision جديد عند تعديله. معرّف الحدث يحتوي UUID وrevision وتوقيت حدوثه. pre وdue والتأجيل لها معرّفات منفصلة ومستقرة.
- قبل فتح Overlay يُحفظ claim للحدث على القرص؛ لا يعاد عرضه بعد restart. الضغط المتكرر على التأجيل لا ينشئ تأجيلات متطابقة.
- تحديث Reminder يغيّر revision ويلغي التأجيلات القديمة. إعادة مطابقة قائمة الإشعارات تزيل الطلبات القديمة؛ الحذف يزيل سجلّه والتأجيلات المرتبطة به.
- المصالحة عند التشغيل وWake وتنشيط التطبيق وتغيّر التاريخ/المنطقة الزمنية وتعديل البيانات، إضافة إلى مهلة دقيقة للموعد وفحص كل 30 ثانية. لا نعتمد على Timer واحد.
- مهلة التأخير الافتراضية 15 دقيقة. المتأخر خارجها يسجل missed. التذكيرات الواقعة أثناء pause لا تندفع دفعة واحدة عند الاستئناف.
- تُجهّز أقرب 60 إشعارًا خلال 7 أيام، وتُحدّث النافذة أثناء التشغيل. التكرار اليومي/الأسبوعي يُحسب بتوقيت التقويم للتعامل مع تغيّر التوقيت الصيفي.
- عند Quit تبقى الإشعارات التي سبق جدولتها لدى macOS؛ Overlay والأصوات الطويلة والتجديد المستمر للجدول تحتاج بقاء التطبيق عاملًا. تفعيل Login يساعد على الاستمرارية.
- macOS يتحكم بتسليم الإشعارات أثناء السكون وFocus؛ التطبيق لا يستطيع سحب إشعار تسلّمه النظام بأثر رجعي أثناء انطفائه. عند Wake يطبق التطبيق grace period على Overlay وينظف الإشعارات القديمة.
- التنبيه المسبق يستخدم صوت إشعار النظام. يدير SoundManager صوت الموعد لتجنب ازدواج صوت النظام والتطبيق، حتى لو كان التطبيق يعمل في الخلفية. صوت الملف المخصص ومستواه يعملان داخل التطبيق؛ عند Quit يبقى إشعار الموعد مرئيًا لكن صامتًا. اترك التطبيق عاملًا للحصول على صوت الموعد وOverlay.

## البيانات والخصوصية

البيانات في `~/Library/Application Support/MasterReminder/data.json` وملفات الصوت المستوردة في `Sounds/`. الملف يُكتب atomically بصلاحية 0600. عند تعذّر قراءة ملف موجود لا يُستبدل بملف فارغ؛ تظهر رسالة واضحة وتُوقف الكتابة حتى استيراد نسخة صحيحة أو إعادة الضبط.

التصدير يشمل التذكيرات والإعدادات وسجل الأحداث والتأجيلات والصلاة. ملفات الصوت ليست مضمنة في JSON؛ احتفظ بها منفصلة. الاستيراد يتحقق من schema والأحجام والمعرّفات والمسارات، ويأخذ نسخة احتياطية قبل الاستبدال. الصوت المخصص المفقود يرجع للافتراضي. إعادة الضبط لا تغيّر أذونات النظام أو تسجيل Login.

لا Calendar permission ولا Location permission ولا جمع بيانات أو Analytics. الربط مع Apple/Google Calendar مصدر اختياري مستقبلي خلف `MeetingProvider`. مواقيت الصلاة المحسوبة يمكن إضافتها خلف `PrayerTimesProvider`.

## الاختبارات وحدود التحقق

XCTest يغطي حساب pre/due وgrace وmissed والتكرار وDST والتأجيل ومنع التكرار وتعديل وحذف الجدولة والتخزين واسترجاع البيانات والترتيب والإعدادات والصلاة اليدوية. اختبار runtime يفحص حزمة التطبيق نفسها على macOS runner.

الاختبار السحابي لا يمنح أذونات المستخدم، ولا يسجل التطبيق عند Login، ولا يثبت نجاح الظهور فوق كل تطبيق بملء الشاشة أو على شاشاتك الفعلية. بعد التنزيل جرّب زر الـ10 ثوانٍ، ثم النوم/الاستيقاظ وإعادة التشغيل وشاشة ثانية إن وُجدت. هذه اختبارات تكامل مع جهازك ولا تُستبدل بادعاء نجاح من CI.

## Notarization لاحقًا

المسار المستقبلي: **Sign → Notarize → Staple → DMG/Release**. لا توجد خطوة Notarization أو `notarytool` الآن. عند طلب التوزيع مستقبلًا نضيف المصادقة المناسبة وإرسال الحزمة إلى Apple وفحص قبولها وإرفاق التذكرة قبل التوزيع، دون تغيير بنية التطبيق.

## مراجع المنصة

- [MenuBarExtra — Apple](https://developer.apple.com/documentation/swiftui/menubarextra)
- [SMAppService — Apple](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [UserNotifications — Apple](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter)
- [GitHub hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
