import SwiftUI

private class TBRestOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

class TBRestOverlayViewModel: ObservableObject {
    @Published var restType: TBRestOverlayController.RestType
    @Published var countdown: String

    init(restType: TBRestOverlayController.RestType, countdown: String) {
        self.restType = restType
        self.countdown = countdown
    }
}

class TBRestOverlayController {
    enum RestType {
        case shortRest
        case longRest
    }

    private var windows: [NSWindow] = []
    private var viewModel: TBRestOverlayViewModel?

    func showOverlays(
        restType: RestType,
        countdown: String,
        backgroundImageName: String? = nil,
        skipHandler: @escaping () -> Void
    ) {
        closeOverlays()

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let viewModel = TBRestOverlayViewModel(restType: restType, countdown: countdown)
        self.viewModel = viewModel

        for screen in screens {
            let window = createOverlayWindow(for: screen)
            let overlayView = TBRestOverlayView(
                viewModel: viewModel,
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
        viewModel?.countdown = text
    }

    func closeOverlays() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        viewModel = nil
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
