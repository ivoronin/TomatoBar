import KeyboardShortcuts
import SwiftState
import SwiftUI

let digitFont = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)

class TBTimer: ObservableObject {
    @AppStorage("isWindupEnabled") var isWindupEnabled = true
    @AppStorage("isDingEnabled") var isDingEnabled = true
    @AppStorage("isTickingEnabled") var isTickingEnabled = true
    @AppStorage("stopAfterBreak") var stopAfterBreak = false
    @AppStorage("showTimerInMenuBar") var showTimerInMenuBar = true
    @AppStorage("workIntervalLength") var workIntervalLength = 25
    @AppStorage("shortRestIntervalLength") var shortRestIntervalLength = 5
    @AppStorage("longRestIntervalLength") var longRestIntervalLength = 15
    @AppStorage("workIntervalsInSet") var workIntervalsInSet = 4

    @Published var timeLeftString: String = ""

    private var stateMachine = TBStateMachine(state: .ready)
    private var statusBarItem: NSStatusItem? {
        return AppDelegate.shared.statusBarItem
    }

    private let player = TBPlayer()
    private var timeLeftSeconds: Int = 0
    private var consecutiveWorkIntervals: Int = 0
    private var notificationCenter = TBNotificationCenter()
    @Published var timer: DispatchSourceTimer?

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
         *                 |             skipRest           |
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
        stateMachine.addRoutes(event: .skipRest, transitions: [.rest => .work])

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

        KeyboardShortcuts.onKeyUp(for: .startStopTimer) { [self] in
            self.startStopAction()
        }

        notificationCenter.setActionHandler(handler: onNotificationAction)
    }

    private func onNotificationAction(action: TBNotification.Action) {
        if action == .skipRest {
            if stateMachine.state == .rest {
                skipRestAction()
            }
        }
    }

    public func startStopAction() {
        stateMachine <-! .startStop
    }

    public func skipRestAction() {
        stateMachine <-! .skipRest
    }

    public func toggleTickingAction() {
        if stateMachine.state == .work {
            player.toggleTicking()
        }
    }

    private func startTimer(seconds: Int) {
        timeLeftSeconds = seconds

        let queue = DispatchQueue(label: "Timer")
        timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer?.schedule(deadline: .now(), repeating: .seconds(1), leeway: .never)
        timer?.setEventHandler(handler: onTimerTick)
        timer?.resume()
    }

    /**
      Formats timeLeftString and updates menubar item label if it is enabled

      Called when:
      - Timer ticks
      - "Display timer" toggled in settings
     */
    public func renderTimeLeft() {
        var buttonTitle = NSAttributedString()
        timeLeftString = String(
            format: "%.2i:%.2i",
            timeLeftSeconds / 60,
            timeLeftSeconds % 60
        )
        if showTimerInMenuBar, timer != nil {
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

    private func onWorkStart(context _: TBStateMachine.Context) {
        statusBarItem?.button?.image = TBIcon.work
        if isWindupEnabled {
            player.playWindup()
        }
        if isTickingEnabled {
            player.startTicking()
        }
        startTimer(seconds: workIntervalLength * 60)
    }

    private func onWorkFinish(context _: TBStateMachine.Context) {
        consecutiveWorkIntervals += 1
        if isDingEnabled {
            player.playDing()
        }
    }

    private func onWorkEnd(context _: TBStateMachine.Context) {
        player.stopTicking()
    }

    private func onRestStart(context _: TBStateMachine.Context) {
        var kind = "short"
        var length = shortRestIntervalLength
        var image = TBIcon.shortRest
        if consecutiveWorkIntervals >= workIntervalsInSet {
            kind = "long"
            length = longRestIntervalLength
            image = TBIcon.longRest
            consecutiveWorkIntervals = 0
        }
        notificationCenter.send(
            title: "Time's up",
            body: "It's time for a \(kind) break!",
            category: TBNotification.Category.restStarted
        )
        statusBarItem?.button?.image = image
        startTimer(seconds: length * 60)
    }

    private func onRestFinish(context ctx: TBStateMachine.Context) {
        if ctx.event == .skipRest {
            return
        }
        notificationCenter.send(
            title: "Break is over",
            body: "Keep up the good work!",
            category: TBNotification.Category.restFinished
        )
    }

    private func onIdleStart(context _: TBStateMachine.Context) {
        statusBarItem?.button?.title = ""
        statusBarItem?.button?.image = TBIcon.idle
        consecutiveWorkIntervals = 0

        if timer != nil {
            timer?.cancel()
            timer = nil
        }
    }
}
