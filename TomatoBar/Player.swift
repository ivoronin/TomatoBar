import AVFoundation
import SwiftUI

enum TBSound: String {
    case windup, ding, ticking
}

class TBPlayer: ObservableObject {
    private var windupSound: AVAudioPlayer
    private var dingSound: AVAudioPlayer
    private var tickingSound: AVAudioPlayer
    private var isTicking = false
    private var previewingSound: TBSound?

    /* File names (without extension) of user-chosen sounds; absent means default */
    @Published private(set) var customSoundNames: [TBSound: String] = [:]
    private var customSoundURLs: [TBSound: URL] = [:]

    @AppStorage("windupVolume") var windupVolume: Double = 1.0 {
        didSet {
            setVolume(windupSound, windupVolume)
        }
    }
    @AppStorage("dingVolume") var dingVolume: Double = 1.0 {
        didSet {
            setVolume(dingSound, dingVolume)
        }
    }
    @AppStorage("tickingVolume") var tickingVolume: Double = 1.0 {
        didSet {
            setVolume(tickingSound, tickingVolume)
        }
    }

    private func setVolume(_ sound: AVAudioPlayer, _ volume: Double) {
        sound.setVolume(Float(volume), fadeDuration: 0)
    }

    init() {
        windupSound = TBPlayer.defaultPlayer(.windup)
        dingSound = TBPlayer.defaultPlayer(.ding)
        tickingSound = TBPlayer.defaultPlayer(.ticking)

        for sound in [TBSound.windup, .ding, .ticking] {
            guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey(sound)) else {
                continue
            }
            do {
                try loadCustomSound(sound, bookmark: bookmark)
            } catch {
                logger.append(event: TBLogEventSoundLoadError(sound: sound, error: error))
                UserDefaults.standard.removeObject(forKey: bookmarkKey(sound))
            }
        }

        setVolume(windupSound, windupVolume)
        setVolume(dingSound, dingVolume)
        setVolume(tickingSound, tickingVolume)
    }

    private static func defaultPlayer(_ sound: TBSound) -> AVAudioPlayer {
        let asset = NSDataAsset(name: sound.rawValue)
        do {
            return try preparedPlayer(
                AVAudioPlayer(data: asset!.data, fileTypeHint: AVFileType.wav.rawValue),
                sound
            )
        } catch {
            fatalError("Error initializing players: \(error)")
        }
    }

    private static func preparedPlayer(_ player: AVAudioPlayer, _ sound: TBSound) -> AVAudioPlayer {
        if sound == .ticking {
            player.numberOfLoops = -1
        }
        player.prepareToPlay()
        return player
    }

    private func bookmarkKey(_ sound: TBSound) -> String {
        return "\(sound.rawValue)SoundBookmark"
    }

    private func player(_ sound: TBSound) -> AVAudioPlayer {
        switch sound {
        case .windup: return windupSound
        case .ding: return dingSound
        case .ticking: return tickingSound
        }
    }

    private func volume(_ sound: TBSound) -> Double {
        switch sound {
        case .windup: return windupVolume
        case .ding: return dingVolume
        case .ticking: return tickingVolume
        }
    }

    private func replacePlayer(_ sound: TBSound, with newPlayer: AVAudioPlayer) {
        let oldPlayer = player(sound)
        oldPlayer.stop()
        switch sound {
        case .windup: windupSound = newPlayer
        case .ding: dingSound = newPlayer
        case .ticking: tickingSound = newPlayer
        }
        setVolume(newPlayer, volume(sound))
    }

    /* Resolves a security-scoped bookmark and swaps in a player for the file it points to */
    private func loadCustomSound(_ sound: TBSound, bookmark: Data) throws {
        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmark,
                          options: .withSecurityScope,
                          bookmarkDataIsStale: &isStale)
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let player = TBPlayer.preparedPlayer(try AVAudioPlayer(data: Data(contentsOf: url)), sound)
        if isStale {
            UserDefaults.standard.set(try makeBookmark(url), forKey: bookmarkKey(sound))
        }
        replacePlayer(sound, with: player)
        customSoundNames[sound] = url.deletingPathExtension().lastPathComponent
        customSoundURLs[sound] = url
    }

    private func makeBookmark(_ url: URL) throws -> Data {
        return try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                    includingResourceValuesForKeys: nil,
                                    relativeTo: nil)
    }

    func customSoundURL(_ sound: TBSound) -> URL? {
        return customSoundURLs[sound]
    }

    /* Uses a user-chosen file, falling back to the default sound if it can't be loaded */
    func setCustomSound(_ sound: TBSound, url: URL) {
        do {
            let bookmark = try makeBookmark(url)
            try loadCustomSound(sound, bookmark: bookmark)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey(sound))
        } catch {
            logger.append(event: TBLogEventSoundLoadError(sound: sound, error: error))
            resetSound(sound)
            return
        }
        preview(sound)
    }

    func resetSound(_ sound: TBSound) {
        UserDefaults.standard.removeObject(forKey: bookmarkKey(sound))
        customSoundNames[sound] = nil
        customSoundURLs[sound] = nil
        replacePlayer(sound, with: TBPlayer.defaultPlayer(sound))
        preview(sound)
    }

    /* While ticking, a swapped ticking sound just keeps looping; otherwise it plays once */
    private func preview(_ sound: TBSound) {
        stopPreview()
        let player = player(sound)
        if sound == .ticking {
            if isTicking {
                player.play()
                return
            }
            player.numberOfLoops = 0
        }
        player.currentTime = 0
        player.play()
        previewingSound = sound
    }

    func stopPreview() {
        guard let sound = previewingSound else {
            return
        }
        previewingSound = nil
        player(sound).stop()
        if sound == .ticking {
            tickingSound.numberOfLoops = -1
        }
    }

    func playWindup() {
        windupSound.play()
    }

    func playDing() {
        dingSound.play()
    }

    func startTicking() {
        if previewingSound == .ticking {
            stopPreview()
        }
        isTicking = true
        tickingSound.play()
    }

    func stopTicking() {
        isTicking = false
        tickingSound.stop()
    }
}
