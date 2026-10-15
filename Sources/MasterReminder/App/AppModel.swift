import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import ReminderCore
import ReminderDesign

enum Page: String, CaseIterable, Identifiable {
    case dashboard, reminders, library, tasbih, widgets, prayer, settings
    var id: String { rawValue }
    var title: String {
        switch self { case .dashboard: return "اليوم"; case .reminders: return "التذكيرات"; case .prayer: return "الصلاة"; case .library: return "المكتبة"; case .tasbih: return "التسبيح"; case .widgets: return "الويدجت"; case .settings: return "الإعدادات" }
    }
    var symbol: String {
        switch self { case .dashboard: return "square.grid.2x2"; case .reminders: return "bell"; case .prayer: return "moon.stars"; case .library: return "books.vertical"; case .tasbih: return "circle.dotted"; case .widgets: return "rectangle.3.group"; case .settings: return "gearshape" }
    }
}

@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published private(set) var data = AppData()
    @Published private(set) var upcoming: [Occurrence] = []
    @Published var page: Page = .dashboard
    @Published var editing: Reminder?
    @Published var isCreating = false
    let widgets = DesktopWidgetManager()
    @Published var error: String?
    @Published var notice: String?
    let notifications = NotificationManager()
    let login = LoginItemManager()
    let overlay = OverlayManager()
    let sounds: SoundManager
    let storage: StorageManager
    let prayerProvider = ManualPrayerTimesProvider()
    private var mainWindow: NSWindow?
    private var timer: Timer?
    private var deadline: Timer?
    private var wake: WakeObserver?
    private var started = false
    private var reconciling = false
    private var dirty = false
    private var canPersist = true
    private var temporary: [Reminder] = []
    private var transientLedger: [String: EventRecord] = [:]
    private var activeQueue: [Occurrence] = []
    private var recent: [String: Occurrence] = [:]
    var isSmoke: Bool { ProcessInfo.processInfo.arguments.contains("--smoke-test") }
    var settings: AppSettings { data.settings }
    var allReminders: [Reminder] { data.reminders + prayerProvider.reminders(entries: data.prayers, settings: settings) + temporary }
    var ledger: [String: EventRecord] { data.ledger.merging(transientLedger) { _, new in new } }

    private init() {
        let fm = FileManager.default
        let base: URL
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            base = fm.temporaryDirectory.appendingPathComponent("MasterReminder-Smoke")
        } else {
            base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MasterReminder")
        }
        storage = StorageManager(url: base.appendingPathComponent("data.json"))
        sounds = SoundManager(directory: base.appendingPathComponent("Sounds"))
        do { data = try storage.load() }
        catch { canPersist = false; self.error = "تعذّر قراءة البيانات. لم نغيّر الملف الأصلي. يمكنك استيراد نسخة سليمة أو إعادة ضبط البيانات. " + error.localizedDescription; Log.storage.error("Storage load failed; writes blocked") }
    }

    func start() {
        guard !started else { return }; started = true
        Brand.registerFonts()
        widgets.restore(model: self)
        notifications.isPaused = { [weak self] in self?.settings.isPaused(at: Date()) ?? false }
        notifications.shouldPlayForegroundSound = { [weak self] in self?.settings.soundEnabled ?? true }
        notifications.onAction = { [weak self] id, action in self?.notificationAction(id: id, action: action) }
        wake = WakeObserver(action: { [weak self] in self?.login.refresh(); self?.reconcile() }, sleep: { [weak self] in self?.prepareForSleep() })
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in Task { @MainActor in self?.reconcile() } }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        reconcile()
        if !settings.onboardingComplete || isSmoke { openWindow() }
        if isSmoke { Task { await runSmokeTest() } }
        Log.app.info("Application started")
    }

    @discardableResult private func persist() -> Bool {
        guard canPersist else { return false }
        do { try storage.save(data); return true }
        catch { report("تعذّر حفظ البيانات", error); Log.storage.error("Storage write failed"); return false }
    }
    private func transaction(_ update: (inout AppData) -> Void) -> Bool {
        guard canPersist else { error = "البيانات محمية بعد فشل القراءة. استورد نسخة سليمة أو أعد الضبط من الإعدادات."; return false }
        let old = data; update(&data)
        if persist() { return true }
        data = old; return false
    }
    func report(_ message: String, _ failure: Error) { error = message + ": " + failure.localizedDescription }
    func newReminder() { isCreating = true; openWindow() }
    func reminderFromLibrary(_ entry: LibraryEntry) { editing = entry.reminder; openWindow() }
    func saveReminder(_ reminder: Reminder) {
        do {
            let valid = try reminder.validated()
            guard transaction({ $0.upsert(valid) }) else { return }
            invalidate(reminder.id); editing = nil; isCreating = false; reconcile()
        } catch { report("راجع بيانات التذكير", error) }
    }
    func deleteReminder(_ reminder: Reminder) {
        guard transaction({ $0.delete(reminder.id) }) else { return }
        invalidate(reminder.id); reconcile()
    }
    func updateSettings(_ update: (inout AppSettings) -> Void) {
        let old = settings
        guard transaction({ update(&$0.settings); $0.settings.normalize() }) else { return }
        if old.soundEnabled != settings.soundEnabled || old.volume != settings.volume { sounds.stop() }
        if settings.isPaused(at: Date()) || !settings.overlayEnabled { overlay.close(); sounds.stop(); activeQueue.removeAll() }
        // Changes to global sound require replacement of pending contents even with the same IDs.
        if old.soundEnabled != settings.soundEnabled { notifications.clearAll() }
        reconcile()
    }
    func setting<T>(_ key: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { self.settings[keyPath: key] }, set: { value in self.updateSettings { $0[keyPath: key] = value } })
    }
    func setPrayer(_ entry: PrayerEntry) {
        guard transaction({ data in
            if let index = data.prayers.firstIndex(where: { $0.id == entry.id }) {
                var value = entry; value.revision = data.prayers[index].revision + 1
                data.prayers[index] = value
                data.snoozes.removeAll { $0.reminder.id == entry.id }
            }
        }) else { return }
        invalidate(entry.id); reconcile()
    }
    private func invalidate(_ id: UUID) {
        activeQueue.removeAll { $0.reminder.id == id }
        recent = recent.filter { $0.value.reminder.id != id }
        if overlay.current?.reminder.id == id { overlay.close(); sounds.stop(); presentNext() }
    }
    func pause(minutes: Int?) {
        let until = minutes.map { Date().addingTimeInterval(TimeInterval($0 * 60)) }
            ?? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
        updateSettings { $0.pausedUntil = until }
    }
    func resume() { updateSettings { $0.suppressedThrough = Date(); $0.pausedUntil = nil } }
    func reconcile() {
        if reconciling { dirty = true; return }
        reconciling = true
        Task { @MainActor in
            repeat {
                dirty = false
                await self.reconcileOnce()
            } while dirty
            reconciling = false
        }
    }
    private func reconcileOnce() async {
        let now = Date()
        if let pause = settings.pausedUntil, pause <= now {
            // Reminders inside a pause never burst on resume or restart.
            data.lastReconciled = max(data.lastReconciled ?? pause, pause)
            data.settings.suppressedThrough = pause
            data.settings.pausedUntil = nil
        }
        let graceStart = now.addingTimeInterval(TimeInterval(-settings.graceMinutes * 60))
        let from = max(min(data.lastReconciled ?? graceStart, graceStart), now.addingTimeInterval(-7 * 86400))
        var due = allReminders.flatMap { reminder -> [Occurrence] in
            if reminder.repeatRule == .once && reminder.date <= now { return [Occurrence(reminder: reminder, date: reminder.date)] }
            return ReminderScheduler.occurrences(for: reminder, from: from, through: now)
        } + data.snoozes.filter { $0.date <= now }.map(\.occurrence)
        // Preserve explicit pause boundary even if the app was quit while paused.
        due.sort { $0.date < $1.date }
        for occurrence in due {
            recent[occurrence.id] = occurrence
            let decision = ReminderScheduler.decision(occurrence, now: now, settings: settings, ledger: ledger)
            let status: EventStatus
            switch decision {
            case .future, .duplicate: continue
            case .fire: status = .fired
            case .missed: status = .missed
            case .paused: status = .paused
            }
            if occurrence.reminder.isTemporary {
                transientLedger[occurrence.id] = EventRecord(status, at: now)
            } else {
                guard transaction({ $0.ledger[occurrence.id] = EventRecord(status, at: now) }) else { continue }
            }
            if status == .fired { activeQueue.append(occurrence) }
        }
        data.lastReconciled = now
        data.ledger = data.ledger.filter { $0.value.date > now.addingTimeInterval(-35 * 86400) }
        // One-off reminders stay consumed even after ledger pruning because they are then outside grace.
        data.snoozes.removeAll { $0.date < now.addingTimeInterval(-86400) }
        temporary.removeAll { $0.date < now.addingTimeInterval(-3600) }
        recent = recent.filter { $0.value.date > now.addingTimeInterval(-86400) }
        _ = persist()
        upcoming = ReminderScheduler.upcoming(reminders: allReminders, snoozes: data.snoozes, now: now, ledger: ledger)
        for item in upcoming { recent[item.id] = item }
        presentNext()
        scheduleDeadline(now: now)
        let plan = ReminderScheduler.notificationPlan(occurrences: upcoming, now: now, settings: settings)
        let prefixes = Set(allReminders.map { "mr-\($0.id.uuidString)-r\($0.revision)-" })
        do { try await notifications.sync(plan, settings: settings, validPrefixes: prefixes) }
        catch { report("تعذّرت جدولة بعض الإشعارات؛ سنعيد المحاولة", error); Log.scheduler.error("Notification reconcile failed") }
    }
    private func scheduleDeadline(now: Date) {
        deadline?.invalidate()
        let candidates = [upcoming.first?.date, settings.pausedUntil].compactMap { $0 }.filter { $0 > now }
        guard let next = candidates.min() else { return }
        deadline = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in Task { @MainActor in self?.reconcile() } }
        if let deadline { RunLoop.main.add(deadline, forMode: .common) }
    }
    private func presentNext() {
        guard overlay.current == nil, !settings.isPaused(at: Date()) else { return }
        while !activeQueue.isEmpty {
            let occurrence = activeQueue.removeFirst()
            guard Date().timeIntervalSince(occurrence.date) <= TimeInterval(settings.graceMinutes * 60) else { continue }
            do { try sounds.play(occurrence.reminder, settings: settings) } catch { report("تعذّر تشغيل الصوت", error) }
            if settings.overlayEnabled && occurrence.reminder.overlay {
                overlay.show(occurrence, settings: settings,
                    done: { [weak self] in self?.finish(occurrence) },
                    snooze: { [weak self] minutes in self?.snooze(occurrence, minutes: minutes) })
                break
            }
        }
    }
    func finish(_ occurrence: Occurrence) {
        if occurrence.reminder.isTemporary { transientLedger[occurrence.id] = EventRecord(.dismissed, at: Date()) }
        else { guard transaction({ $0.ledger[occurrence.id] = EventRecord(.dismissed, at: Date()) }) else { overlay.close(); sounds.stop(); return } }
        notifications.clearOccurrence(occurrence.id)
        activeQueue.removeAll { $0.id == occurrence.id }
        if overlay.current?.id == occurrence.id { overlay.close(); sounds.stop() }
        presentNext(); reconcile()
    }
    func snooze(_ occurrence: Occurrence, minutes: Int) {
        guard occurrence.reminder.snoozeAllowed else { return }
        if occurrence.reminder.isTemporary {
            guard transientLedger[occurrence.id]?.status != .snoozed else { return }
            transientLedger[occurrence.id] = EventRecord(.snoozed, at: Date())
            var value = occurrence.reminder; value.id = UUID(); value.date = Date().addingTimeInterval(TimeInterval(minutes * 60)); value.preAlertMinutes = 0
            temporary.append(value)
        } else {
            guard transaction({ _ = $0.snooze(occurrence, now: Date(), minutes: minutes) }) else { return }
        }
        notifications.clearOccurrence(occurrence.id)
        activeQueue.removeAll { $0.id == occurrence.id }
        if overlay.current?.id == occurrence.id { overlay.close(); sounds.stop() }
        presentNext(); reconcile()
    }
    private func notificationAction(id: String, action: String) {
        if action == UNNotificationDefaultActionIdentifier { openWindow(); return }
        let now = Date()
        let restored = data.snoozes.map(\.occurrence) + allReminders.flatMap {
            ReminderScheduler.occurrences(for: $0, from: now.addingTimeInterval(TimeInterval(-settings.graceMinutes * 60)), through: now)
        }
        guard let occurrence = recent[id] ?? restored.first(where: { $0.id == id }), now.timeIntervalSince(occurrence.date) <= TimeInterval(settings.graceMinutes * 60) else { return }
        if action == "done" { finish(occurrence) }
        else if action.hasPrefix("snooze-"), let minutes = Int(action.dropFirst(7)) { snooze(occurrence, minutes: minutes) }
    }
    private func prepareForSleep() {
        sounds.stop(); overlay.close(); activeQueue.removeAll(); _ = persist()
    }
    func testReminder() {
        var value = Reminder(title: "لحظة تطمئن فيها", date: Date().addingTimeInterval(10))
        value.detail = "سبحان الله وبحمده"
        value.sound = .dhikr
        value.type = .dhikr; value.preAlertMinutes = 0; value.isTemporary = true
        temporary.append(value); notice = settings.isPaused(at: Date()) ? "التذكيرات متوقفة مؤقتًا. استأنفها لتجربة التنبيه." : "سيظهر التذكير التجريبي بعد 10 ثوانٍ."
        reconcile()
    }
    func testOverlay() {
        guard !settings.isPaused(at: Date()) else { notice = "استأنف التذكيرات أولًا."; return }
        var value = Reminder(title: "لحظة ذكر", date: Date()); value.detail = SpiritualLibrary.shared.dailyVerse()?.text ?? "سبحان الله وبحمده"
        value.type = .breakTime; value.isTemporary = true
        let occurrence = Occurrence(reminder: value, date: value.date)
        activeQueue.append(occurrence); presentNext()
    }
    func testSound() {
        do { var sample = Reminder(title: "ذكر", date: Date()); sample.sound = .dhikr; try sounds.play(sample, settings: settings) } catch { report("تعذّر تشغيل الصوت", error) }
    }
    func testNotification() { Task { do { try await notifications.test() } catch { report("الإشعارات", error) } } }
    func allowNotifications() { Task { do { try await notifications.requestPermission(); reconcile() } catch { report("تعذّر طلب الإذن", error) } } }
    func setLogin(_ value: Bool) { do { try login.setEnabled(value) } catch { report("تعذّر تغيير التشغيل عند الدخول", error) } }

    func openWindow(page: Page? = nil) {
        if let page { self.page = page }
        if mainWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1160, height: 790),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Master Reminder"; window.titlebarAppearsTransparent = true
            window.minSize = NSSize(width: 960, height: 700); window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("main-window")
            window.contentView = NSHostingView(rootView: RootView().environmentObject(self))
            window.center(); mainWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); mainWindow?.makeKeyAndOrderFront(nil)
        reconcile()
    }
    func exportData() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Master-Reminder-Backup.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try storage.encoded(data).write(to: url, options: .atomic); notice = "تم تصدير البيانات. ملفات الصوت المخصصة تُنسخ بشكل منفصل." }
        catch { report("تعذّر التصدير", error) }
    }
    func importData() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 10_000_000 else { throw DataError.fileTooLarge }
            var imported = try storage.decode(Data(contentsOf: url))
            let alert = NSAlert(); alert.messageText = "استبدال البيانات الحالية؟"; alert.informativeText = "سيتم حفظ نسخة احتياطية محلية قبل الاستبدال."
            alert.addButton(withTitle: "استيراد"); alert.addButton(withTitle: "إلغاء")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            try backupCurrent()
            imported.settings.onboardingComplete = true
            // Foreign audio filenames never cause reads outside our app-owned Sounds directory.
            for index in imported.reminders.indices where imported.reminders[index].sound == .custom {
                if let file = imported.reminders[index].customSoundFile,
                   FileManager.default.fileExists(atPath: sounds.directory.appendingPathComponent(file).path) { continue }
                imported.reminders[index].sound = .default; imported.reminders[index].customSoundFile = nil
            }
            try storage.save(imported); data = imported; canPersist = true
            clearRuntime(); notifications.clearAll(); reconcile(); notice = "تم الاستيراد. راجع مواقيت الصلاة والتذكيرات."
        } catch { report("تعذّر الاستيراد؛ البيانات الحالية محفوظة", error) }
    }
    private func backupCurrent() throws {
        if FileManager.default.fileExists(atPath: storage.url.path) {
            let backup = storage.url.deletingLastPathComponent().appendingPathComponent("backup-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: storage.url, to: backup)
        }
    }
    func resetData() {
        do {
            try backupCurrent(); let clean = AppData(); try storage.save(clean)
            data = clean; canPersist = true; clearRuntime(); notifications.clearAll(); reconcile()
        } catch { report("تعذّرت إعادة الضبط", error) }
    }
    private func clearRuntime() {
        overlay.close(); sounds.stop(); temporary.removeAll(); transientLedger.removeAll(); activeQueue.removeAll(); recent.removeAll()
    }
    func quit() { prepareForSleep(); NSApp.terminate(nil) }

    private func runSmokeTest() async {
        // Runs inside the real .app on the macOS runner. It never requests permissions or login registration.
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        var results: [String: Bool] = [:]
        results["mainWindow"] = mainWindow?.isVisible == true
        results["libraryLoaded"] = SpiritualLibrary.shared.entries.count == 6545
        results["arabicFontRegistered"] = NSFont(name: Brand.arabicName, size: 18) != nil
        results["brandIconPresent"] = AppResources.url("AppIcon", "png").flatMap { NSImage(contentsOf: $0) } != nil
        results["audioSampleDecodes"] = (try? AVAudioPlayer(contentsOf: AppResources.url("dhikr-sample", "mp3")!)) != nil
        newReminder(); results["creationWizard"] = isCreating; isCreating = false
        widgets.set(.dhikr, visible: true); results["desktopWidgetCreated"] = widgets.count == 1
        widgets.setFloating(true); results["widgetFloating"] = widgets.floatOnTop
        widgets.set(.dhikr, visible: false); results["widgetRemoved"] = widgets.count == 0
        widgets.setFloating(false)

        testOverlay()
        results["overlayCreated"] = overlay.windowCount > 0
        if let occurrence = overlay.current { finish(occurrence) }
        results["overlayClosed"] = overlay.windowCount == 0
        var reminder = Reminder(title: "Smoke", date: Date().addingTimeInterval(3600))
        saveReminder(reminder); results["create"] = data.reminders.contains { $0.id == reminder.id }
        reminder.title = "Updated"; saveReminder(reminder)
        results["edit"] = data.reminders.first { $0.id == reminder.id }?.title == "Updated"
        results["persistence"] = (try? storage.load().reminders.contains { $0.id == reminder.id }) == true
        reminder = data.reminders.first { $0.id == reminder.id } ?? reminder
        reminder.date = Date().addingTimeInterval(2); saveReminder(reminder)
        try? await Task.sleep(nanoseconds: 3_500_000_000)
        results["runtimeDueTrigger"] = overlay.current?.reminder.id == reminder.id
        if let occurrence = overlay.current {
            snooze(occurrence, minutes: 5)
            results["runtimeSnooze"] = data.snoozes.contains { $0.parentID == occurrence.id }
            results["snoozeClosesOverlay"] = overlay.current == nil
            results["snoozePersisted"] = (try? storage.load().snoozes.contains { $0.parentID == occurrence.id }) == true
        } else { results["runtimeSnooze"] = false }
        deleteReminder(reminder); results["delete"] = !data.reminders.contains { $0.id == reminder.id }
        results["deleteSnoozeCleanup"] = data.snoozes.isEmpty
        testReminder()
        try? await Task.sleep(nanoseconds: 11_000_000_000)
        results["tenSecondTestTrigger"] = overlay.current?.reminder.isTemporary == true
        results["temporaryNotPersisted"] = (try? storage.load().reminders.isEmpty) == true
        if let occurrence = overlay.current { finish(occurrence) }
        clearRuntime(); notice = nil
        mainWindow?.close(); results["closeKeepsProcessAlive"] = NSApp.isRunning
        openWindow(); results["reopen"] = mainWindow?.isVisible == true
        let url = storage.url.deletingLastPathComponent().appendingPathComponent("smoke-results.json")
        if let view = mainWindow?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: url.deletingLastPathComponent().appendingPathComponent("dashboard.png"))
        }
        for (target, name) in [(Page.library, "library"), (.widgets, "widgets"), (.tasbih, "tasbih")] {
            page = target
            try? await Task.sleep(nanoseconds: 500_000_000)
            if let view = mainWindow?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: url.deletingLastPathComponent().appendingPathComponent(name + ".png"))
            }
        }
        page = .dashboard; newReminder()
        try? await Task.sleep(nanoseconds: 600_000_000)
        if let view = mainWindow?.attachedSheet?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: url.deletingLastPathComponent().appendingPathComponent("creation.png"))
            results["wizardSheetRendered"] = true
        } else { results["wizardSheetRendered"] = false }
        isCreating = false
        try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: url)
        Log.app.info("Runtime smoke completed")
        NSApp.terminate(nil)
    }
}
