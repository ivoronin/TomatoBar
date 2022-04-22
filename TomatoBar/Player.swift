import AppKit
import AVFoundation

class TBPlayer {
    private var windupSound: AVAudioPlayer
    private var dingSound: AVAudioPlayer
    private var tickingSound: AVAudioPlayer

    init() {
        let windupSoundAsset = NSDataAsset(name: "windup")
        let dingSoundAsset = NSDataAsset(name: "ding")
        let tickingSoundAsset = NSDataAsset(name: "ticking")

        let wav = AVFileType.wav.rawValue
        do {
            windupSound = try AVAudioPlayer(data: windupSoundAsset!.data, fileTypeHint: wav)
            dingSound = try AVAudioPlayer(data: dingSoundAsset!.data, fileTypeHint: wav)
            tickingSound = try AVAudioPlayer(data: tickingSoundAsset!.data, fileTypeHint: wav)
        } catch {
            fatalError("Error initializing players: \(error)")
        }

        windupSound.prepareToPlay()
        dingSound.prepareToPlay()
        tickingSound.numberOfLoops = -1
        tickingSound.prepareToPlay()
    }

    public func playWindup() {
        windupSound.play()
    }

    public func playDing() {
        dingSound.play()
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
