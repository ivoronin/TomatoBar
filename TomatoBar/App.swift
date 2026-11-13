import Carbon.HIToolbox
import SwiftUI
import LaunchAtLogin

extension NSImage.Name {
    static let idle = Self("BarIconIdle")
    static let work = Self("BarIconWork")
    static let shortRest = Self("BarIconShortRest")
    static let longRest = Self("BarIconLongRest")
}

private let digitFont = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)

@main
struct TBApp: App {
    @NSApplicationDelegateAdaptor(TBStatusItem.self) var appDelegate

    init() {
        TBStatusItem.shared = appDelegate
        LaunchAtLogin.migrateIfNeeded()
    }

    var body: some Scene {
        Settings {}
    }
}

class TBStatusItem: NSObject, NSApplicationDelegate {
    private var popover = NSPopover()
    private var statusBarItem: NSStatusItem?
    private(set) var timer: TBTimer!
    private var sleepObserver: NSObjectProtocol?
    private var logObserver: NSObjectProtocol?
    private var timeZoneObserver: NSObjectProtocol?
    private var statsTabMonitor: Any?
    private var logAlertScheduled = false
    private var readAlertScheduled = false
    private var terminationPending = false
    private var forceQuit = false
    private var lastDamagedLines: [Int] = []
    private let stats = TBStatsPanelModel()
    static var shared: TBStatusItem!

    func applicationDidFinishLaunching(_: Notification) {
        timer = TBTimer()
        timer.onLogFailure = { [weak self] _ in self?.presentLogFailure() }
        let view = TBPopoverView(
            timer: timer, stats: stats,
            showCurrentStats: { [weak self] in self?.resetStats() },
            retryHistory: { [weak self] in self?.reloadHistory(presentReadError: false) },
            resize: { [weak self] size in
                guard size.width > 0, size.height > 0 else { return }
                DispatchQueue.main.async {
                    guard let self = self, self.popover.contentSize != size else { return }
                    self.popover.contentSize = size
                }
            }
        )
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: view)
        popover.contentSize = viewSize()

        statusBarItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        statusBarItem?.button?.imagePosition = .imageLeft
        setIcon(name: .idle)
        statusBarItem?.button?.action = #selector(TBStatusItem.togglePopover(_:))

        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.timer.finishActiveInterval() }
        logObserver = NotificationCenter.default.addObserver(
            forName: .tbLogDidAppend, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.reloadHistory() }
        }
        timeZoneObserver = NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main
        ) { [weak self] _ in self?.stats.refreshTimeZone() }
        if #available(macOS 14.0, *) {
            installStatsTabMonitor()
        }
        if !logger.append(event: TBLogEventAppStart()) {
            presentLogFailure()
        } else {
            reloadHistory()
        }
    }

    private func installStatsTabMonitor() {
        statsTabMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.keyCode == kVK_Tab, self.popover.isShown,
                  event.window === self.popover.contentViewController?.view.window,
                  self.stats.tab == .stats, self.stats.historyError == nil,
                  event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
                return event
            }
            // Let macOS handle traversal after the first Tab enters the chart.
            return self.stats.handleDayTab(backward: event.modifierFlags.contains(.shift)) ? nil : event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = statsTabMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if forceQuit { return .terminateNow }
        timer?.finishActiveInterval()
        if logger.lastError != nil || logger.hasPendingEvents {
            terminationPending = true
            presentLogFailure()
            return .terminateLater
        }
        return .terminateNow
    }

    private func presentLogFailure() {
        guard !logAlertScheduled else { return }
        logAlertScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            defer { self.logAlertScheduled = false }
            while let error = logger.lastError {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Could not save the activity log"
                alert.informativeText = "The timer has stopped. \(error.localizedDescription)"
                alert.addButton(withTitle: "Retry")
                alert.addButton(withTitle: "Quit")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn {
                    if logger.retryPending() {
                        self.timer.didRecoverLog()
                        if self.terminationPending {
                            NSApp.reply(toApplicationShouldTerminate: true)
                        }
                    }
                } else {
                    self.forceQuit = true
                    if self.terminationPending {
                        NSApp.reply(toApplicationShouldTerminate: true)
                    } else {
                        NSApp.terminate(nil)
                    }
                    break
                }
            }
        }
    }

    func reloadHistory(presentReadError: Bool = true) {
        // A recoverable partial write is not a damaged historical record.
        guard logger.lastError == nil, !logger.hasPendingEvents else { return }
        do {
            let snapshot = try TBHistory.read(from: logger.fileURL)
            stats.updateHistory(snapshot)
            if snapshot.damagedLines != lastDamagedLines {
                lastDamagedLines = snapshot.damagedLines
                if !snapshot.damagedLines.isEmpty {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Some activity records could not be read"
                        alert.informativeText = "The log is preserved. Only complete, valid intervals are included."
                        alert.runModal()
                    }
                }
            }
        } catch {
            stats.failReading(error)
            if presentReadError && !(popover.isShown && stats.tab == .stats) {
                presentReadFailure()
            }
        }
    }

    private func presentReadFailure() {
        guard !readAlertScheduled else { return }
        readAlertScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            defer { self.readAlertScheduled = false }
            guard let error = self.stats.historyError else { return }
            let alert = NSAlert()
            alert.messageText = "Could not load the activity log"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Retry")
            alert.addButton(withTitle: "Close")
            if alert.runModal() == .alertFirstButtonReturn {
                DispatchQueue.main.async { self.reloadHistory() }
            }
        }
    }

    func setTitle(title: String?) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 0.9
        paragraphStyle.alignment = NSTextAlignment.center

        let attributedTitle = NSAttributedString(
            string: title != nil ? " \(title!)" : "",
            attributes: [
                NSAttributedString.Key.font: digitFont,
                NSAttributedString.Key.paragraphStyle: paragraphStyle
            ]
        )
        statusBarItem?.button?.attributedTitle = attributedTitle
    }

    func setIcon(name: NSImage.Name, tint: NSColor? = nil) {
        let image = NSImage(named: name)
        guard let original = image, let tint = tint else {
            statusBarItem?.button?.image = image
            return
        }
        let tinted = NSImage(size: original.size, flipped: false) { bounds in
            original.draw(in: bounds)
            tint.setFill()
            bounds.fill(using: .sourceIn)
            return true
        }
        statusBarItem?.button?.image = tinted
    }

    private func resetStats() {
        stats.reset()
        reloadHistory(presentReadError: false)
    }

    private func viewSize() -> NSSize {
        let view = popover.contentViewController!.view
        view.layoutSubtreeIfNeeded()
        return view.fittingSize
    }

    func showPopover(_: AnyObject?) {
        if let button = statusBarItem?.button {
            resetStats()
            popover.contentSize = viewSize()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func closePopover(_ sender: AnyObject?) {
        popover.performClose(sender)
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            closePopover(sender)
        } else {
            showPopover(sender)
        }
    }
}
