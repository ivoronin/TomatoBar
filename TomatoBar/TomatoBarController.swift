// swiftlint:disable prohibited_interface_builder
import AVFoundation
import Cocoa
import os.log

/** TomatoBar mode */
public enum TomatoBarMode {
    /** Working */
    case work
    /** Resting */
    case rest
}

public class TomatoBarController: NSViewController {
    /** Is sound enabled flag */
    private var isSoundEnabled: Bool {
        UserDefaults.standard.bool(forKey: "isSoundEnabled")
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

    /** Current mode (interval or break) */
    private var currentMode: TomatoBarMode = .work

    /** Time left, in seconds */
    private var timeLeftSeconds: Int = 0
    /** Time left as MM:SS */
    private var timeLeftString: String {
        String(format: "%.2i:%.2i", timeLeftSeconds / 60, timeLeftSeconds % 60)
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
            "isSoundEnabled": true
        ])

        /* Initialize status bar */
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.alignment = .right
        // swiftlint:disable:next discouraged_object_literal
        statusBarButton?.image = #imageLiteral(resourceName: "BarIcon")
        statusBarButton?.imagePosition = .imageOnly
        statusItem?.menu = statusMenu

        /* Initialize touch bar, WARNING: uses private framework methods */
        NSTouchBarItem.addSystemTrayItem(touchBarItem)
        DFRElementSetControlStripPresenceForIdentifier(touchBarItem.identifier.rawValue, true)
    }

    /** Called on Touch Bar button and Start and Stop menu items clicks */
    @IBAction private func startStopAction(_ sender: Any) {
        timer == nil ? start() : cancel()
    }

    /** Starts interval */
    private func start() {
        /* Prepare UI */
        touchBarButton.imagePosition = .noImage
        if currentMode == .work {
            touchBarButton.bezelColor = NSColor.systemGreen
        } else {
            touchBarButton.bezelColor = NSColor.systemYellow
        }
        statusBarButton?.imagePosition = .imageLeft
        swap(&startMenuItem.isHidden, &stopMenuItem.isHidden)
        statusItem?.length = 70

        /* Start timer */
        if currentMode == .work {
            timeLeftSeconds = workIntervalLengthSeconds
        } else {
            timeLeftSeconds = restIntervalLengthSeconds
        }
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
        sendNotication()
        playSound(ringingSound)
        if currentMode == .work {
            currentMode = .rest
        } else {
            currentMode = .work
        }
        start()
    }

    /** Cancels interval */
    private func cancel() {
        reset()
    }

    /** Resets controller to initial state */
    private func reset() {
        /* Reset timer */
        timer?.cancel()
        timer = nil

        currentMode = .work

        /* Reset UI */
        touchBarButton.imagePosition = .imageOnly
        touchBarButton.bezelColor = NSColor.clear
        statusBarButton?.imagePosition = .imageOnly
        swap(&startMenuItem.isHidden, &stopMenuItem.isHidden)
        statusItem?.length = NSStatusItem.variableLength
    }

    /** Called every second by timer */
    private func tick() {
        timeLeftSeconds -= 1
        DispatchQueue.main.async {
            if self.timeLeftSeconds >= 0 {
                self.touchBarButton.title = self.timeLeftString
                self.statusBarButton?.title = self.timeLeftString
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
        if currentMode == .work {
            notification.informativeText = "It's time for a break!"
        } else {
            notification.informativeText = "Keep up the good work!"
        }
        NSUserNotificationCenter.default.deliver(notification)
    }

    deinit { }
}
