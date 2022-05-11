import Defaults
import KeyboardShortcuts
import SwiftUI

class TBViewModel: ObservableObject {
    @Published var timeLeftString: String = ""
    @Published var timerActive: Bool = false

    private var timer: TBTimer
    private var presets = TBPresets()
    private var notificationCenter = TBNotificationCenter()

    init() {
        timer = TBTimer(presets: presets)
        timer.addChangeHandler(handler: onTimerChange)
        timer.addTickHandler(handler: updateTimeLeft)
        KeyboardShortcuts.onKeyUp(for: .startStopTimer, action: startStop)
        notificationCenter.setActionHandler(handler: onNotificationAction)
        Defaults.observe(.showTimerInMenuBar) { _ in
            self.updateTimeLeft()
        }.tieToLifetime(of: self)
    }

    public func startStop() {
        timer.startStop()
    }

    private func skipRest() {
        timer.skipRest()
    }

    func updateTimeLeft() {
        if !timerActive {
            return
        }
        let seconds = secondsUntil(date: timer.finishTime)
        timeLeftString = String(
            format: "%.2i:%.2i",
            seconds / 60,
            seconds % 60
        )
        TBStatusItem.shared.setTitle(title: Defaults[.showTimerInMenuBar] ? timeLeftString : nil)
    }

    private func onNotificationAction(action: TBNotification.Action) {
        switch action {
        case .skipRest:
            skipRest()
        }
    }

    func onTimerChange(context ctx: TBStateMachine.Context) {
        switch ctx.toState {
        case .idle:
            TBStatusItem.shared.setIcon(name: .idle)
            timerActive = false
        case .work:
            if [.shortRest, .longRest].contains(ctx.fromState) {
                notificationCenter.send(
                    title: "Break is over",
                    body: "Keep up the good work!",
                    category: .restFinished
                )
            }
            timerActive = true
        case .shortRest:
            notificationCenter.send(
                title: "Time's up",
                body: "It's time for a short break!",
                category: .restStarted
            )
            TBStatusItem.shared.setIcon(name: .shortRest)
            timerActive = true
        case .longRest:
            notificationCenter.send(
                title: "Time's up",
                body: "It's time for a long break!",
                category: .restStarted
            )
            TBStatusItem.shared.setIcon(name: .longRest)
            timerActive = true
        }
    }
}
