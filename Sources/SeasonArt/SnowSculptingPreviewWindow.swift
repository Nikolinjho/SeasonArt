import AppKit

/// Маленькое окно черновика пропускает весь ввод в приложение под ним.
final class SnowSculptingPreviewWindow: NSPanel {
    var showsInScreenshots = false {
        didSet { sharingType = showsInScreenshots ? .readOnly : .none }
    }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "SeasonArt · снежок"
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        animationBehavior = .none
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        sharingType = .none
        contentView = SnowSculptingPreviewView()
    }

    func display(_ gesture: SnowSculptingGesture, screenFrame: CGRect) {
        let radius = gesture.size?.radius ?? 8
        let center = CGPoint(x: gesture.lastPoint.x + screenFrame.minX,
                             y: gesture.center.y + screenFrame.minY)
        setFrame(CGRect(x: center.x - radius - 2, y: center.y - radius - 2,
                        width: radius * 2 + 4, height: radius * 2 + 4), display: false)
        contentView?.needsDisplay = true
    }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        FixedSpace.hold(self)
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private final class SnowSculptingPreviewView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let ball = NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2))
        NSGradient(starting: .white, ending: NSColor(calibratedRed: 0.68, green: 0.84, blue: 0.94, alpha: 0.9))?.draw(in: ball, angle: -60)
        NSColor.white.withAlphaComponent(0.8).setStroke()
        ball.lineWidth = 1
        ball.stroke()
    }
}
