import AppKit

/// Одноразовая панель: захват ввода существует только до завершения лепки.
final class SnowSculptingWindow: NSPanel {
    var began: ((CGPoint) -> Void)?
    var moved: ((CGPoint) -> Void)?
    var ended: ((CGPoint) -> Void)?
    var cancelled: (() -> Void)?
    var showsInScreenshots = false {
        didSet { sharingType = showsInScreenshots ? .readOnly : .none }
    }
    private var finished = false
    private var waitingTimer: Timer?
    private var previousApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?
    private var userSwitchedApplication = false

    init(screenFrame: CGRect) {
        super.init(contentRect: screenFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "SeasonArt · лепка снежка"
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        sharingType = .none
        contentView = SnowSculptingView(frame: CGRect(origin: .zero, size: screenFrame.size))
        contentView?.autoresizingMask = [.width, .height]
        setFrame(screenFrame, display: false)
    }

    func present() {
        guard !finished else { return }
        previousApplication = NSWorkspace.shared.frontmostApplication
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, !finished,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  app.processIdentifier != previousApplication?.processIdentifier else { return }
            userSwitchedApplication = true
            cancelOperation(nil)
        }
        orderFrontRegardless()
        makeKey()
        makeFirstResponder(contentView)
        let timer = Timer(timeInterval: 15, repeats: false) { [weak self] _ in self?.cancelOperation(nil) }
        RunLoop.main.add(timer, forMode: .common)
        waitingTimer = timer
    }

    func display(_ gesture: SnowSculptingGesture?) {
        (contentView as? SnowSculptingView)?.gesture = gesture
        contentView?.needsDisplay = true
    }

    fileprivate func begin(at point: CGPoint) {
        guard !finished else { return }
        waitingTimer?.invalidate()
        waitingTimer = nil
        began?(point)
    }

    fileprivate func move(to point: CGPoint) { if !finished { moved?(point) } }
    fileprivate func end(at point: CGPoint) { if !finished { ended?(point) } }

    override func cancelOperation(_ sender: Any?) {
        guard !finished else { return }
        let callback = cancelled
        close()
        callback?()
    }

    override func close() {
        guard !finished else { return }
        let restoreFocus = isKeyWindow && !userSwitchedApplication
        finished = true
        waitingTimer?.invalidate()
        waitingTimer = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        began = nil
        moved = nil
        ended = nil
        cancelled = nil
        super.close()
        if restoreFocus, let previousApplication,
           previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication.activate(options: [])
        }
        previousApplication = nil
    }

    override func resignKey() {
        super.resignKey()
        guard !finished else { return }
        userSwitchedApplication = true
        cancelOperation(nil)
    }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        FixedSpace.hold(self)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private final class SnowSculptingView: NSView {
    var gesture: SnowSculptingGesture?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var panel: SnowSculptingWindow? { window as? SnowSculptingWindow }
    private func global(_ event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
    }
    override func mouseDown(with event: NSEvent) { panel?.begin(at: global(event)) }
    override func mouseDragged(with event: NSEvent) { panel?.move(to: global(event)) }
    override func mouseUp(with event: NSEvent) { panel?.end(at: global(event)) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { panel?.cancelOperation(nil) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 { panel?.cancelOperation(nil); return true }
        return super.performKeyEquivalent(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        // WindowServer пропускает мышь через полностью прозрачные пиксели.
        NSColor(calibratedWhite: 0, alpha: 0.02).setFill()
        bounds.fill()
        let text = "Проведи мышью по сугробу. Отпусти, чтобы создать шар. Esc – отмена"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .medium),
                                                       .foregroundColor: NSColor.white]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let width = min(bounds.width - 32, textSize.width + 32)
        let hint = CGRect(x: (bounds.width - width) / 2, y: bounds.height - 100, width: width, height: 56)
        NSColor(calibratedWhite: 0.12, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: hint, xRadius: 12, yRadius: 12).fill()
        (text as NSString).draw(in: hint.insetBy(dx: 16, dy: 10), withAttributes: attributes)
        guard let gesture else { return }
        let radius = gesture.size?.radius ?? 8
        let ball = NSBezierPath(ovalIn: CGRect(x: gesture.center.x - radius, y: gesture.center.y - radius,
                                             width: radius * 2, height: radius * 2))
        NSGradient(starting: .white, ending: NSColor(calibratedRed: 0.68, green: 0.84, blue: 0.94, alpha: 0.9))?.draw(in: ball, angle: -60)
        NSColor.white.withAlphaComponent(0.8).setStroke()
        ball.lineWidth = 1
        ball.stroke()
    }
}
