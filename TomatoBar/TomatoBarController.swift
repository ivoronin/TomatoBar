// swiftlint:disable prohibited_interface_builder
import AVFoundation
import Cocoa
import os.log

public class TomatoBarController: NSViewController {
    /** TomatoBar mode */
    public enum Mode {
        /** Idle */
        case idle
        /** Working */
        case work
        /** Resting, should be named "break", but it's a reserved work :) */
        case rest
    }

    /** Current mode (interval or break) */
    private var currentMode: Mode = .idle

    /** Is sound enabled flag */
    private var isSoundEnabled: Bool {
        UserDefaults.standard.bool(forKey: "isSoundEnabled")
    }

    private var stopAfterBreak: Bool {
        UserDefaults.standard.bool(forKey: "stopAfterBreak")
    }

    /** Interval length, in minutes */
    private var workIntervalLengthMinutes: Int {
        UserDefaults.standard.integer(forKey: "workIntervalLength")
    }
    /** Interval length as seconds */
    private var workIntervalLengthSeconds: Int { workIntervalLengthMinutes * 60 }

    /** Break length, in minutes */
    private var restIntervalLengthMinutes: Int {
        UserDefaults.standard.integer(forKey: "restIntervalLength")
    }
    /** Break length as seconds */
    private var restIntervalLengthSeconds: Int { restIntervalLengthMinutes * 60 }

    /** Time left, in seconds */
    private var timeLeftSeconds: Int = 0
    // swiftlint:disable:next explicit_type_interface
    private var timeLeftFont = NSFont.monospacedDigitSystemFont(
        ofSize: 0, weight: .regular
    )
    /** Time left as MM:SS */
    private var timeLeftString: NSAttributedString {
        NSAttributedString(
            string: String(format: "%.2i:%.2i", timeLeftSeconds / 60, timeLeftSeconds % 60),
            attributes: [NSAttributedString.Key.font: self.timeLeftFont]
        )
    }
    /** Timer instance */
    private var timer: DispatchSourceTimer?

    /** Status bar item */
    public var statusItem: NSStatusItem?
    /** Status bar button */
    private var statusBarButton: NSButton? {
        statusItem?.button
    }

    /* Sounds */
    private let windupSound: AVAudioPlayer
    private let ringingSound: AVAudioPlayer

    @IBOutlet private var statusMenu: NSMenu!
    @IBOutlet private var touchBarItem: NSTouchBarItem!
    @IBOutlet private var touchBarButton: NSButton!
    @IBOutlet private var startMenuItem: NSMenuItem!
    @IBOutlet private var stopMenuItem: NSMenuItem!

    public required init?(coder: NSCoder) {
        /* Init sounds */
        guard let windupSoundAsset = NSDataAsset(name: "windup"),
            let ringingSoundAsset = NSDataAsset(name: "ringing")
            else {
                os_log("Unable to load sound data assets")
                return nil
        }

        do {
            windupSound = try AVAudioPlayer(data: windupSoundAsset.data)
            ringingSound = try AVAudioPlayer(data: ringingSoundAsset.data)
        } catch {
            os_log("Unable to create player instances: %{public}@", error.localizedDescription)
            return nil
        }

        windupSound.prepareToPlay()
        ringingSound.prepareToPlay()

        super.init(coder: coder)
    }

    /* Loaded because of fake view */
    override public func viewDidLoad() {
        super.viewDidLoad()
        /* Register defaults */
        UserDefaults.standard.register(defaults: [
            "workIntervalLength": 25,
            "restIntervalLength": 5,
            "isSoundEnabled": true,
            "stopAfterBreak": false
        ])

        /* Initialize status bar */
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.alignment = .right
        // swiftlint:disable:next discouraged_object_literal
        statusBarButton?.image = #imageLiteral(resourceName: "BarIcon")
        statusItem?.menu = statusMenu

        /* Initialize touch bar, WARNING: uses private framework methods */
        NSTouchBarItem.addSystemTrayItem(touchBarItem)
        DFRElementSetControlStripPresenceForIdentifier(touchBarItem.identifier.rawValue, true)
    }

    /** Called on Touch Bar button and Start and Stop menu items clicks */
    @IBAction private func startStopAction(_ sender: Any) {
        currentMode == .idle ? start(mode: .work) : cancel()
    }

    private func setMode(mode: Mode) {
        switch mode {
        case .idle:
            touchBarButton.imagePosition = .imageOnly
            touchBarButton.bezelColor = NSColor.clear
            statusBarButton?.imagePosition = .imageOnly
            startMenuItem.isHidden = false
            stopMenuItem.isHidden = true
            statusItem?.length = NSStatusItem.variableLength

        case .work:
            touchBarButton.imagePosition = .noImage
            touchBarButton.bezelColor = NSColor.systemGreen
            statusBarButton?.imagePosition = .imageLeft
            startMenuItem.isHidden = true
            stopMenuItem.isHidden = false
            statusItem?.length = 70

        case .rest:
            touchBarButton.bezelColor = NSColor.systemYellow
        }
        currentMode = mode
    }

    /** Starts interval */
    private func start(mode: Mode) {
        switch mode {
        case .work:
            timeLeftSeconds = workIntervalLengthSeconds

        case .rest:
            timeLeftSeconds = restIntervalLengthSeconds

        default:
            fatalError("Unexpected mode")
        }
        setMode(mode: mode)

        // swiftlint:disable:next explicit_type_interface
        let queue = DispatchQueue(label: "Timer")
        timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer?.schedule(deadline: .now(), repeating: .seconds(1), leeway: .never)
        timer?.setEventHandler(handler: self.tick)
        timer?.resume()

        playSound(windupSound)
    }

    /** Called on interval finish */
    private func finish() {
        assert(currentMode != .idle)
        sendNotication()
        playSound(ringingSound)
        switch currentMode {
        case .work:
            start(mode: .rest)

        case .rest:
            stopAfterBreak ? cancel() : start(mode: .work)

        default:
            fatalError("Unexpected mode")
        }
    }

    /** Cancels interval */
    private func cancel() {
        assert(currentMode != .idle)
        /* Reset timer */
        timer?.cancel()
        timer = nil

        setMode(mode: .idle)
    }

    /** Called every second by timer */
    private func tick() {
        assert(currentMode != .idle)
        timeLeftSeconds -= 1
        DispatchQueue.main.async {
            if self.timeLeftSeconds >= 0 {
                self.touchBarButton.attributedTitle = self.timeLeftString
                self.statusBarButton?.attributedTitle = self.timeLeftString
            } else {
                self.finish()
            }
        }
    }

    /** Plays sound */
    private func playSound(_ sound: AVAudioPlayer) {
        if isSoundEnabled {
            sound.play()
        }
    }

    /** Sends notification */
    private func sendNotication() {
        // swiftlint:disable:next explicit_type_interface
        let notification = NSUserNotification()
        notification.title = "Time's up"
        switch currentMode {
        case .work:
            notification.informativeText = "It's time for a break!"

        case .rest:
            notification.informativeText = "Keep up the good work!"

        default:
            fatalError("Unexpected mode")
        }
        NSUserNotificationCenter.default.deliver(notification)
    }

    deinit { }
}
