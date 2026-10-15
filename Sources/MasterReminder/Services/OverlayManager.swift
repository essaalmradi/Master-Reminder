import AppKit
import SwiftUI
import ReminderDesign
import ReminderCore

private final class ReminderPanel: NSPanel {
    var dismissAction: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { dismissAction?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { dismissAction?() } else { super.keyDown(with: event) }
    }
}

@MainActor final class OverlayManager {
    private var windows: [ReminderPanel] = []
    private var dismissTimer: Timer?
    private var monitor: Any?
    private var displayObserver: NSObjectProtocol?
    private(set) var current: Occurrence?
    private var onDone: (() -> Void)?
    var windowCount: Int { windows.count }

    func show(_ occurrence: Occurrence, settings: AppSettings, done: @escaping () -> Void, snooze: @escaping (Int) -> Void) {
        close()
        current = occurrence; onDone = done
        let screens = settings.allScreens ? NSScreen.screens : [NSScreen.screens.first].compactMap { $0 }
        for screen in screens {
            let panel = ReminderPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
            panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.isFloatingPanel = true; panel.dismissAction = done
            panel.contentView = NSHostingView(rootView: OverlayView(occurrence: occurrence, opacity: settings.overlayOpacity,
                defaultSnooze: settings.defaultSnooze, done: done, snooze: snooze)
                .environment(\.layoutDirection, .rightToLeft).environment(\.locale, Locale(identifier: "ar")))
            panel.setFrame(screen.frame, display: true)
            panel.alphaValue = 0; panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in context.duration = 0.25; panel.animator().alphaValue = 1 }
            windows.append(panel)
        }
        windows.first?.makeKey()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { done(); return nil }; return event
        }
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { _ in Task { @MainActor in done() } }
        if occurrence.reminder.overlayDuration > 0 {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(occurrence.reminder.overlayDuration), repeats: false) { _ in
                Task { @MainActor in done() }
            }
        }
        Log.overlay.info("Overlay opened on \(self.windows.count) screens")
    }
    func close() {
        dismissTimer?.invalidate(); dismissTimer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }; displayObserver = nil
        for window in windows { window.orderOut(nil); window.close() }
        windows.removeAll(); current = nil; onDone = nil
    }
}

private struct OverlayView: View {
    let occurrence: Occurrence
    let opacity: Double
    let defaultSnooze: Int
    let done: () -> Void
    let snooze: (Int) -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(opacity).ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: occurrence.reminder.type.symbol).font(.system(size: 48, weight: .light)).foregroundStyle(Brand.ocean)
                Text("حان الوقت").font(Brand.font(21)).foregroundStyle(.white.opacity(0.65))
                Text(occurrence.reminder.title).font(Brand.font(42)).multilineTextAlignment(.center)
                if !occurrence.reminder.detail.isEmpty {
                    ScrollView { Text(occurrence.reminder.detail).font(Brand.font(26)).lineSpacing(10).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center).frame(maxWidth: .infinity) }.frame(maxHeight: 330)
                }
                HStack(spacing: 16) {
                    Button("تم", action: done).buttonStyle(.borderedProminent).tint(Brand.ocean).keyboardShortcut(.defaultAction)
                    if occurrence.reminder.snoozeAllowed {
                        Button("تأجيل \(defaultSnooze) دقائق") { snooze(defaultSnooze) }.buttonStyle(.bordered)
                        Menu("خيارات التأجيل") {
                            ForEach([5, 10, 15], id: \.self) { minutes in Button("\(minutes) دقائق") { snooze(minutes) } }
                        }.menuStyle(.borderlessButton).fixedSize()
                    }
                }.controlSize(.large).padding(.top, 12)
                Button("إغلاق · Esc", action: done).buttonStyle(.plain).foregroundStyle(.white.opacity(0.65)).padding(.top, 12)
            }.foregroundStyle(.white).padding(48).frame(maxWidth: 850)
        }.font(Brand.font(17)).preferredColorScheme(.dark)
    }
}
