import SwiftUI

enum TBIcon {
    static var idle = #imageLiteral(resourceName: "BarIconIdle")
    static var work = #imageLiteral(resourceName: "BarIconWork")
    static var shortRest = #imageLiteral(resourceName: "BarIconShortRest")
    static var longRest = #imageLiteral(resourceName: "BarIconLongRest")
}

@main
struct TBApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        AppDelegate.shared = appDelegate
    }

    var body: some Scene {
        WindowGroup {
            EmptyView()
                .frame(width: .zero)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var popover = NSPopover()
    var statusBarItem: NSStatusItem?
    static var shared: AppDelegate!

    func applicationDidFinishLaunching(_: Notification) {
        let view = TBPopoverView()

        popover.behavior = .transient
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = NSHostingView(rootView: view)

        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusBarItem?.button?.image = TBIcon.idle
        statusBarItem?.button?.imagePosition = .imageLeft
        statusBarItem?.button?.action = #selector(AppDelegate.togglePopover(_:))
    }

    @objc func showPopover(_: AnyObject?) {
        if let button = statusBarItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc func closePopover(_ sender: AnyObject?) {
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
