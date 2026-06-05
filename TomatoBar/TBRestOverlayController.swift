import SwiftUI

private class TBRestOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

class TBRestOverlayController {
    enum RestType {
        case shortRest
        case longRest
    }

    private var windows: [NSWindow] = []
    private var skipHandler: (() -> Void)?

    func showOverlays(
        restType: RestType,
        countdown: String,
        backgroundImageName: String? = nil,
        skipHandler: @escaping () -> Void
    ) {
        closeOverlays()

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        self.skipHandler = skipHandler

        for screen in screens {
            let window = createOverlayWindow(for: screen)
            let overlayView = TBRestOverlayView(
                restType: restType,
                countdown: countdown,
                skipHandler: skipHandler,
                backgroundImageName: backgroundImageName
            )
            let hostingView = NSHostingView(rootView: overlayView)
            hostingView.frame = window.contentRect(forFrameRect: window.frame)
            window.contentView = hostingView
            window.orderFront(nil)
            windows.append(window)
        }
    }

    func updateCountdown(_ text: String) {
        for window in windows {
            guard let hostingView = window.contentView as? NSHostingView<TBRestOverlayView> else {
                continue
            }
            // Recreate the hosting view with updated countdown text
            let updatedView = TBRestOverlayView(
                restType: hostingView.rootView.restType,
                countdown: text,
                skipHandler: hostingView.rootView.skipHandler,
                backgroundImageName: hostingView.rootView.backgroundImageName
            )
            hostingView.rootView = updatedView
        }
    }

    func closeOverlays() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        skipHandler = nil
    }

    private func createOverlayWindow(for screen: NSScreen) -> NSWindow {
        let window = TBRestOverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .modalPanel
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenDisallowsTiling]
        window.isReleasedWhenClosed = false
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.hasShadow = false
        return window
    }
}