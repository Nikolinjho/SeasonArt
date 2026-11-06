import AppKit

final class WinterObjectView: NSView {
    private(set) var object: WinterObject
    private var lastDragTimestamp: TimeInterval?

    init(object: WinterObject) {
        self.object = object
        super.init(frame: CGRect(origin: .zero, size: object.frame.size))
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { nil }

    func display(object: WinterObject) {
        let changed = self.object.sizes != object.sizes
        self.object = object
        if changed { needsDisplay = true }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let panel = window as? WinterObjectWindow else { return }
        lastDragTimestamp = event.timestamp
        panel.dragBegan?(panel.convertPoint(toScreen: event.locationInWindow))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let panel = window as? WinterObjectWindow, let previous = lastDragTimestamp else { return }
        lastDragTimestamp = event.timestamp
        panel.dragged?(panel.convertPoint(toScreen: event.locationInWindow), max(1.0 / 240, event.timestamp - previous))
    }

    override func mouseUp(with event: NSEvent) { endDrag() }

    func endDrag() {
        guard lastDragTimestamp != nil else { return }
        lastDragTimestamp = nil
        (window as? WinterObjectWindow)?.dragEnded?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let gradient = NSGradient(starting: .white, ending: NSColor(calibratedRed: 0.65, green: 0.79, blue: 0.87, alpha: 1))!
        var bottom: CGFloat = 0
        for size in object.sizes {
            let radius = size.radius
            let rect = CGRect(x: bounds.midX - radius, y: bottom, width: radius * 2, height: radius * 2).insetBy(dx: 0.5, dy: 0.5)
            let ball = NSBezierPath(ovalIn: rect)
            gradient.draw(in: ball, angle: -50)
            NSColor(calibratedWhite: 0.55, alpha: 0.4).setStroke()
            ball.lineWidth = 0.8
            ball.stroke()
            bottom += radius * 2
        }
        guard object.isSnowman else { return }
        let x = bounds.midX
        NSColor(calibratedWhite: 0.14, alpha: 1).setFill()
        for point in [CGPoint(x: x - 5, y: 115), CGPoint(x: x + 5, y: 115),
                      CGPoint(x: x, y: 87), CGPoint(x: x, y: 74), CGPoint(x: x, y: 39)] {
            NSBezierPath(ovalIn: CGRect(x: point.x - 1.8, y: point.y - 1.8, width: 3.6, height: 3.6)).fill()
        }
        NSColor.systemOrange.setFill()
        let carrot = NSBezierPath()
        carrot.move(to: CGPoint(x: x - 1, y: 111))
        carrot.line(to: CGPoint(x: x + 12, y: 108))
        carrot.line(to: CGPoint(x: x - 1, y: 106))
        carrot.close()
        carrot.fill()
        NSColor(calibratedRed: 0.76, green: 0.08, blue: 0.13, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: x - 14, y: 96, width: 28, height: 6), xRadius: 2, yRadius: 2).fill()
        NSBezierPath(roundedRect: CGRect(x: x + 6, y: 80, width: 6, height: 20), xRadius: 1, yRadius: 1).fill()
    }
}
