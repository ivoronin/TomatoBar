import KeyboardShortcuts
import SwiftState
import SwiftUI

class TBTimer: ObservableObject {
    @AppStorage("stopAfterBreak") var stopAfterBreak = false
    @AppStorage("showTimerInMenuBar") var showTimerInMenuBar = true
    @AppStorage("workIntervalLength") var workIntervalLength = 25
    @AppStorage("shortRestIntervalLength") var shortRestIntervalLength = 5
    @AppStorage("longRestIntervalLength") var longRestIntervalLength = 15
    @AppStorage("workIntervalsInSet") var workIntervalsInSet = 4
    // This preference is "hidden"
    @AppStorage("overrunTimeLimit") var overrunTimeLimit = -60.0

    static let pauseColor = NSColor(srgbRed: 1, green: 0.68, blue: 0.24, alpha: 1)

    var onLogFailure: ((Error) -> Void)?
    private let eventLog: TBLogger
    private let now: () -> Date
    private var failureTime: Date?
    private var stateMachine = TBStateMachine(state: .idle)
    public let player = TBPlayer()
    private var consecutiveWorkIntervals: Int = 0
    private var notificationCenter = TBNotificationCenter()
    private var finishTime: Date?
    private var pausedInterval: (state: TBStateMachineStates, remaining: TimeInterval)?
    private var restIcon: NSImage.Name = .shortRest
    private var timerFormatter = DateComponentsFormatter()
    @Published var timeLeftString: String = ""
    @Published var timer: DispatchSourceTimer?

