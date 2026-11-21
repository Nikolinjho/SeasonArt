import AppKit

struct WinterSleighPass {
    static let size = CGSize(width: 416, height: 110)
    let screen: CGRect
    private(set) var elapsed: TimeInterval = 0

    var duration: TimeInterval { Double(screen.width + Self.size.width * 2) / 205 }
    var finished: Bool { elapsed >= duration }

    var frame: CGRect {
        let x = screen.minX - Self.size.width + CGFloat(elapsed) * 205
        let waveform = sin(CGFloat(elapsed) * 1.8)
        let y = screen.minY + screen.height * 0.55 + min(55, screen.height * 0.08) * waveform
        return CGRect(origin: CGPoint(x: x, y: y), size: Self.size)
    }

    mutating func advance(_ dt: TimeInterval) {
        guard dt.isFinite, dt > 0 else { return }
        elapsed += dt
    }
}

final class WinterSleighShow {
    private(set) var pass: WinterSleighPass
    let window: WinterToyWindow

    init(screen: CGRect) {
        let pass = WinterSleighPass(screen: screen)
        self.pass = pass
        window = WinterToyWindow(frame: pass.frame, interactive: false) { _ in }
        window.title = "SeasonArt · сани Деда Мороза"
        redraw()
    }

    func advance(_ dt: TimeInterval) -> Bool {
        pass.advance(dt)
        guard !pass.finished else {
            window.close()
            return false
        }
        window.setFrameOrigin(pass.frame.origin)
        redraw()
        return true
    }

    private func redraw() {
        let elapsed = pass.elapsed
        window.updateArtwork { _ in WinterSleighArtwork.draw(at: elapsed) }
    }
}

enum WinterSleighArtwork {
    static func draw(at time: TimeInterval) {
        let phase = CGFloat(time) * 2 * .pi * 2.65
        let sleigh = CGRect(x: 2, y: 6, width: 129, height: 93)
        let deer = [
            CGRect(x: 135, y: 41 + sin(phase) * 2.6, width: 84, height: 59),
            CGRect(x: 229, y: 44 + sin(phase + 1.75) * 2.6, width: 84, height: 59),
            CGRect(x: 323, y: 46 + sin(phase + 3.5) * 2.6, width: 84, height: 59)
        ]
        let reins = NSBezierPath()
        var hitch = CGPoint(x: 102, y: 54)
        for body in deer {
            let collar = CGPoint(x: body.minX + body.width * 0.70, y: body.minY + 17)
            let gap = collar.x - hitch.x
            reins.move(to: hitch)
            reins.curve(to: collar,
                        controlPoint1: CGPoint(x: hitch.x + gap * 0.36, y: hitch.y - 6),
                        controlPoint2: CGPoint(x: collar.x - gap * 0.24, y: collar.y - 7))
            hitch = CGPoint(x: body.maxX - 16, y: collar.y)
        }
        reins.lineWidth = 1.25
        NSColor(calibratedRed: 0.56, green: 0.33, blue: 0.17, alpha: 1).setStroke()
        reins.stroke()
        WinterArtwork.sleigh?.draw(in: sleigh, from: .zero, operation: .sourceOver, fraction: 1)
        for (index, rect) in deer.enumerated() {
            drawLegs(in: rect, phase: phase + CGFloat(index) * 1.75)
            WinterArtwork.reindeer?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    private static func drawLegs(in body: CGRect, phase: CGFloat) {
        for index in 0..<4 {
            let front = index % 2 == 1
            let near = index >= 2
            let angle = phase + (front ? 0.9 : 0) + (near ? 2.9 : 0)
            let root = CGPoint(x: body.minX + body.width * (front ? 0.67 : 0.29) + (near ? 1.5 : -2),
                               y: body.minY + 8.5)
            let swing = sin(angle)
            let tuck = max(0, cos(angle))
            let knee = CGPoint(x: root.x + swing * 7.2 + (front ? 2 : -2),
                               y: root.y - 9.5 + tuck * 3)
            let hoof = CGPoint(x: knee.x + swing * 8.6 - (front ? 6 : 2) * tuck,
                               y: knee.y - 10.5 + tuck * 6)
            let leg = NSBezierPath()
            leg.move(to: root)
            leg.curve(to: hoof, controlPoint1: knee, controlPoint2: CGPoint(x: knee.x, y: knee.y - 5))
            leg.lineCapStyle = .round
            leg.lineWidth = near ? 4.0 : 3.2
            let fur = near ? NSColor(red: 0.58, green: 0.32, blue: 0.19, alpha: 1)
                : NSColor(red: 0.40, green: 0.22, blue: 0.14, alpha: 1)
            fur.setStroke()
            leg.stroke()
            NSColor(calibratedRed: 0.20, green: 0.13, blue: 0.11, alpha: 1).setFill()
            NSBezierPath(roundedRect: CGRect(x: hoof.x - 2.2, y: hoof.y - 1.5, width: 5.5, height: 3.5),
                         xRadius: 1.3, yRadius: 1.3).fill()
        }
    }
}
