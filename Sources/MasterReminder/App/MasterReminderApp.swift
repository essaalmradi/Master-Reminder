import SwiftUI
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { AppModel.shared.start() }
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
            Text("Master Reminder")
            if let next = model.upcoming.first {
                Text(next.reminder.title)
                Text(next.date, style: .relative)
            } else { Text("لا توجد مواعيد قادمة") }
            Divider()
            Button("إضافة تذكير") { model.newReminder() }.keyboardShortcut("n")
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
