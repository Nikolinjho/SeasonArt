import AppKit

final class WinterPlowWindow: NSPanel {
    var showsInScreenshots = false {
        didSet { sharingType = showsInScreenshots ? .readOnly : .none }
    }

    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        sharingType = .none
        contentView = WinterPlowView(frame: CGRect(origin: .zero, size: frame.size))
        contentView?.autoresizingMask = [.width, .height]
        setFrame(frame, display: false)
    }

    func display(frame: CGRect) { setFrame(frame, display: false) }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        FixedSpace.hold(self)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private final class WinterPlowView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = AffineTransform(scaleByX: bounds.width / 108, byY: bounds.height / 58)
        (transform as NSAffineTransform).concat()
        NSColor(calibratedRed: 0.96, green: 0.66, blue: 0.12, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: 27, y: 15, width: 75, height: 19), xRadius: 4, yRadius: 4).fill()
        NSBezierPath(roundedRect: CGRect(x: 31, y: 29, width: 30, height: 27), xRadius: 3, yRadius: 3).fill()
        NSColor(calibratedRed: 0.26, green: 0.58, blue: 0.76, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: 35, y: 34, width: 21, height: 17), xRadius: 2, yRadius: 2).fill()
        NSColor(calibratedWhite: 0.15, alpha: 1).setFill()
        for x in [CGFloat(29), 42, 55, 68, 81, 94] {
            NSBezierPath(ovalIn: CGRect(x: x - 6, y: 3, width: 12, height: 15)).fill()
        }
        NSColor(calibratedWhite: 0.72, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(x: 17, y: 13, width: 17, height: 5)).fill()
        let blade = NSBezierPath()
        blade.move(to: CGPoint(x: 1, y: 3))
        blade.line(to: CGPoint(x: 20, y: 6))
        blade.line(to: CGPoint(x: 24, y: 31))
        blade.line(to: CGPoint(x: 15, y: 32))
        blade.close()
        NSGradient(starting: .white, ending: NSColor(calibratedWhite: 0.65, alpha: 1))!.draw(in: blade, angle: 0)
    }
}
