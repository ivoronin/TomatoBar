import SwiftUI
import UserNotifications

@main
struct TomatoBarApp: App {
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
    var popover = NSPopover()
    public var statusBarItem: NSStatusItem?
    static var shared: AppDelegate!

    func applicationDidFinishLaunching(_: Notification) {
        UNUserNotificationCenter
            .current()
            .requestAuthorization(
                options: [.alert]
            ) { _, error in
                if error != nil {
                    print("Error requesting notification authorization: \(error!)")
                }
            }

        let view = TomatoBarView()

        popover.behavior = .transient
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = NSHostingView(rootView: view)

        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusBarItem?.button?.image = #imageLiteral(resourceName: "BarIcon")
        statusBarItem?.button?.imagePosition = .imageLeft
        statusBarItem?.button?.action = #selector(AppDelegate.togglePopover(_:))
    }

    @objc func showPopover(_: AnyObject?) {
        if let button = statusBarItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
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
