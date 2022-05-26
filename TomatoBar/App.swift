import SwiftUI

extension NSImage.Name {
    static let idle = Self("BarIconIdle")
    static let work = Self("BarIconWork")
    static let shortRest = Self("BarIconShortRest")
    static let longRest = Self("BarIconLongRest")
}

private let digitFont = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)

@main
struct TBApp: App {
    @NSApplicationDelegateAdaptor(TBStatusItem.self) var appDelegate

    init() {
        TBStatusItem.shared = appDelegate
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class TBStatusItem: NSObject, NSApplicationDelegate {
    private var statusBarItem: NSStatusItem?
    static var shared: TBStatusItem!

    func applicationDidFinishLaunching(_: Notification) {
        let tbPopoverView = TBPopoverView()
        let tbPopoverNSView = NSHostingView(rootView: tbPopoverView)
        
        statusBarItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        statusBarItem?.button?.imagePosition = .imageLeft
        setIcon(name: .idle)
        statusBarItem?.menu = createMenu(from: tbPopoverNSView)
        statusBarItem?.menu?.delegate = self
    }

    func setTitle(title: String?) {
        let attributedTitle = NSAttributedString(
            string: title != nil ? " \(title!)" : "",
            attributes: [NSAttributedString.Key.font: digitFont]
        )
        statusBarItem?.button?.attributedTitle = attributedTitle
    }

    func setIcon(name: NSImage.Name) {
        statusBarItem?.button?.image = NSImage(named: name)
    }
}

// MARK: - View Actions
extension TBStatusItem: NSMenuDelegate {
    
    func menuWillOpen(_ menu: NSMenu) {
        // TODO: Need to figure out a way to make view of NSStatusItem key
        // guard let item = menu.item(at: 0) else { return }
        // item.view?.window?.makeKey()
        // item.view?.becomeFirstResponder()
    }

}

// MARK: - Helpers
extension TBStatusItem {
    
    private func createMenu(from view: NSView) -> NSMenu {
        view.translatesAutoresizingMaskIntoConstraints = false
        let contentView = NSView(frame: .init(x: 0, y: 0, width: 250, height: 250))
        contentView.addSubview(view)
        
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentView.topAnchor, constant: -8),
            view.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: -8),
        ])
        
        view.wantsLayer = true
        let menuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menuItem.view = contentView
        
        let menu = NSMenu()
        menu.addItem(menuItem)
        
        return menu
    }
    
}
