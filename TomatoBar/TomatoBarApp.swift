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
        let view = TomatoBarView()

        popover.behavior = .transient
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = NSHostingView(rootView: view)

        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusBarItem?.button?.image = BarIcon.idle
        statusBarItem?.button?.imagePosition = .imageLeft
        statusBarItem?.button?.action = #selector(AppDelegate.togglePopover(_:))

        NotificationCenter.requestAuthorization()
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

enum NotificationCenter {
    static func requestAuthorization() {
        UNUserNotificationCenter
            .current()
            .requestAuthorization(
                options: [.alert]
            ) { _, error in
                if error != nil {
                    print("Error requesting notification authorization: \(error!)")
                }
            }
    }

    static func send(title: String, body: String) {
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.getNotificationSettings { settings in
            if settings.authorizationStatus != .authorized ||
                settings.alertSetting != .enabled
            {
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            notificationCenter.add(request) { error in
                if error != nil {
                    print("Error adding notification: \(error!)")
                }
            }
        }
    }
}
