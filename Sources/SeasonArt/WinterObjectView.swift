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
        let changed = self.object.radii != object.radii || self.object.rotation != object.rotation
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

    override func mouseUp(with event: NSEvent) {
        guard let previous = lastDragTimestamp else { return }
        lastDragTimestamp = nil
        (window as? WinterObjectWindow)?.dragEnded?(max(0, event.timestamp - previous))
    }

    func cancelDrag() {
        guard lastDragTimestamp != nil else { return }
        lastDragTimestamp = nil
        (window as? WinterObjectWindow)?.dragCancelled?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let gradient = NSGradient(starting: .white, ending: NSColor(calibratedRed: 0.65, green: 0.79, blue: 0.87, alpha: 1))!
        let frames = object.ballFrames
        for rect in frames {
            let ball = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            gradient.draw(in: ball, angle: -50)
            NSColor(calibratedWhite: 0.55, alpha: 0.4).setStroke()
            ball.lineWidth = 0.8
            ball.stroke()
        }
        if object.radii.count == 1, let rect = frames.first {
            // Свет остаётся неподвижным, вращаются только маленькие снежные пятнышки.
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).addClip()
            let radius = object.radii[0]
            NSColor(calibratedRed: 0.50, green: 0.66, blue: 0.74, alpha: 0.22).setFill()
            for (x, y, size): (CGFloat, CGFloat, CGFloat) in [(-0.35, 0.2, 0.10), (0.28, -0.32, 0.13), (0.4, 0.35, 0.07)] {
                let px = (x * cos(object.rotation) - y * sin(object.rotation)) * radius + rect.midX
                let py = (x * sin(object.rotation) + y * cos(object.rotation)) * radius + rect.midY
                NSBezierPath(ovalIn: CGRect(x: px, y: py, width: radius * size, height: radius * size)).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        guard let decoration = object.decoration else { return }
        NSColor(calibratedWhite: 0.14, alpha: 1).setFill()
        for rect in decoration.eyes + decoration.buttons {
            NSBezierPath(ovalIn: rect).fill()
        }
        NSColor.systemOrange.setFill()
        let carrot = NSBezierPath()
        for (index, point) in decoration.nose.enumerated() {
            if index == 0 { carrot.move(to: point) } else { carrot.line(to: point) }
        }
        carrot.close()
        carrot.fill()
        NSColor(calibratedRed: 0.76, green: 0.08, blue: 0.13, alpha: 1).setFill()
        for rect in decoration.scarf {
            NSBezierPath(roundedRect: rect, xRadius: rect.height * 0.1, yRadius: rect.height * 0.1).fill()
        }
    }
}
