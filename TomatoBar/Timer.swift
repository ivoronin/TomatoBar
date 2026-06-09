import KeyboardShortcuts
import SwiftState
import SwiftUI

@MainActor
class TBTimer: ObservableObject {
    @AppStorage("stopAfterBreak") var stopAfterBreak = false
    @AppStorage("showTimerInMenuBar") var showTimerInMenuBar = true
    @AppStorage("workIntervalLength") var workIntervalLength = 25
    @AppStorage("shortRestIntervalLength") var shortRestIntervalLength = 5
    @AppStorage("longRestIntervalLength") var longRestIntervalLength = 15
    @AppStorage("workIntervalsInSet") var workIntervalsInSet = 4
    // This preference is "hidden"
    @AppStorage("overrunTimeLimit") var overrunTimeLimit = -60.0
    @AppStorage("enableRestOverlay") var enableRestOverlay = true
    @AppStorage("restBackgroundFolderPath") var restBackgroundFolderPath = ""
    @AppStorage("restBackgroundFolderBookmark") var restBackgroundFolderBookmark = Data()

    private var stateMachine = TBStateMachine(state: .idle)
    public let player = TBPlayer()
    private let overlayController = TBRestOverlayController()
    private let restBackgroundProvider = TBRestBackgroundProvider()
    private var consecutiveWorkIntervals: Int = 0
    private var notificationCenter = TBNotificationCenter()
    private var finishTime: Date!
    private var timerFormatter = DateComponentsFormatter()
    private var didAutoStartOnLaunch = false
    private var timerGeneration = 0
    private let timerRefreshInterval = 0.25
    @Published var timeLeftString: String = ""
    @Published var timer: Timer?

