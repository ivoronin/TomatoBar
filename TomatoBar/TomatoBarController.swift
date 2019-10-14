import AVFoundation
import Cocoa
import os.log

public class TomatoBarController: NSViewController {
    /** Is sound enabled flag */
    private var isSoundEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "isSoundEnabled")
    }
    
    /** Is working flag */
    private var isResting: Bool {
        return UserDefaults.standard.bool(forKey: "isResting")
    }

    /** Working interval length, in minutes */
    private var intervalLengthMinutes: Int {
        return UserDefaults.standard.integer(forKey: "workingIntervalLength")
    }
    /** Working interval length as seconds */
    private var intervalLengthSeconds: Int { return intervalLengthMinutes * 60 }
    
    /** Resting interval length, in minutes */
    private var restingIntervalLengthMinutes: Int {
        return UserDefaults.standard.integer(forKey: "restingIntervalLength")
    }
    /** Resting interval length as seconds */
    private var restingIntervalLengthSeconds: Int { return restingIntervalLengthMinutes * 60 }

    /** Time left, in seconds */
    private var timeLeftSeconds: Int = 0
    /** Time left as MM:SS */
    private var timeLeftString: String {
        return String(format: "%.2i:%.2i", timeLeftSeconds / 60, timeLeftSeconds % 60)
    }
    /** Timer instance */
    private var timer: DispatchSourceTimer?

    /** Status bar item */
    public var statusItem: NSStatusItem?
    /** Status bar button */
    private var statusBarButton: NSButton? {
        return statusItem?.button
    }

    /* Sounds */
    private let windupSound: AVAudioPlayer
    private let ringingSound: AVAudioPlayer

    @IBOutlet private var statusMenu: NSMenu!
    @IBOutlet private var touchBarItem: NSTouchBarItem!
    @IBOutlet private var touchBarButton: NSButton!
    @IBOutlet private var startMenuItem: NSMenuItem!
    @IBOutlet private var stopMenuItem: NSMenuItem!
    @IBOutlet private var isSoundEnabledCheckBox: NSButton!

    required public init?(coder: NSCoder) {
        /* Init sounds */
        guard let windupSoundAsset: NSDataAsset = NSDataAsset(name: NSDataAsset.Name(rawValue: "windup")),
            let ringingSoundAsset: NSDataAsset = NSDataAsset(name: NSDataAsset.Name(rawValue: "ringing"))
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
        UserDefaults.standard.register(defaults: ["workingIntervalLength": 25,
                                                  "isSoundEnabled": true,
                                                  "restingIntervalLength": 5])

        /* Initialize status bar */
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.alignment = .right
        statusBarButton?.image = NSImage(named: NSImage.Name("BarIcon"))
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
        touchBarButton.bezelColor = NSColor.systemGreen
        statusBarButton?.imagePosition = .imageLeft
        swap(&startMenuItem.isHidden, &stopMenuItem.isHidden)
        statusItem?.length = 70

        /* Start timer */
        timeLeftSeconds = isResting ? restingIntervalLengthSeconds : intervalLengthSeconds
        let queue: DispatchQueue = DispatchQueue(label: "Timer")
        timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer?.schedule(deadline: .now(), repeating: .seconds(1), leeway: .never)
        timer?.setEventHandler(handler: self.tick)
        timer?.resume()

        playSound(windupSound)
    }

    /** Called on interval finish */
    private func finish() {
        sendNotication()
        reset()
        playSound(ringingSound)
        UserDefaults.standard.set(!isResting, forKey: "isResting")
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
        let notification: NSUserNotification = NSUserNotification()
        notification.title = "Time's up"
        notification.informativeText = "Keep up the good work!"
        NSUserNotificationCenter.default.deliver(notification)
    }
}
