// swiftlint:disable prohibited_interface_builder
// swiftlint:disable explicit_type_interface
// swiftlint:disable required_deinit
import Cocoa
import os.log
import SwiftState

public class TomatoBarController: NSViewController {
    private typealias TomatoBarContext = StateMachine<TomatoBarState, TomatoBarEvent>.Context
    private enum TomatoBarState: StateType {
        case ready, idle, work, rest
    }
    private enum TomatoBarEvent: EventType {
        case startStop, timerFired
    }

    private var stateMachine = StateMachine<TomatoBarState, TomatoBarEvent>(state: .ready)
    private var timeLeftSeconds: Int = 0
    private let timeLeftFont = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)
    private var timer: DispatchSourceTimer?
    private var statusItem: NSStatusItem?
    private var statusBarButton: NSButton? { statusItem?.button }

    private let settings = TomatoBarSettings.shared
    private let player = TomatoBarPlayer.shared

    @IBOutlet private var statusMenu: NSMenu!
    @IBOutlet private var touchBarItem: NSTouchBarItem!
    @IBOutlet private var touchBarButton: NSButton!
    @IBOutlet private var startMenuItem: NSMenuItem!
    @IBOutlet private var stopMenuItem: NSMenuItem!

    /* Loaded because of the fake view */
    override public func viewDidLoad() {
        super.viewDidLoad()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.alignment = .right
        // swiftlint:disable:next discouraged_object_literal
        statusBarButton?.image = #imageLiteral(resourceName: "BarIcon")
        statusItem?.menu = statusMenu

        /* Initialize touch bar, WARNING: uses private framework methods */
        NSTouchBarItem.addSystemTrayItem(touchBarItem)
        DFRElementSetControlStripPresenceForIdentifier(touchBarItem.identifier.rawValue, true)

        stateMachine.addRoute(.ready => .idle)
        stateMachine.addRoutes(event: .startStop, transitions: [
            .idle => .work, .work => .idle, .rest => .idle
        ])
        stateMachine.addRoutes(event: .timerFired, transitions: [.work => .rest])
        stateMachine.addRoutes(event: .timerFired, transitions: [.rest => .idle]) { _ in
            self.settings.stopAfterBreak
        }
        stateMachine.addRoutes(event: .timerFired, transitions: [.rest => .work]) { _ in
            !self.settings.stopAfterBreak
        }

        stateMachine.addAnyHandler(.any => .work, handler: onWorkStart)
        stateMachine.addAnyHandler(.work => .rest, order: 0, handler: onWorkFinish)
        stateMachine.addAnyHandler(.work => .any, order: 1, handler: onWorkEnd)
        stateMachine.addAnyHandler(.any => .rest, handler: onRestStart)
        stateMachine.addAnyHandler(.rest => .work, handler: onRestFinish)
        stateMachine.addAnyHandler(.any => .idle, handler: onIdleStart)

        stateMachine.addErrorHandler { ctx in
            fatalError(
                """
                stateMachine error: \
                transition \(ctx.fromState) => \(ctx.toState), \
                event \(String(describing: ctx.event)), \
                userInfo \(String(describing: ctx.userInfo))
                """
            )
        }

        stateMachine <- .idle
    }

    /** Called on Touch Bar button and Start and Stop menu items clicks */
    @IBAction private func startStopAction(_ sender: Any) {
        stateMachine <-! .startStop
    }

    /** Called when user clicks on the "Ticking sound" checkbox */
    @IBAction private func toggleTickingAction(_ sender: Any) {
        if stateMachine.state == .work {
            player.toggleTicking()
        }
    }

    private func startTimer(seconds: Int) {
        touchBarButton.imagePosition = .noImage
        statusBarButton?.imagePosition = .imageLeft
        startMenuItem.isHidden = true
        stopMenuItem.isHidden = false

        timeLeftSeconds = seconds

        let queue = DispatchQueue(label: "Timer")
        timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer?.schedule(deadline: .now(), repeating: .seconds(1), leeway: .never)
        timer?.setEventHandler(handler: onTimerTick)
        timer?.resume()
    }

    /** Called every second by the timer */
    private func onTimerTick() {
        timeLeftSeconds -= 1
        DispatchQueue.main.async {
            if self.timeLeftSeconds >= 0 {
                let buttonTitle = NSAttributedString(
                    string: String(
                        format: "%.2i:%.2i",
                        self.timeLeftSeconds / 60,
                        self.timeLeftSeconds % 60
                    ),
                    attributes:
                        [NSAttributedString.Key.font: self.timeLeftFont]
                )
                self.touchBarButton.attributedTitle = buttonTitle
                self.statusBarButton?.attributedTitle = buttonTitle
            } else {
                self.stateMachine <-! .timerFired
            }
        }
    }

    private func onWorkStart(context: TomatoBarContext) {
        player.playWindup()
        player.startTicking()
        touchBarButton.bezelColor = NSColor.systemGreen
        startTimer(seconds: settings.workIntervalLength * 60)
    }

    private func onWorkFinish(context: TomatoBarContext) {
        sendNotication(title: "Time's up", text: "It's time for a break!")
        player.playRinging()
    }

    private func onWorkEnd(context: TomatoBarContext) {
        player.stopTicking()
    }

    private func onRestStart(context: TomatoBarContext) {
        touchBarButton.bezelColor = NSColor.systemYellow
        startTimer(seconds: settings.restIntervalLength * 60)
    }

    private func onRestFinish(context: TomatoBarContext) {
        sendNotication(title: "Break is over", text: "Keep up the good work!")
    }

    private func onIdleStart(context: TomatoBarContext) {
        touchBarButton.imagePosition = .imageOnly
        touchBarButton.bezelColor = NSColor.clear
        statusBarButton?.imagePosition = .imageOnly
        startMenuItem.isHidden = false
        stopMenuItem.isHidden = true

        if timer != nil {
            timer?.cancel()
            timer = nil
        }
    }

    private func sendNotication(title: String, text: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = text
        NSUserNotificationCenter.default.deliver(notification)
    }
}
