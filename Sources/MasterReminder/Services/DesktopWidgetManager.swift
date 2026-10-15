import AppKit
import SwiftUI
import ReminderCore
import ReminderDesign

private final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class DesktopWidgetManager: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var enabled: Set<SpiritualWidgetKind> = []
    @Published private(set) var floatOnTop = false
    private var panels: [SpiritualWidgetKind: NSPanel] = [:]
    private var model: AppModel?
    private var defaults: UserDefaults { model?.isSmoke == true ? UserDefaults(suiteName: "MasterReminder-SmokeWidgets")! : .standard }
    var count: Int { panels.count }
    func restore(model: AppModel) {
        self.model = model
        floatOnTop = defaults.bool(forKey: "widgets-floating")
        let saved = defaults.stringArray(forKey: "desktop-widgets-v1") ?? []
        for value in saved { if let kind = SpiritualWidgetKind(rawValue: value) { show(kind) } }
    }
    func set(_ kind: SpiritualWidgetKind, visible: Bool) {
        if visible { show(kind) } else { panels.removeValue(forKey: kind)?.close(); enabled.remove(kind) }
        defaults.set(enabled.map(\.rawValue).sorted(), forKey: "desktop-widgets-v1")
    }
    func setFloating(_ value: Bool) {
        floatOnTop = value; defaults.set(value, forKey: "widgets-floating")
        for panel in panels.values { panel.level = value ? .floating : .normal }
    }
    private func show(_ kind: SpiritualWidgetKind) {
        guard panels[kind] == nil, let model else { return }
        let width: CGFloat = kind.isWide ? 580 : 280
        let height: CGFloat = kind.isWide ? 250 : 280
        let panel = DesktopPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.isMovableByWindowBackground = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.level = floatOnTop ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.identifier = NSUserInterfaceItemIdentifier(kind.rawValue); panel.delegate = self
        panel.contentView = NSHostingView(rootView: DesktopWidgetContainer(kind: kind, model: model, manager: self))
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let i = CGFloat(SpiritualWidgetKind.allCases.firstIndex(of: kind) ?? 0)
        let suggested = NSPoint(x: screen.maxX - width - 28 - (i.truncatingRemainder(dividingBy: 2)) * 30,
                                y: screen.maxY - height - 24 - i * 36)
        panel.setFrameOrigin(suggested)
        if let saved = defaults.string(forKey: "widget-frame-\(kind.rawValue)") {
            let rect = NSRectFromString(saved)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) { panel.setFrameOrigin(rect.origin) }
        }
        panels[kind] = panel; enabled.insert(kind); panel.orderFrontRegardless()
    }
    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let id = window.identifier?.rawValue else { return }
        defaults.set(NSStringFromRect(window.frame), forKey: "widget-frame-\(id)")
    }
    func closeAll() { for panel in panels.values { panel.close() }; panels.removeAll(); enabled.removeAll() }
}

private struct DesktopWidgetContainer: View {
    let kind: SpiritualWidgetKind
    @ObservedObject var model: AppModel
    @ObservedObject var manager: DesktopWidgetManager
    @State private var hover = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            SpiritualWidgetView(kind: kind, date: context.date, nextTitle: model.upcoming.first?.reminder.title, nextDate: model.upcoming.first?.date)
        }.overlay(alignment: .topLeading) {
            if hover {
                HStack(spacing: 8) {
                    Button { manager.set(kind, visible: false) } label: { Image(systemName: "xmark.circle.fill") }.help("إخفاء الويدجت")
                    Button { model.openWindow(page: kind == .next ? .reminders : .library) } label: { Image(systemName: "arrow.up.forward.circle.fill") }.help("فتح التطبيق")
                }.buttonStyle(.plain).font(.system(size: 19)).foregroundStyle(.white.opacity(0.8)).padding(10)
            }
        }.onHover { hover = $0 }
        .contextMenu {
            Button("فتح التطبيق") { model.openWindow() }
            Button(manager.floatOnTop ? "عرض عادي على المكتب" : "إبقاء فوق النوافذ") { manager.setFloating(!manager.floatOnTop) }
            Button("إخفاء الويدجت") { manager.set(kind, visible: false) }
        }
    }
}
