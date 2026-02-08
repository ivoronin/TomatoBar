import ScriptingBridge
import Cocoa

@objc protocol ShortcutsEvents {
    @objc optional var shortcuts: SBElementArray { get }
}
@objc protocol Shortcut {
    @objc optional var name: String { get }
    @objc optional func run(withInput: Any?) -> Any?
}

extension SBApplication: ShortcutsEvents {}
extension SBObject: Shortcut {}

public func DoNotDisturb(state: Bool) -> Bool {
    guard
        let app: ShortcutsEvents = SBApplication(bundleIdentifier: "com.apple.shortcuts.events"),
        let shortcuts = app.shortcuts else {
        return false
    }

    guard let shortcut = shortcuts.object(withName: "macos-focus-mode") as? Shortcut else {
        return false
    }

    guard shortcut.name == "macos-focus-mode" else {
        if let shortcutURL = Bundle.main.url(forResource: "macos-focus-mode", withExtension: "shortcut") {
            NSWorkspace.shared.open(shortcutURL)
        }
        return false
    }

    let input = state ? "on" : "off"
    _ = shortcut.run?(withInput: input)

    return true
}
