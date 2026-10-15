import AppKit

@MainActor final class WakeObserver {
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    init(action: @escaping () -> Void, sleep: @escaping () -> Void) {
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification, action)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification, action)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification, sleep)
        observe(.default, NSApplication.didBecomeActiveNotification, action)
        observe(.default, .NSSystemTimeZoneDidChange, action)
        observe(.default, .NSCalendarDayChanged, action)
        observe(.default, NSNotification.Name("NSSystemClockDidChangeNotification"), action)
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { @MainActor in action() }
        }
        observers.append((center, token))
    }
    deinit { for (center, token) in observers { center.removeObserver(token) } }
}
