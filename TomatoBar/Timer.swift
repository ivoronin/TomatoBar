import Cocoa
import Defaults
import Foundation
import SwiftState

typealias TimerChangeHandler = (TBStateMachine.Context) -> Void
typealias TimerTickHandler = () -> Void

class TBTimer {
    public var finishTime: Date!
    private var state: TBStateMachineStates {
        stateMachine.state
    }

    private var stateMachine = TBStateMachine(state: .idle)
    private let player = TBPlayer()
    private var consecutiveWorkIntervals: Int = 0
    private var timer: DispatchSourceTimer?
    private var tickHandler: TimerTickHandler!
    private var preset: TBPreset

    init(preset: TBPreset) {
        self.preset = preset

        /*
         * State diagram
         *
         *                 start/stop
         *       +--------------+-------------+
         *       |              |             |
         *       |  start/stop  |  timerFired |
         *       V    |         |    |        |
         * +--------+ |  +--------+  | +------------------+
         * | idle   |--->| work   |--->| (short|long)Rest |
         * +--------+    +--------+    +------------------+
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
            .idle => .work, .work => .idle, .shortRest => .idle, .longRest => .idle,
        ])
        stateMachine.addRoutes(event: .timerFired, transitions: [.work => .shortRest]) { _ in
            self.consecutiveWorkIntervals < preset.setSize
        }
        stateMachine.addRoutes(event: .timerFired, transitions: [.work => .longRest]) { _ in
            self.consecutiveWorkIntervals >= preset.setSize
        }
        stateMachine.addRoutes(event: .timerFired, transitions: [.shortRest => .idle]) { _ in
            Defaults[.stopAfterBreak]
        }
        stateMachine.addRoutes(event: .timerFired, transitions: [.shortRest => .work]) { _ in
            !Defaults[.stopAfterBreak]
        }
        stateMachine.addRoutes(event: .skipRest, transitions: [.shortRest => .work])
        stateMachine.addRoutes(event: .skipRest, transitions: [.longRest => .work])

        /*
         * "Finish" handlers are called when time interval ended
         * "End"    handlers are called when time interval ended or was cancelled
         */
        stateMachine.addAnyHandler(.any => .work, handler: onWorkStart)
        stateMachine.addAnyHandler(.work => .shortRest, order: 0, handler: onWorkFinish)
        stateMachine.addAnyHandler(.work => .any, order: 1, handler: onWorkEnd)
        stateMachine.addAnyHandler(.any => .shortRest, handler: onShortRestStart)
        stateMachine.addAnyHandler(.any => .longRest, handler: onLongRestStart)
        stateMachine.addAnyHandler(.any => .idle, handler: onIdleStart)

        stateMachine.addErrorHandler { ctx in fatalError("state machine context: <\(ctx)>") }

        Defaults.observe(.isTickingEnabled, handler: toggleTicking).tieToLifetime(of: self)
    }

    func addChangeHandler(handler: @escaping TimerChangeHandler) {
        stateMachine.addAnyHandler(.any => .any, order: 99, handler: handler)
    }

    func addTickHandler(handler: @escaping TimerTickHandler) {
        tickHandler = handler
    }

    func startStop() {
        stateMachine <-! .startStop
    }

    func skipRest() {
        if [.shortRest, .longRest].contains(state) {
            stateMachine <-! .skipRest
        }
    }

    private func toggleTicking(change: Defaults.KeyChange<Bool>) {
        print("toggleTicking", change)
        if stateMachine.state != .work {
            return
        }
        if change.newValue {
            player.startTicking()
        } else {
            player.stopTicking()
        }
    }

    private func startTimer(seconds: Int) {
        finishTime = Date().addingTimeInterval(TimeInterval(seconds))

        let queue = DispatchQueue(label: "Timer")
        timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer!.schedule(deadline: .now(), repeating: .seconds(1), leeway: .never)
        timer!.setEventHandler(handler: onTimerTick)
        timer!.resume()
    }

    private func stopTimer() {
        timer!.cancel()
        timer = nil
    }

    private func onTimerTick() {
        /* Cannot publish updates from background thread */
        DispatchQueue.main.async { [self] in
            self.tickHandler()
            let seconds = secondsUntil(date: finishTime)
            if seconds <= 0 {
                /*
                 Ticks can be missed during the machine sleep.
                 Stop the timer if it goes beyond an overrun time limit.
                 */
                if seconds < Defaults[.overrunTimeLimit] {
                    stateMachine <-! .startStop
                } else {
                    stateMachine <-! .timerFired
                }
            }
        }
    }

    private func onWorkStart(context _: TBStateMachine.Context) {
        // TBStatusItem.shared.setIcon(name: .work)
        if Defaults[.isWindupEnabled] {
            player.playWindup()
        }
        if Defaults[.isTickingEnabled] {
            player.startTicking()
        }
        startTimer(seconds: preset.work * 60)
    }

    private func onWorkFinish(context _: TBStateMachine.Context) {
        consecutiveWorkIntervals += 1
        if Defaults[.isDingEnabled] {
            player.playDing()
        }
    }

    private func onWorkEnd(context _: TBStateMachine.Context) {
        player.stopTicking()
    }

    private func onShortRestStart(context _: TBStateMachine.Context) {
        startTimer(seconds: preset.shortRest * 60)
    }

    private func onLongRestStart(context _: TBStateMachine.Context) {
        startTimer(seconds: preset.longRest * 60)
    }

    private func onIdleStart(context _: TBStateMachine.Context) {
        stopTimer()
        consecutiveWorkIntervals = 0
    }
}
