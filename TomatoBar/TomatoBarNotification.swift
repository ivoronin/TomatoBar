import UserNotifications

public enum TomatoBarNotification {
    public enum Category: String {
        case restStarted, restFinished
    }

    public enum Action: String {
        case skipRest
    }
}

public typealias NotificationHandler = (TomatoBarNotification.Action) -> Void

class NotificationDispatcher: NSObject, UNUserNotificationCenterDelegate {
    private var handler: NotificationHandler!

    func setActionHandler(handler: @escaping NotificationHandler) {
        self.handler = handler
    }

    func userNotificationCenter(_: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler _: @escaping () -> Void)
    {
        if handler != nil {
            if let action = TomatoBarNotification.Action(rawValue: response.actionIdentifier) {
                handler(action)
            }
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
            identifier: TomatoBarNotification.Action.skipRest.rawValue,
            title: "Skip",
            options: []
        )
        let restStartedCategory = UNNotificationCategory(
            identifier: TomatoBarNotification.Category.restStarted.rawValue,
            actions: [actionSkipRest],
            intentIdentifiers: []
        )
        let restFinishedCategory = UNNotificationCategory(
            identifier: TomatoBarNotification.Category.restFinished.rawValue,
            actions: [],
            intentIdentifiers: []
        )

        center.setNotificationCategories([
            restStartedCategory,
            restFinishedCategory,
        ])
    }

    public func setActionHandler(handler: @escaping NotificationHandler) {
        dispatcher.setActionHandler(handler: handler)
    }

    public func send(title: String, body: String, category: TomatoBarNotification.Category) {
        if disabled {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category.rawValue
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
