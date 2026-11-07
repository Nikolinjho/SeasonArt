import AppKit

final class WinterObjectView: NSView {
    private(set) var object: WinterObject
    private var shadows: [WinterContactShadow]
    private var lastDragTimestamp: TimeInterval?

    init(object: WinterObject) {
        self.object = object
        shadows = WinterContactShadow.shadows(on: object, among: [])
        super.init(frame: CGRect(origin: .zero, size: object.presentationFrame.size))
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { nil }

    func display(object: WinterObject, shadows suppliedShadows: [WinterContactShadow]? = nil) {
        let shadows = suppliedShadows ?? WinterContactShadow.shadows(on: object, among: [])
        let changed = self.object.radii != object.radii || self.object.rotation != object.rotation || self.shadows != shadows
        self.object = object
        self.shadows = shadows
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
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let origin = NSAffineTransform()
        origin.translateX(by: -object.drawingBounds.minX, yBy: -object.drawingBounds.minY)
        origin.concat()
        for points in object.arms {
            let twig = NSBezierPath()
            for (index, point) in points.enumerated() {
                if index == 0 { twig.move(to: point) } else { twig.line(to: point) }
            }
            twig.lineCapStyle = .round
            twig.lineJoinStyle = .round
            NSColor(calibratedRed: 0.24, green: 0.14, blue: 0.08, alpha: 1).setStroke()
            twig.lineWidth = object.armLineWidth
            twig.stroke()
            NSColor(calibratedRed: 0.49, green: 0.32, blue: 0.18, alpha: 1).setStroke()
            twig.lineWidth = object.armLineWidth * 0.45
            twig.stroke()
        }
        let gradient = NSGradient(starting: .white, ending: NSColor(calibratedRed: 0.65, green: 0.79, blue: 0.87, alpha: 1))!
        let frames = object.ballFrames
        for (index, rect) in frames.enumerated() {
            let ball = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            gradient.draw(in: ball, angle: -50)
            NSColor(calibratedWhite: 0.55, alpha: 0.4).setStroke()
            ball.lineWidth = 0.8
            ball.stroke()
            for shadow in shadows where shadow.ballIndex == index {
                NSGraphicsContext.saveGraphicsState()
                ball.addClip()
                NSGraphicsContext.current?.cgContext.setBlendMode(.sourceAtop)
                let transform = NSAffineTransform()
                transform.translateX(by: shadow.center.x, yBy: shadow.center.y)
                transform.rotate(byRadians: shadow.angle)
                transform.scaleX(by: shadow.halfWidth, yBy: shadow.depth)
                transform.concat()
                let color = NSColor(calibratedRed: 0.20, green: 0.32, blue: 0.42, alpha: shadow.opacity)
                let fade = NSGradient(colors: [color, color.withAlphaComponent(shadow.opacity * 0.45), color.withAlphaComponent(0)],
                                      atLocations: [0, 0.45, 1], colorSpace: .genericRGB)!
                fade.draw(fromCenter: .zero, radius: 0, toCenter: .zero, radius: 1, options: [])
                NSGraphicsContext.restoreGraphicsState()
            }
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
