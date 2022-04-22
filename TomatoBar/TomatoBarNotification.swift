import UserNotifications

public enum TomatoBarNotification {
    public enum Category {
        static let restStarted = "restStarted"
        static let restFinished = "restFinished"
    }

    enum Action {
        static let skipRest = "skipBreak"
    }
}

public typealias NotificationHandler = (String) -> Void

class NotificationDispatcher: NSObject, UNUserNotificationCenterDelegate {
    private var handler: NotificationHandler!

    func registerActionHandler(handler: @escaping NotificationHandler) {
        self.handler = handler
    }

    func userNotificationCenter(_: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler _: @escaping () -> Void)
    {
        if handler != nil {
            handler(response.actionIdentifier)
        }
    }
}

public class NotificationCenter {
    private var center = UNUserNotificationCenter.current()
    private var dispatcher = NotificationDispatcher()
    private var disabled = false

    init() {
        center.requestAuthorization(
            options: [.alert]
        ) { _, error in
            if error != nil {
                self.disabled = true
                print("Error requesting notification authorization: \(error!)")
            }
        }

        center.delegate = dispatcher

        let actionSkipRest = UNNotificationAction(
            identifier: TomatoBarNotification.Action.skipRest,
            title: "Skip",
            options: []
        )
        let restStartedCategory = UNNotificationCategory(
            identifier: TomatoBarNotification.Category.restStarted,
            actions: [actionSkipRest],
            intentIdentifiers: []
        )
        let restFinishedCategory = UNNotificationCategory(
            identifier: TomatoBarNotification.Category.restFinished,
            actions: [],
            intentIdentifiers: []
        )

        center.setNotificationCategories([
            restStartedCategory,
            restFinishedCategory,
        ])
    }

    public func registerActionHandler(handler: @escaping NotificationHandler) {
        dispatcher.registerActionHandler(handler: handler)
    }

    public func send(title: String, body: String, category: String) {
        if disabled {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if error != nil {
                print("Error adding notification: \(error!)")
            }
        }
    }
}