    init(log: TBLogger = logger, registerSystemHandlers: Bool = true,
         now: @escaping () -> Date = Date.init) {
        eventLog = log
        self.now = now
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
        stateMachine.addRoutes(event: .skipWork, transitions: [.work => .rest])
        stateMachine.addRoutes(event: .skipRest, transitions: [.rest => .work])
        stateMachine.addRoutes(event: .pause, transitions: [.work => .paused, .rest => .paused])
        stateMachine.addRoutes(event: .resume, transitions: [.paused => .work]) { [weak self] _ in
            self?.pausedInterval?.state == .work
        }
        stateMachine.addRoutes(event: .resume, transitions: [.paused => .rest]) { [weak self] _ in
            self?.pausedInterval?.state == .rest
        }
        stateMachine.addRoutes(event: .discardPause, transitions: [.paused => .idle])

        /*
         * "Finish" handlers are called when time interval ended
         * "End"    handlers are called when time interval ended or was cancelled
         */
        stateMachine.addAnyHandler(.any => .work, handler: onWorkStart)
        stateMachine.addAnyHandler(.work => .rest, order: 0, handler: onWorkFinish)
        stateMachine.addAnyHandler(.work => .any, order: 1, handler: onWorkEnd)
        stateMachine.addAnyHandler(.any => .rest, handler: onRestStart)
        stateMachine.addAnyHandler(.rest => .work, handler: onRestFinish)
        stateMachine.addAnyHandler(.any => .paused, handler: onPause)
        stateMachine.addAnyHandler(.any => .idle, handler: onIdleStart)
        stateMachine.addAnyHandler(.any => .any, order: .max, handler: recordTransition)

        stateMachine.addErrorHandler { ctx in fatalError("state machine context: <\(ctx)>") }

        timerFormatter.unitsStyle = .positional
        timerFormatter.allowedUnits = [.minute, .second]
        timerFormatter.zeroFormattingBehavior = .pad

        if registerSystemHandlers {
            KeyboardShortcuts.onKeyUp(for: .startStopTimer, action: startStop)
            notificationCenter.setActionHandler(handler: onNotificationAction)

            let aem = NSAppleEventManager.shared()
            aem.setEventHandler(self,
                               andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
                               forEventClass: AEEventClass(kInternetEventClass),
                               andEventID: AEEventID(kAEGetURL))
        }
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

    var isPaused: Bool { stateMachine.state == .paused }
    var canTogglePause: Bool { stateMachine.state != .idle }
    var isResting: Bool { stateMachine.state == .rest }
    var canSkipInterval: Bool { canTogglePause && !isPaused }

    func startStop() {
        guard !isPaused, eventLog.lastError == nil, !eventLog.hasPendingEvents else { return }
        transition(.startStop)
    }

    func skipInterval() {
        guard canSkipInterval, eventLog.lastError == nil, !eventLog.hasPendingEvents else { return }
        transition(isResting ? .skipRest : .skipWork)
    }

    func togglePause() {
        guard canTogglePause, eventLog.lastError == nil, !eventLog.hasPendingEvents else { return }
        transition(isPaused ? .resume : .pause)
    }

    func finishActiveInterval() {
        guard stateMachine.state != .idle else { return }
        transition(isPaused ? .discardPause : .startStop)
    }

    private func transition(_ event: TBStateMachineEvents) {
        stateMachine.tryEvent(event, userInfo: failureTime ?? now())
    }

    private func transitionTime(_ context: TBStateMachine.Context) -> Date {
        context.userInfo as? Date ?? now()
    }

    func didRecoverLog() {
        failureTime = nil
    }

    private func recordTransition(context: TBStateMachine.Context) {
        let event = TBLogEventTransition(fromContext: context, timestamp: transitionTime(context))
        guard !eventLog.append(event: event) else { return }
        let firstFailure = failureTime == nil
        failureTime = event.timestamp
        // A transition may have started the next interval before writing failed.
        // Close it at the same instant, never at the time Retry is clicked.
        finishActiveInterval()
        if firstFailure, let error = eventLog.lastError {
            onLogFailure?(error)
        }
    }

    func updateTimeLeft() {
        if let remaining = pausedInterval?.remaining {
            timeLeftString = timerFormatter.string(from: remaining) ?? ""
        } else {
            timeLeftString = finishTime.map { timerFormatter.string(from: now(), to: $0) ?? "" } ?? ""
        }
        TBStatusItem.shared.setTitle(title: canTogglePause && showTimerInMenuBar ? timeLeftString : nil)
    }

    private func startTimer(seconds: TimeInterval, at start: Date) {
        timer?.cancel()
        finishTime = start.addingTimeInterval(seconds)

        let queue = DispatchQueue(label: "Timer")
        let source = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        source.schedule(deadline: .now(), repeating: .seconds(1), leeway: .never)
        source.setEventHandler { [weak self] in self?.onTimerTick() }
        timer = source
        source.resume()
        updateTimeLeft()
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
        finishTime = nil
        updateTimeLeft()
    }

    func onTimerTick() {
        /* Cannot publish updates from background thread */
        DispatchQueue.main.async { [self] in
            guard let finishTime = finishTime else { return }
            updateTimeLeft()
            let timeLeft = finishTime.timeIntervalSince(now())
            if timeLeft <= 0 {
                /*
                 Ticks can be missed during the machine sleep.
                 Stop the timer if it goes beyond an overrun time limit.
                 */
                transition(timeLeft < overrunTimeLimit ? .startStop : .timerFired)
            }
        }
    }

    private func onNotificationAction(action: TBNotification.Action) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, action == .skipRest, self.isResting else { return }
            self.skipInterval()
        }
    }

    private func onWorkStart(context: TBStateMachine.Context) {
        TBStatusItem.shared.setIcon(name: .work, tint: .systemRed)
        if context.event != .resume {
            player.playWindup()
        }
        player.startTicking()
        startInterval(minutes: workIntervalLength, context: context)
    }

    private func startInterval(minutes: Int, context: TBStateMachine.Context) {
        let seconds = pausedInterval?.remaining ?? TimeInterval(minutes * 60)
        pausedInterval = nil
        startTimer(seconds: seconds, at: transitionTime(context))
    }

    private func onPause(context: TBStateMachine.Context) {
        let remaining = max(0, finishTime?.timeIntervalSince(transitionTime(context)) ?? 0)
        pausedInterval = (context.fromState, remaining)
        stopTimer()
        let icon = context.fromState == .rest ? restIcon : .work
        TBStatusItem.shared.setIcon(name: icon, tint: Self.pauseColor)
    }

    private func onWorkFinish(context: TBStateMachine.Context) {
        consecutiveWorkIntervals += 1
        if context.event == .timerFired {
            player.playDing()
        }
    }

    private func onWorkEnd(context _: TBStateMachine.Context) {
        player.stopTicking()
    }

    private func onRestStart(context: TBStateMachine.Context) {
        if context.event == .resume {
            TBStatusItem.shared.setIcon(name: restIcon, tint: .systemGray)
            startInterval(minutes: shortRestIntervalLength, context: context)
            return
        }
        var body = NSLocalizedString("TBTimer.onRestStart.short.body", comment: "Short break body")
        var length = shortRestIntervalLength
        var imgName = NSImage.Name.shortRest
        if consecutiveWorkIntervals >= workIntervalsInSet {
            body = NSLocalizedString("TBTimer.onRestStart.long.body", comment: "Long break body")
            length = longRestIntervalLength
            imgName = .longRest
            consecutiveWorkIntervals = 0
        }
        if context.event == .timerFired {
            notificationCenter.send(
                title: NSLocalizedString("TBTimer.onRestStart.title", comment: "Time's up title"),
                body: body,
                category: .restStarted
            )
        }
        restIcon = imgName
        TBStatusItem.shared.setIcon(name: restIcon, tint: .systemGray)
        startInterval(minutes: length, context: context)
    }

    private func onRestFinish(context ctx: TBStateMachine.Context) {
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
        pausedInterval = nil
        stopTimer()
        TBStatusItem.shared.setIcon(name: .idle)
        consecutiveWorkIntervals = 0
    }
}
