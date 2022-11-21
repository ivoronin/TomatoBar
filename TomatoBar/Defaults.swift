import Defaults

extension Defaults.Keys {
    static let isWindupEnabled = Key<Bool>("isWindupEnabled", default: true)
    static let isDingEnabled = Key<Bool>("isDingEnabled", default: true)
    static let isTickingEnabled = Key<Bool>("isTickingEnabled", default: false)
    static let stopAfterBreak = Key<Bool>("stopAfterBreak", default: false)
    static let showTimerInMenuBar = Key<Bool>("showTimerInMenuBar", default: false)
    static let currentPresetId = Key<String>("currentPresetId", default: standardPreset.id)
    // This preference is "hidden"
    static let overrunTimeLimit = Key<Int>("overrunTimeLimit", default: -60)
}