    init() {
        /*
         * State diagram
         *
         *                 start/stop
         *       +--------------+-------------+
         *       |              |             |
         *       |  start/stop  |  timerFired |
         *       V    |         |    |        |
         * +--------+ |  +--------+  | +--------+
         * | idle   |--->| work   |--->| rest   |
         * +--------+    +--------+    +--------+
         *   A                  A        |    |
         *   |                  |        |    |
         *   |                  +--------+    |
         *   |  timerFired (!stopAfterBreak)  |
         *   |             skipRest           |
         *   |                                |
         *   +--------------------------------+
         *      timerFired (stopAfterBreak)
         *
         */
        stateMachine.addRoutes(event: .startStop, transitions: [
            .idle => .work, .work => .idle, .rest => .idle,
        ])
        stateMachine.addRoutes(event: .startRest, transitions: [.idle => .rest])
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
        stateMachine.addAnyHandler(.any => .any, handler: { ctx in
            logger.append(event: TBLogEventTransition(fromContext: ctx))
        })

        stateMachine.addErrorHandler { ctx in fatalError("state machine context: <\(ctx)>") }

        timerFormatter.unitsStyle = .positional
        timerFormatter.allowedUnits = [.minute, .second]
        timerFormatter.zeroFormattingBehavior = .pad

        KeyboardShortcuts.onKeyUp(for: .startStopTimer, action: startStop)
        notificationCenter.setActionHandler(handler: onNotificationAction)

        let aem: NSAppleEventManager = NSAppleEventManager.shared()
        aem.setEventHandler(self,
                            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
                            forEventClass: AEEventClass(kInternetEventClass),
                            andEventID: AEEventID(kAEGetURL))

        startWorkOnLaunch()
    }

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor,
                                 withReplyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.forKeyword(AEKeyword(keyDirectObject))?.stringValue else {
            print("url handling error: cannot get url")
            return
        }
        let url = URL(string: urlString)
        guard url != nil,
              let scheme = url!.scheme,
              let host = url!.host else {
            print("url handling error: cannot parse url")
            return
        }
        guard scheme.caseInsensitiveCompare("tomatobar") == .orderedSame else {
            print("url handling error: unknown scheme \(scheme)")
            return
        }
        switch host.lowercased() {
        case "startstop":
            startStop()
        default:
            print("url handling error: unknown command \(host)")
            return
        }
    }

    func startStop() {
        stateMachine <-! .startStop
    }

    private func startWorkOnLaunch() {
        guard !didAutoStartOnLaunch, stateMachine.state == .idle else { return }
        didAutoStartOnLaunch = true
        startStop()
    }

    func startRest() {
        stateMachine <-! .startRest
    }

    func skipRest() {
        stateMachine <-! .skipRest
    }

    func setRestBackgroundFolder(url: URL) {
        restBackgroundFolderPath = url.path
        restBackgroundFolderBookmark = (try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )) ?? Data()
    }

    func updateTimeLeft(now: Date = Date()) {
        timeLeftString = formattedTimeLeft(now: now)
        if timer != nil, showTimerInMenuBar {
            TBStatusItem.shared.setTitle(title: timeLeftString)
        } else {
            TBStatusItem.shared.setTitle(title: nil)
        }
        if timer != nil, enableRestOverlay {
            overlayController.updateCountdown(timeLeftString)
        }
    }

    private func formattedTimeLeft(now: Date = Date()) -> String {
        let secondsLeft = max(0, ceil(finishTime.timeIntervalSince(now)))
        return timerFormatter.string(from: secondsLeft)!
    }

    private func startTimer(seconds: Int) {
        stopTimer()
        timerGeneration += 1
        let generation = timerGeneration
        finishTime = Date().addingTimeInterval(TimeInterval(seconds))

        let activeTimer = Timer(timeInterval: timerRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.onTimerTick(generation: generation)
            }
        }
        timer = activeTimer
        RunLoop.main.add(activeTimer, forMode: .common)
    }

    private func stopTimer() {
        timerGeneration += 1
        timer?.invalidate()
        timer = nil
    }

    private func onTimerTick(generation: Int) {
        guard generation == timerGeneration else { return }

        let now = Date()
        updateTimeLeft(now: now)
        let timeLeft = finishTime.timeIntervalSince(now)
        if timeLeft <= 0 {
            stopTimer()
            /*
             Ticks can be missed during the machine sleep.
             Stop the timer if it goes beyond an overrun time limit.
             */
            if timeLeft < overrunTimeLimit {
                stateMachine <-! .startStop
            } else {
                stateMachine <-! .timerFired
            }
        }
    }

    private func onNotificationAction(action: TBNotification.Action) {
        if action == .skipRest, stateMachine.state == .rest {
            skipRest()
        }
    }

    private func onWorkStart(context _: TBStateMachine.Context) {
        TBStatusItem.shared.setIcon(name: .work)
        player.playWindup()
        player.startTicking()
        startTimer(seconds: workIntervalLength * 60)
    }

    private func onWorkFinish(context _: TBStateMachine.Context) {
        consecutiveWorkIntervals += 1
        player.playDing()
    }

    private func onWorkEnd(context _: TBStateMachine.Context) {
        player.stopTicking()
    }

    private func onRestStart(context _: TBStateMachine.Context) {
        var body = NSLocalizedString("TBTimer.onRestStart.short.body", comment: "Short break body")
        var length = shortRestIntervalLength
        var imgName = NSImage.Name.shortRest
        var restType = TBRestOverlayController.RestType.shortRest
        if consecutiveWorkIntervals >= workIntervalsInSet {
            body = NSLocalizedString("TBTimer.onRestStart.long.body", comment: "Long break body")
            length = longRestIntervalLength
            imgName = .longRest
            restType = .longRest
            consecutiveWorkIntervals = 0
        }
        notificationCenter.send(
            title: NSLocalizedString("TBTimer.onRestStart.title", comment: "Time's up title"),
            body: body,
            category: .restStarted
        )
        TBStatusItem.shared.setIcon(name: imgName)
        startTimer(seconds: length * 60)
        if enableRestOverlay {
            let initialCountdown = formattedTimeLeft()
            let configuredImage = restBackgroundProvider.randomImage(
                folderPath: restBackgroundFolderPath,
                bookmarkData: restBackgroundFolderBookmark
            )
            let backgroundImage = configuredImage ?? NSImage(named: "RestBackground")
            overlayController.showOverlays(
                restType: restType,
                countdown: initialCountdown,
                backgroundImage: backgroundImage,
                skipHandler: { [weak self] in self?.skipRest() }
            )
        }
    }

    private func onRestFinish(context ctx: TBStateMachine.Context) {
        overlayController.closeOverlays()
        if ctx.event == .skipRest {
            return
        }
        notificationCenter.send(
            title: NSLocalizedString("TBTimer.onRestFinish.title", comment: "Break is over title"),
            body: NSLocalizedString("TBTimer.onRestFinish.body", comment: "Break is over body"),
            category: .restFinished
        )
    }

    private func onIdleStart(context _: TBStateMachine.Context) {
        stopTimer()
        TBStatusItem.shared.setIcon(name: .idle)
        consecutiveWorkIntervals = 0
        overlayController.closeOverlays()
    }
}
