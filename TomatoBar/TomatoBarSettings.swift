// swiftlint:disable explicit_type_interface
// swiftlint:disable missing_docs
// swiftlint:disable required_deinit
import Foundation

public class TomatoBarSettings {
    public static let shared = TomatoBarSettings()

    private var defaults = UserDefaults.standard
    public var isRingingEnabled: Bool { defaults.bool(forKey: "isRingingEnabled") }
    public var isTickingEnabled: Bool { defaults.bool(forKey: "isTickingEnabled") }
    public var stopAfterBreak: Bool { defaults.bool(forKey: "stopAfterBreak") }
    public var workIntervalLength: Int { defaults.integer(forKey: "workIntervalLength") }
    public var restIntervalLength: Int { defaults.integer(forKey: "restIntervalLength") }

    public required init() {
        defaults.register(defaults: [
            "workIntervalLength": 25,
            "restIntervalLength": 5,
            "isRingingEnabled": true,
            "isTickingEnabled": true,
            "stopAfterBreak": false
        ])
    }
}
