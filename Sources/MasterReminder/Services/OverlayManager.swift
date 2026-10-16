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
    private var spaceObserver: NSObjectProtocol?
    private var rebuild: (() -> Void)?
    private(set) var current: Occurrence?
    var windowCount: Int { windows.count }
    var visibleWindowCount: Int { windows.filter { $0.isVisible && $0.alphaValue > 0.95 && $0.isOnActiveSpace }.count }
    var onScreenWindowCount: Int {
        let numbers = Set(windows.map(\.windowNumber))
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.filter { item in
            guard let number = item[kCGWindowNumber as String] as? Int,
                  let alpha = item[kCGWindowAlpha as String] as? Double else { return false }
            return numbers.contains(number) && alpha > 0.95
        }.count
    }

    @discardableResult func show(_ occurrence: Occurrence, settings: AppSettings, done: @escaping () -> Void, snooze: @escaping (Int) -> Void) -> Bool {
        close()
        rebuild = { [weak self] in self?.buildWindows(occurrence, settings: settings, done: done, snooze: snooze) }
        buildWindows(occurrence, settings: settings, done: done, snooze: snooze)
        guard !windows.isEmpty else { close(); return false }
        current = occurrence
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { done(); return nil }; return event
        }
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.rebuild?() } }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.bringForward() } }
        if occurrence.reminder.overlayDuration > 0 {
            let timer = Timer(timeInterval: TimeInterval(occurrence.reminder.overlayDuration), repeats: false) { _ in Task { @MainActor in done() } }
            dismissTimer = timer; RunLoop.main.add(timer, forMode: .common)
        }
        Log.overlay.info("Overlay presented on \(self.windows.count) screens")
        return true
    }
    private func buildWindows(_ occurrence: Occurrence, settings: AppSettings, done: @escaping () -> Void, snooze: @escaping (Int) -> Void) {
        for window in windows { window.orderOut(nil); window.close() }
        windows.removeAll()
        let screens = settings.allScreens ? NSScreen.screens : [NSScreen.main ?? NSScreen.screens.first].compactMap { $0 }
        NSApp.unhideWithoutActivation()
        for screen in screens {
            let panel = ReminderPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
            panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.isFloatingPanel = true; panel.dismissAction = done
            panel.contentView = NSHostingView(rootView: OverlayView(occurrence: occurrence, opacity: settings.overlayOpacity,
                defaultSnooze: settings.defaultSnooze, done: done, snooze: snooze)
                .environment(\.layoutDirection, .rightToLeft).environment(\.locale, Locale(identifier: "ar_LY")))
            panel.setFrame(screen.frame, display: true)
            // Never depend on an animation completing to make a scheduled alert visible.
            panel.alphaValue = 1; panel.orderFrontRegardless(); windows.append(panel)
        }
        bringForward()
    }
    private func bringForward() { for window in windows { window.orderFrontRegardless() }; windows.first?.makeKey() }
    func snapshot(to url: URL) {
        guard let view = windows.first?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
    func simulateEscapeForSmoke() {
        guard let window = windows.first,
              let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                  windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) else { return }
        NSApp.sendEvent(event)
    }
    func close() {
        dismissTimer?.invalidate(); dismissTimer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }; displayObserver = nil
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }; spaceObserver = nil
        for window in windows { window.orderOut(nil); window.close() }
        windows.removeAll(); current = nil; rebuild = nil
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
                HStack(spacing: 10) {
                    BrandIcon(size: 32)
                    Text("Master Reminder").font(Brand.latin(14))
                    Spacer()
                    Button(action: done) { Image(systemName: "xmark").frame(width: 28, height: 28) }.buttonStyle(.plain).accessibilityLabel("إغلاق التنبيه")
                }.foregroundStyle(.secondary)
                Image(systemName: occurrence.reminder.type.symbol).font(.system(size: 32, weight: .light)).foregroundStyle(Brand.ice)
                Text(occurrence.reminder.title).font(Brand.font(30)).multilineTextAlignment(.center)
                if !occurrence.reminder.detail.isEmpty {
                    ScrollView { Text(occurrence.reminder.detail).font(Brand.font(25)).lineSpacing(10).multilineTextAlignment(.center).frame(maxWidth: .infinity) }.frame(maxHeight: 280)
                }
                HStack(spacing: 12) {
                    Button("تم", action: done).buttonStyle(BrandButton()).keyboardShortcut(.defaultAction).accessibilityIdentifier("reminder.done")
                    if occurrence.reminder.snoozeAllowed {
                        Button("بعد \(defaultSnooze) دقائق") { snooze(defaultSnooze) }.buttonStyle(.bordered).controlSize(.large).accessibilityIdentifier("reminder.snooze")
                        Menu { ForEach([5, 10, 15], id: \.self) { minutes in Button("\(minutes) دقائق") { snooze(minutes) } } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                    }
                }
                Text("لحظة لك · اضغط Esc للإغلاق").font(Brand.font(12)).foregroundStyle(.secondary)
            }.padding(32).frame(maxWidth: 620)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.14), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 40, y: 16)
        }.font(Brand.font(16)).foregroundStyle(.white).preferredColorScheme(.dark)
    }
}
