import SwiftState
import SwiftUI
import KeyboardShortcuts

let digitFont = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)

enum BarIcon {
    static var idle = #imageLiteral(resourceName: "BarIconIdle")
    static var work = #imageLiteral(resourceName: "BarIconWork")
    static var shortRest = #imageLiteral(resourceName: "BarIconShortRest")
    static var longRest = #imageLiteral(resourceName: "BarIconLongRest")
}

public class TomatoBarTimer: ObservableObject {
    @AppStorage("isWindupEnabled") public var isWindupEnabled = true
    @AppStorage("isDingEnabled") public var isDingEnabled = true
    @AppStorage("isTickingEnabled") public var isTickingEnabled = true
    @AppStorage("stopAfterBreak") public var stopAfterBreak = false
    @AppStorage("showTimerInMenuBar") public var showTimerInMenuBar = true
    @AppStorage("workIntervalLength") public var workIntervalLength = 25
    @AppStorage("shortRestIntervalLength") public var shortRestIntervalLength = 5
    @AppStorage("longRestIntervalLength") public var longRestIntervalLength = 15
    @AppStorage("workIntervalsInSet") public var workIntervalsInSet = 4

    @Published var timeLeftString: String = ""

    var stateMachine = TomatoBarStateMachine(state: .ready)
    private var statusBarItem: NSStatusItem? {
        return AppDelegate.shared.statusBarItem
    }

    private let player = TomatoBarPlayer()
    private var timeLeftSeconds: Int = 0
    private var consecutiveWorkIntervals: Int = 0
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

        KeyboardShortcuts.onKeyUp(for: .startStopTimer) { [self] in
            self.startStopAction()
        }
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

    private func onWorkStart(context _: TomatoBarContext) {
        statusBarItem?.button?.image = BarIcon.work
        if isWindupEnabled {
            player.playWindup()
        }
        if isTickingEnabled {
            player.startTicking()
        }
        startTimer(seconds: workIntervalLength * 60)
    }

    private func onWorkFinish(context _: TomatoBarContext) {
        consecutiveWorkIntervals += 1
        if isDingEnabled {
            player.playDing()
        }
    }

    private func onWorkEnd(context _: TomatoBarContext) {
        player.stopTicking()
    }

    private func onRestStart(context _: TomatoBarContext) {
        var kind = "short"
        var length = shortRestIntervalLength
        var image = BarIcon.shortRest
        if consecutiveWorkIntervals >= workIntervalsInSet {
            kind = "long"
            length = longRestIntervalLength
            image = BarIcon.longRest
            consecutiveWorkIntervals = 0
        }
        NotificationCenter.send(
            title: "Time's up",
            body: "It's time for a \(kind) break!"
        )
        statusBarItem?.button?.image = image
        startTimer(seconds: length * 60)
    }

    private func onRestFinish(context _: TomatoBarContext) {
        NotificationCenter.send(title: "Break is over", body: "Keep up the good work!")
    }

    private func onIdleStart(context _: TomatoBarContext) {
        statusBarItem?.button?.title = ""
        statusBarItem?.button?.image = BarIcon.idle
        consecutiveWorkIntervals = 0

        if timer != nil {
            timer?.cancel()
            timer = nil
        }
    }
}
