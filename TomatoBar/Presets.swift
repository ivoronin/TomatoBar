import Defaults
import SwiftUI

struct TBPreset {
    var id: String
    var name: String
    var work: Int
    var shortRest: Int
    var longRest: Int
    var setSize: Int
    var builtin: Bool
}

let standardPreset = TBPreset(
    id: "0FFAAA6E-649C-443C-8D25-F0A92EFD17B3",
    name: "Standard",
    work: 25,
    shortRest: 5,
    longRest: 15,
    setSize: 5,
    builtin: true
)

let rule5217Preset = TBPreset(
    id: "C3EFA3CC-B1E2-4CA2-9169-3BBCE721FF4F",
    name: "52/17 Rule",
    work: 52,
    shortRest: 17,
    longRest: 0,
    setSize: 0,
    builtin: true
)

class TBPresetStore {
    private static let builtinPresets: [TBPreset] = [
        standardPreset,
        rule5217Preset,
    ]

    static func load() -> [TBPreset] {
        var presets: [TBPreset] = []
        presets.append(contentsOf: builtinPresets)
        return presets
    }

    func save(presets _: [TBPreset]) {}
}
