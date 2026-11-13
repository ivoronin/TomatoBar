// Test-only substitutes for UI, audio and system notifications. Timer.swift
// itself is compiled unchanged into the test target; no app is launched.
import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let startStopTimer = Self("startStopTimer")
}

extension NSImage.Name {
    static let idle = Self("BarIconIdle")
    static let work = Self("BarIconWork")
    static let shortRest = Self("BarIconShortRest")
    static let longRest = Self("BarIconLongRest")
}

class TBStatusItem {
    static let shared = TBStatusItem()
    func setIcon(name _: NSImage.Name, tint _: NSColor? = nil) {}
    func setTitle(title _: String?) {}
}

class TBPlayer {
    func playWindup() {}
    func startTicking() {}
    func stopTicking() {}
    func playDing() {}
}

enum TBNotification {
    enum Action { case skipRest }
    enum Category { case restStarted, restFinished }
}

class TBNotificationCenter {
    func setActionHandler(handler _: @escaping (TBNotification.Action) -> Void) {}
    func send(title _: String, body _: String, category _: TBNotification.Category) {}
}
