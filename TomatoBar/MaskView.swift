
import Cocoa

class MaskHelper {
    var windowControllers = [NSWindowController]()
    var dismissBlock: (() -> Void)?
    
    static let shared = MaskHelper()

    private init() {}
    
    func showMaskWindow(desc: String, dismissBlock: (() -> Void)? = nil) {
        self.dismissBlock = dismissBlock
        let screens = NSScreen.screens
        for screen in screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: true)
            window.level = .screenSaver
            window.collectionBehavior = .canJoinAllSpaces
            window.backgroundColor = NSColor.black.withAlphaComponent(0.2)
            let maskView = MaskView(desc: desc, frame: window.contentLayoutRect) { [weak self] in
                if let windowControllers = self?.windowControllers, windowControllers.isEmpty == false {
                    for wc in windowControllers {
                        wc.close()
                    }
                    self?.windowControllers.removeAll()
                    self?.dismissBlock?()
                }
            }
            window.contentView = maskView

            let windowController = NSWindowController(window: window)
            windowController.loadWindow()
            windowController.showWindow(nil)
            windowControllers.append(windowController)
            maskView.show()
        }
    }
    
    func hideMaskWindow() {
        for wc in windowControllers {
            guard let mask = wc.window?.contentView as? MaskView else { continue }
            mask.hide()
        }
    }
}

class MaskView: NSView {
    var dismissBlock: (() -> Void)? = nil

    lazy var titleLabel = {
        let titleLabel = NSTextField(labelWithString: "")
        titleLabel.textColor = .white.withAlphaComponent(0.8)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 28)
        titleLabel.alignment = .center
        titleLabel.frame = CGRect(x: 0, y: self.bounds.midY - 50, width: self.bounds.width, height: 50)
        return titleLabel
    }()
    
    lazy var tipLabel = {
        let tipLabel = NSTextField(labelWithString: NSLocalizedString("TBMask.skip.label", comment: "Skip label"))
        tipLabel.textColor = .white.withAlphaComponent(0.8)
        tipLabel.font = NSFont.systemFont(ofSize: 18)
        tipLabel.alignment = .center
        tipLabel.frame = CGRect(x: 0, y: self.bounds.midY, width: self.bounds.width, height: 50)
        return tipLabel
    }()
    
    lazy var blurEffect = {
        let blurEffect = NSVisualEffectView(frame: self.bounds)
        blurEffect.alphaValue = 0.9
        blurEffect.appearance = NSAppearance(named: .vibrantDark)
        blurEffect.blendingMode = .behindWindow
        blurEffect.state = .inactive
        return blurEffect
    }()
    
    init(desc: String, frame: NSRect, dismissBlock: (() -> Void)? = nil) {
        self.dismissBlock = dismissBlock
        super.init(frame: frame)
        self.wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        titleLabel.stringValue = desc
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
//        debugPrint("++++ \(self) deinit")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        addSubview(blurEffect)
        addSubview(titleLabel)
        addSubview(tipLabel)
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            MaskHelper.shared.hideMaskWindow()
        }
    }
    
    // MARK: - Public
    
    public func show() {
        layer?.removeAllAnimations()
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = 1.0
        layer?.add(animation, forKey: "opacity")
    }
    
    public func hide() {
        layer?.removeAllAnimations()
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0
        animation.duration = 0.25
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        animation.delegate = self
        layer?.add(animation, forKey: "opacity")
    }
}

extension MaskView: CAAnimationDelegate {
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        dismissBlock?()
    }
}
