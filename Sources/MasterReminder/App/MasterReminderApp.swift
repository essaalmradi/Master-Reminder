import SwiftUI
import ReminderDesign
import AppKit
import Carbon

enum LaunchContext {
    static func isBackgroundLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event, event.eventID == kAEOpenApplication,
              let reason = event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue else { return false }
        return reason == keyAELaunchedAsLogInItem || reason == keyAELaunchedAsServiceItem
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start(isBackgroundLaunch: LaunchContext.isBackgroundLaunch(NSAppleEventManager.shared().currentAppleEvent))
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppModel.shared.openWindow(); return true
    }
}

@main struct MasterReminderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel.shared
    var body: some Scene {
        MenuBarExtra("Master Reminder", systemImage: model.settings.isPaused(at: Date()) ? "bell.slash" : "bell") {
            Text("Master Reminder \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
            if let next = model.upcoming.first {
                Text(next.reminder.title)
                Text(next.date, style: .relative)
            } else { Text("لا توجد مواعيد قادمة") }
            Divider()
            Button("إضافة تذكير") { model.newReminder() }.keyboardShortcut("n")
            Button("الويدجت على المكتب") { model.openWindow(page: .widgets) }
            Button("فتح التطبيق") { model.openWindow() }
            Button("تجربة التذكير بعد 10 ثوانٍ") { model.testReminder() }
            Divider()
            if model.settings.isPaused(at: Date()) { Button("استئناف التذكيرات") { model.resume() } }
            else { PauseMenu(model: model) }
            Button("الإعدادات") { model.openWindow(page: .settings) }.keyboardShortcut(",")
            Divider()
            Button("إنهاء Master Reminder") { model.quit() }.keyboardShortcut("q")
        }
    }
}

struct PauseMenu: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Menu("إيقاف مؤقت") {
            Button("30 دقيقة") { model.pause(minutes: 30) }
            Button("ساعة") { model.pause(minutes: 60) }
            Button("ساعتان") { model.pause(minutes: 120) }
            Button("حتى الغد") { model.pause(minutes: nil) }
        }
    }
}
