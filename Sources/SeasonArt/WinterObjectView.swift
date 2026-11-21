import AppKit

final class WinterObjectView: NSView {
    private(set) var object: WinterObject
    private var shadows: [WinterContactShadow]
    private var gaze: CGPoint = .zero
    private var lastDragTimestamp: TimeInterval?
    private var lastDragPoint: CGPoint?

    init(object: WinterObject) {
        self.object = object
        shadows = WinterContactShadow.shadows(on: object, among: [])
        super.init(frame: CGRect(origin: .zero, size: object.presentationFrame.size))
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { nil }

    func display(object: WinterObject, shadows suppliedShadows: [WinterContactShadow]? = nil) {
        let shadows = suppliedShadows ?? WinterContactShadow.shadows(on: object, among: [])
        let changed = self.object.id != object.id || self.object.radii != object.radii || self.object.rotation != object.rotation
            || self.object.ballDamage != object.ballDamage || self.shadows != shadows
        self.object = object
        self.shadows = shadows
        if changed { needsDisplay = true }
    }

    func lookToward(_ point: CGPoint, dt: TimeInterval) {
        guard let head = object.isSnowman ? object.ballFrames.last : nil,
              point.x.isFinite, point.y.isFinite, dt.isFinite, dt > 0 else { return }
        let target = WinterSnowmanGaze.target(from: CGPoint(x: object.frame.minX + head.midX,
                                                            y: object.frame.minY + head.midY),
                                               toward: point, headWidth: head.width)
        let alpha = 1 - exp(-min(dt, 0.1) * 18)
        let next = CGPoint(x: gaze.x + (target.x - gaze.x) * alpha, y: gaze.y + (target.y - gaze.y) * alpha)
        guard hypot(next.x - gaze.x, next.y - gaze.y) >= 0.003 else { return }
        gaze = next
        needsDisplay = true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let panel = window as? WinterObjectWindow else { return }
        lastDragTimestamp = event.timestamp
        let point = panel.convertPoint(toScreen: event.locationInWindow)
        lastDragPoint = point
        panel.dragBegan?(point)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let panel = window as? WinterObjectWindow, let previous = lastDragTimestamp else { return }
        lastDragTimestamp = event.timestamp
        let point = panel.convertPoint(toScreen: event.locationInWindow)
        lastDragPoint = point
        panel.dragged?(point, max(1.0 / 240, event.timestamp - previous))
    }

    override func mouseUp(with event: NSEvent) {
        guard let previous = lastDragTimestamp, let panel = window as? WinterObjectWindow else { return }
        let point = panel.convertPoint(toScreen: event.locationInWindow)
        let moved = point != lastDragPoint
        // AppKit может объединить последнее движение с отпусканием кнопки.
        if moved { panel.dragged?(point, max(1.0 / 240, event.timestamp - previous)) }
        lastDragTimestamp = nil
        lastDragPoint = nil
        panel.dragEnded?(moved ? 0 : max(0, event.timestamp - previous))
    }

    func cancelDrag() {
        guard lastDragTimestamp != nil else { return }
        lastDragTimestamp = nil
        lastDragPoint = nil
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
            guard let start = points.first, let tip = points.last else { continue }
            twig.move(to: start)
            if points.count == 3 {
                let bend = points[1]
                twig.curve(to: tip, controlPoint1: CGPoint(x: bend.x, y: start.y),
                           controlPoint2: CGPoint(x: bend.x, y: tip.y))
            } else {
                twig.curve(to: tip, controlPoint1: start,
                           controlPoint2: CGPoint(x: tip.x, y: (start.y + tip.y) / 2))
            }
            twig.lineCapStyle = .round
            twig.lineJoinStyle = .round
            NSColor(calibratedRed: 0.24, green: 0.14, blue: 0.08, alpha: 1).setStroke()
            let width = object.armLineWidth * (points.count == 3 ? 1.15 : 0.66)
            twig.lineWidth = width
            twig.stroke()
            NSColor(calibratedRed: 0.54, green: 0.36, blue: 0.23, alpha: 1).setStroke()
            twig.lineWidth = width * 0.45
            twig.stroke()
        }
        let frames = object.ballFrames
        for index in frames.indices {
            let ball = object.ballPath(for: index)
            WinterArtwork.drawSnow(in: ball, bounds: frames[index])
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
            object.ballPath(for: 0).addClip()
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
        let head = frames[2]
        let warmth = NSColor(calibratedRed: 0.90, green: 0.43, blue: 0.38, alpha: 0.30)
        let blush = NSGradient(starting: warmth, ending: warmth.withAlphaComponent(0))
        for offset: CGFloat in [-0.27, 0.29] {
            let center = CGPoint(x: head.midX + head.width * offset, y: head.midY - head.height * 0.13)
            blush?.draw(fromCenter: center, radius: 0, toCenter: center, radius: head.width * 0.16, options: [])
        }
        let coal = NSGradient(starting: NSColor(calibratedWhite: 0.34, alpha: 1),
                              ending: NSColor(calibratedRed: 0.16, green: 0.14, blue: 0.13, alpha: 1))
        for rect in decoration.mouth + decoration.buttons {
            coal?.draw(in: NSBezierPath(ovalIn: rect), angle: -55)
        }
        decoration.outfit.drawScarf(decoration.scarf)
        for eye in decoration.eyes {
            let socket = NSBezierPath(ovalIn: eye.insetBy(dx: -eye.width * 0.12, dy: -eye.height * 0.07))
            NSColor(calibratedRed: 0.16, green: 0.19, blue: 0.24, alpha: 0.15).setStroke()
            socket.lineWidth = eye.width * 0.12
            NSColor(calibratedWhite: 0.99, alpha: 1).setFill()
            socket.fill()
            socket.stroke()
            let pupil = eye.insetBy(dx: eye.width * 0.15, dy: eye.height * 0.15)
                .offsetBy(dx: gaze.x * eye.width * 0.30, dy: gaze.y * eye.height * 0.27)
            coal?.draw(in: NSBezierPath(ovalIn: pupil), angle: -55)
            NSColor(calibratedWhite: 1, alpha: 0.78).setFill()
            NSBezierPath(ovalIn: CGRect(x: pupil.minX + pupil.width * 0.22, y: pupil.midY,
                                        width: pupil.width * 0.26, height: pupil.height * 0.26)).fill()
        }
        let carrot = NSBezierPath()
        let top = decoration.nose[0]
        let tip = decoration.nose[1]
        let bottom = decoration.nose[2]
        let scale = head.width / 28
        carrot.move(to: top)
        carrot.curve(to: tip, controlPoint1: CGPoint(x: top.x + 5 * scale, y: top.y + 0.4 * scale),
                     controlPoint2: CGPoint(x: tip.x - 3 * scale, y: tip.y + 1.7 * scale))
        carrot.curve(to: bottom, controlPoint1: CGPoint(x: tip.x - 3 * scale, y: tip.y - 1.6 * scale),
                     controlPoint2: CGPoint(x: bottom.x + 4 * scale, y: bottom.y - 0.5 * scale))
        carrot.curve(to: top, controlPoint1: CGPoint(x: top.x - 2.2 * scale, y: bottom.y),
                     controlPoint2: CGPoint(x: top.x - 2.5 * scale, y: top.y))
        carrot.close()
        NSGradient(starting: NSColor(calibratedRed: 0.99, green: 0.68, blue: 0.25, alpha: 1),
                   ending: NSColor(calibratedRed: 0.81, green: 0.27, blue: 0.10, alpha: 1))?
            .draw(in: carrot, angle: -70)
        NSGraphicsContext.saveGraphicsState()
        carrot.addClip()
        NSColor(calibratedRed: 0.63, green: 0.29, blue: 0.15, alpha: 0.38).setStroke()
        for offset: CGFloat in [1.8, 4.0, 6.2] {
            let ridge = NSBezierPath()
            let x = top.x + offset * scale
            ridge.move(to: CGPoint(x: x, y: top.y - offset * 0.13 * scale))
            ridge.curve(to: CGPoint(x: x + 0.7 * scale, y: bottom.y + scale),
                        controlPoint1: CGPoint(x: x - 0.5 * scale, y: top.y - 2 * scale),
                        controlPoint2: CGPoint(x: x - 0.4 * scale, y: bottom.y + 2 * scale))
            ridge.lineWidth = 0.55 * scale
            ridge.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        decoration.outfit.drawHat(decoration.hat)
    }
}
