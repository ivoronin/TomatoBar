import SwiftUI
import LaunchAtLogin

extension NSImage.Name {
    static let idle = Self("BarIconIdle")
    static let work = Self("BarIconWork")
    static let shortRest = Self("BarIconShortRest")
    static let longRest = Self("BarIconLongRest")
}

private let digitFont = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)
private let popoverSize = NSSize(width: 252, height: 332)
private let tomatoAccentColor = Color(NSColor.systemRed)

@main
struct TBApp: App {
    @NSApplicationDelegateAdaptor(TBStatusItem.self) var appDelegate

    init() {
        TBStatusItem.shared = appDelegate
        LaunchAtLogin.migrateIfNeeded()
        logger.append(event: TBLogEventAppStart())
    }

    var body: some Scene {
        Settings {}
    }
}

class TBStatusItem: NSObject, NSApplicationDelegate {
    private var panel: TBPopoverPanel?
    private var statusBarItem: NSStatusItem?
    private var eventMonitor: Any?
    static var shared: TBStatusItem!

    func applicationDidFinishLaunching(_: Notification) {
        statusBarItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        statusBarItem?.button?.imagePosition = .imageLeft
        setIcon(name: .idle)
        statusBarItem?.button?.target = self
        statusBarItem?.button?.action = #selector(TBStatusItem.togglePopover(_:))
        statusBarItem?.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
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

    func setIcon(name: NSImage.Name) {
        statusBarItem?.button?.image = NSImage(named: name)
    }

    func showPopover(_: Any?) {
        guard let button = statusBarItem?.button else {
            return
        }

        if panel == nil {
            let rootView = TBPopoverView()
                .frame(width: popoverSize.width, height: popoverSize.height)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .modifier(TomatoAccentModifier())
            let hostingView = NSHostingView(rootView: rootView)
            hostingView.frame = NSRect(origin: .zero, size: popoverSize)
            panel = TBPopoverPanel(contentView: hostingView)
        }

        guard let panel else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.setFrame(originFrame(alignedTo: button), display: false)
        panel.makeKeyAndOrderFront(nil)
        statusBarItem?.button?.highlight(true)
        statusBarItem?.button?.needsDisplay = true
        startEventMonitor()
    }

    func closePopover(_ sender: Any?) {
        stopEventMonitor()
        panel?.orderOut(sender)
        statusBarItem?.button?.highlight(false)
        statusBarItem?.button?.needsDisplay = true
    }

    @objc func togglePopover(_ sender: Any?) {
        if panel?.isVisible == true {
            closePopover(sender)
        } else {
            showPopover(sender)
        }
    }

    private func originFrame(alignedTo button: NSStatusBarButton) -> NSRect {
        guard let buttonWindow = button.window else {
            return NSRect(origin: .zero, size: popoverSize)
        }

        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screenFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? buttonFrame
        var origin = NSPoint(x: buttonFrame.minX, y: screenFrame.maxY - popoverSize.height)

        if origin.x + popoverSize.width > screenFrame.maxX {
            origin.x = screenFrame.maxX - popoverSize.width
        }
        if origin.x < screenFrame.minX {
            origin.x = screenFrame.minX
        }
        if origin.y < screenFrame.minY {
            origin.y = screenFrame.minY
        }

        return NSRect(origin: origin, size: popoverSize)
    }

    private func startEventMonitor() {
        stopEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if self?.statusButtonContains(event) == false {
                self?.closePopover(nil)
            }
        }
    }

    private func stopEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func statusButtonContains(_ event: NSEvent) -> Bool {
        guard let button = statusBarItem?.button, let buttonWindow = button.window else {
            return false
        }

        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        return buttonFrame.contains(event.locationInWindow)
    }
}

private final class TBPopoverPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: popoverSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.contentView = contentView
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isFloatingPanel = true
        isOpaque = false
        isReleasedWhenClosed = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private struct TomatoAccentModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 12.0, *) {
            content
                .accentColor(tomatoAccentColor)
                .tint(tomatoAccentColor)
        } else {
            content.accentColor(tomatoAccentColor)
        }
    }
}
