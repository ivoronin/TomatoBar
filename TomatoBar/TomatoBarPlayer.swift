// swiftlint:disable explicit_type_interface
// swiftlint:disable missing_docs
// swiftlint:disable required_deinit
import AVFoundation
import Foundation

public class TomatoBarPlayer {
    public static let shared = TomatoBarPlayer()

    private let settings = TomatoBarSettings.shared

    private var windupSound: AVAudioPlayer
    private var ringingSound: AVAudioPlayer
    private var tickingSound: AVAudioPlayer

    public required init() {
        let windupSoundAsset = NSDataAsset(name: "windup")
        let ringingSoundAsset = NSDataAsset(name: "ringing")
        let tickingSoundAsset = NSDataAsset(name: "ticking")
        // swiftlint:disable force_try force_unwrapping
        windupSound = try! AVAudioPlayer(data: windupSoundAsset!.data, fileTypeHint: "wav")
        ringingSound = try! AVAudioPlayer(data: ringingSoundAsset!.data, fileTypeHint: "wav")
        tickingSound = try! AVAudioPlayer(data: tickingSoundAsset!.data, fileTypeHint: "wav")
        // swiftlint:enable force_try force_unwrapping
        windupSound.prepareToPlay()
        ringingSound.prepareToPlay()
        tickingSound.numberOfLoops = -1
        tickingSound.prepareToPlay()
    }

    public func playWindup() {
        if settings.isWindupEnabled {
            windupSound.play()
        }
    }

    public func playRinging() {
        if settings.isRingingEnabled {
            ringingSound.play()
        }
    }

    public func startTicking() {
        if settings.isTickingEnabled {
            tickingSound.play()
        }
    }

    public func stopTicking() {
        tickingSound.stop()
    }

    public func toggleTicking() {
        if tickingSound.isPlaying {
            stopTicking()
        } else {
            startTicking()
        }
    }
}
