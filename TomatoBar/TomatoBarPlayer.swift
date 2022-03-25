import AppKit
import AVFoundation
import Foundation

public class TomatoBarPlayer {
    private var windupSound: AVAudioPlayer
    private var ringingSound: AVAudioPlayer
    private var tickingSound: AVAudioPlayer

    init() {
        let windupSoundAsset = NSDataAsset(name: "windup")
        let ringingSoundAsset = NSDataAsset(name: "ringing")
        let tickingSoundAsset = NSDataAsset(name: "ticking")

        let wav = AVFileType.wav.rawValue
        // swiftlint:disable force_try
        windupSound = try! AVAudioPlayer(data: windupSoundAsset!.data, fileTypeHint: wav)
        ringingSound = try! AVAudioPlayer(data: ringingSoundAsset!.data, fileTypeHint: wav)
        tickingSound = try! AVAudioPlayer(data: tickingSoundAsset!.data, fileTypeHint: wav)
        // swiftlint:enable force_try

        windupSound.prepareToPlay()
        ringingSound.prepareToPlay()
        tickingSound.numberOfLoops = -1
        tickingSound.prepareToPlay()
    }

    public func playWindup() {
        windupSound.play()
    }

    public func playRinging() {
        ringingSound.play()
    }

    public func startTicking() {
        tickingSound.play()
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
