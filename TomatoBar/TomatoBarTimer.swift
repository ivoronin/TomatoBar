import AppKit
import Foundation
import SwiftState
import SwiftUI
import UserNotifications

let digitFont = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)

public class TomatoBarTimer: ObservableObject {
    @AppStorage("isWindupEnabled") public var isWindupEnabled = true
    @AppStorage("isDingEnabled") public var isDingEnabled = true
    @AppStorage("isTickingEnabled") public var isTickingEnabled = true
    @AppStorage("stopAfterBreak") public var stopAfterBreak = false
    @AppStorage("showTimerInMenuBar") public var showTimerInMenuBar = true
    @AppStorage("workIntervalLength") public var workIntervalLength = 25
    @AppStorage("restIntervalLength") public var restIntervalLength = 5

    @Published var startStopString: String = "Start"
    @Published var timeLeftString: String = ""

    @Published var stateMachine = TomatoBarStateMachine(state: .ready)
    private var statusBarItem: NSStatusItem? {
        return AppDelegate.shared.statusBarItem
    }

    private let player = TomatoBarPlayer()
    private var timeLeftSeconds: Int = 0
    private var timer: DispatchSourceTimer?

    init() {
        /*
         * State diagram
         *
         *                               start/stop
         *                     +--------------+-------------+
         *                     |              |             |
         *       viewDidLoad   |  start/stop  |  timerFired |
         *            |        V    |         |    |        |
         * +--------+ |  +--------+ |  +--------+  | +--------+
         * | ready  |--->| idle   |--->| work   |--->| rest   |
         * +--------+    +--------+    +--------+    +--------+
         *                 A                  A        |    |
         *                 |                  |        |    |
         *                 |                  +--------+    |
         *                 |  timerFired (!stopAfterBreak)  |
         *                 |                                |
         *                 +--------------------------------+
         *                    timerFired (stopAfterBreak)
         *
         */
        stateMachine.addRoute(.ready => .idle)
        stateMachine.addRoutes(event: .startStop, transitions: [
            .idle => .work, .work => .idle, .rest => .idle,
        ])
        stateMachine.addRoutes(event: .timerFired, transitions: [.work => .rest])
        stateMachine.addRoutes(event: .timerFired, transitions: [.rest => .idle]) { _ in
            self.stopAfterBreak
        }
        stateMachine.addRoutes(event: .timerFired, transitions: [.rest => .work]) { _ in
            !self.stopAfterBreak
        }

        /*
         * "Finish" handlers are called when time interval ended
         * "End"    handlers are called when time interval ended or was cancelled
         */
        stateMachine.addAnyHandler(.any => .work, handler: onWorkStart)
        stateMachine.addAnyHandler(.work => .rest, order: 0, handler: onWorkFinish)
        stateMachine.addAnyHandler(.work => .any, order: 1, handler: onWorkEnd)
        stateMachine.addAnyHandler(.any => .rest, handler: onRestStart)
        stateMachine.addAnyHandler(.rest => .work, handler: onRestFinish)
        stateMachine.addAnyHandler(.any => .idle, handler: onIdleStart)

        stateMachine.addErrorHandler { ctx in fatalError("state machine context: <\(ctx)>") }

        stateMachine <- .idle
    }

    public func startStopAction() {
        stateMachine <-! .startStop
    }

    public func toggleTickingAction() {
        if stateMachine.state == .work {
            player.toggleTicking()
        }
    }

    private func startTimer(seconds: Int) {
        startStopString = "Stop"

        timeLeftSeconds = seconds

        let queue = DispatchQueue(label: "Timer")
        timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer?.schedule(deadline: .now(), repeating: .seconds(1), leeway: .never)
        timer?.setEventHandler(handler: onTimerTick)
        timer?.resume()
    }

    public func renderTimeLeft() {
        var buttonTitle = NSAttributedString()
        timeLeftString = String(
            format: "%.2i:%.2i",
            timeLeftSeconds / 60,
            timeLeftSeconds % 60
        )
        if showTimerInMenuBar {
            buttonTitle = NSAttributedString(
                string: " \(timeLeftString)",
                attributes: [NSAttributedString.Key.font: digitFont]
            )
        }
        statusBarItem?.button?.attributedTitle = buttonTitle
    }

    private func onTimerTick() {
        timeLeftSeconds -= 1
        DispatchQueue.main.async {
            if self.timeLeftSeconds >= 0 {
                self.renderTimeLeft()
            } else {
                self.stateMachine <-! .timerFired
            }
        }
    }

    private func onWorkStart(context _: TomatoBarContext) {
        if isWindupEnabled {
            player.playWindup()
        }
        if isTickingEnabled {
            player.startTicking()
        }
        startTimer(seconds: workIntervalLength * 60)
    }

    private func onWorkFinish(context _: TomatoBarContext) {
        sendNotification(title: "Time's up", body: "It's time for a break!")
        if isDingEnabled {
            player.playDing()
        }
    }

    private func onWorkEnd(context _: TomatoBarContext) {
        player.stopTicking()
    }

    private func onRestStart(context _: TomatoBarContext) {
        startTimer(seconds: restIntervalLength * 60)
    }

    private func onRestFinish(context _: TomatoBarContext) {
        sendNotification(title: "Break is over", body: "Keep up the good work!")
    }

    private func onIdleStart(context _: TomatoBarContext) {
        startStopString = "Start"
        statusBarItem?.button?.title = ""

        if timer != nil {
            timer?.cancel()
            timer = nil
        }
    }

    private func sendNotification(title: String, body: String) {
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
