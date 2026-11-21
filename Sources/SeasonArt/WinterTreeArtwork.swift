import AppKit

enum WinterTreeArtwork {
    static func draw(in rect: CGRect, decorations: WinterTreeDecorations) {
        guard let evergreen = WinterArtwork.tree else { return }
        let tree = rect.insetBy(dx: rect.width * 0.025, dy: 0)
        evergreen.draw(in: CGRect(x: tree.minX, y: tree.minY, width: tree.width, height: tree.height * 0.9),
                       from: .zero, operation: .sourceOver, fraction: 1)

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: tree.minX + x * tree.width, y: tree.minY + y * tree.height)
        }
        let bands: [(CGFloat, CGFloat, CGFloat)] = [(0.33, 0.68, 0.63), (0.24, 0.76, 0.46), (0.14, 0.86, 0.26)]
        for (row, band) in bands.enumerated() {
            let (left, right, y) = band
            if decorations.ornaments.contains(.garland) {
                let path = NSBezierPath()
                path.move(to: point(left, y + 0.035))
                path.curve(to: point(right, y + 0.025),
                           controlPoint1: point(left + (right - left) * 0.25, y - 0.055),
                           controlPoint2: point(right - (right - left) * 0.25, y - 0.055))
                path.lineWidth = tree.height * 0.018
                path.lineCapStyle = .round
                NSColor(calibratedRed: 0.59, green: 0.36, blue: 0.12, alpha: 1).setStroke()
                path.stroke()
                path.lineWidth *= 0.53
                NSColor(calibratedRed: 1, green: 0.79, blue: 0.39, alpha: 1).setStroke()
                path.stroke()
            }
            if decorations.ornaments.contains(.lights) {
                for index in 0..<(4 + row * 2) {
                    let t = (CGFloat(index) + 0.5) / CGFloat(4 + row * 2)
                    WinterLights.bulb(at: point(left + (right - left) * t, y + 0.04 - sin(t * .pi) * 0.028),
                                       radius: tree.height * 0.0115, colorIndex: index + row)
                }
            }
        }
        let ornaments = WinterTreeOrnament.allCases.filter {
            $0 != .lights && $0 != .garland && decorations.ornaments.contains($0)
        }
        if !ornaments.isEmpty {
            let sites: [(CGFloat, CGFloat)] = [
                (0.50, 0.73), (0.34, 0.54), (0.67, 0.52), (0.23, 0.33), (0.51, 0.35),
                (0.77, 0.33), (0.34, 0.20), (0.59, 0.19), (0.46, 0.58), (0.72, 0.21),
                (0.42, 0.43), (0.59, 0.42), (0.58, 0.64), (0.41, 0.66)
            ]
            let count = min(sites.count, max(6, ornaments.count * 2))
            for (index, site) in sites.prefix(count).enumerated() {
                let center = point(site.0, site.1)
                let size = tree.height * 0.091
                switch ornaments[index % ornaments.count] {
                case .baubles:
                    drawBauble(at: center, size: size, index: index)
                case .candy: drawCandy(at: center, size: size)
                case .bells: drawGlyph("🔔", at: center, size: size)
                case .gingerbread: drawCookie(at: center, size: size)
                case .bows: drawGlyph("🎀", at: center, size: size)
                case .stars: drawGlyph("⭐️", at: center, size: size)
                case .lights, .garland: break
                }
            }
        }
        let tip = point(0.50, 0.918)
        let size = tree.height * 0.14
        switch decorations.topper {
        case .star: drawGlyph("⭐️", at: tip, size: size)
        case .snowflake: drawGlyph("❄️", at: tip, size: size)
        case .bow: drawGlyph("🎀", at: tip, size: size)
        case .bell: drawGlyph("🔔", at: tip, size: size)
        case .heart: drawGlyph("❤️", at: tip, size: size)
        case .finial:
            NSColor(calibratedRed: 1, green: 0.78, blue: 0.37, alpha: 1).setFill()
            let spire = NSBezierPath()
            spire.move(to: CGPoint(x: tip.x, y: tip.y + size * 0.55))
            spire.line(to: CGPoint(x: tip.x - size * 0.14, y: tip.y))
            spire.line(to: CGPoint(x: tip.x + size * 0.14, y: tip.y))
            spire.close()
            spire.fill()
            drawBauble(at: CGPoint(x: tip.x, y: tip.y - size * 0.19), size: size * 0.68, index: 0)
        }
    }

    private static func drawGlyph(_ glyph: String, at point: CGPoint, size: CGFloat) {
        let text = NSAttributedString(string: glyph, attributes: [.font: NSFont.systemFont(ofSize: size)])
        let measured = text.size()
        text.draw(at: CGPoint(x: point.x - measured.width / 2, y: point.y - measured.height / 2))
    }

    private static func drawBauble(at point: CGPoint, size: CGFloat, index: Int) {
        let ball = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        NSColor(calibratedRed: 0.95, green: 0.74, blue: 0.38, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: point.x - size * 0.13, y: ball.maxY - size * 0.1,
                                         width: size * 0.26, height: size * 0.23),
                     xRadius: size * 0.04, yRadius: size * 0.04).fill()
        let colors: [(NSColor, NSColor)] = [
            (NSColor(red: 1, green: 0.42, blue: 0.43, alpha: 1), NSColor(red: 0.60, green: 0.08, blue: 0.18, alpha: 1)),
            (NSColor(red: 0.74, green: 0.90, blue: 1, alpha: 1), NSColor(red: 0.28, green: 0.48, blue: 0.78, alpha: 1)),
            (NSColor(red: 1, green: 0.89, blue: 0.58, alpha: 1), NSColor(red: 0.75, green: 0.41, blue: 0.14, alpha: 1))
        ]
        let colorsForBall = colors[index % colors.count]
        NSGradient(starting: colorsForBall.0, ending: colorsForBall.1)?.draw(in: NSBezierPath(ovalIn: ball), angle: -62)
        NSColor.white.withAlphaComponent(0.77).setFill()
        NSBezierPath(ovalIn: CGRect(x: ball.minX + size * 0.24, y: ball.midY + size * 0.14,
                                   width: size * 0.18, height: size * 0.13)).fill()
    }

    private static func drawCandy(at center: CGPoint, size: CGFloat) {
        let candy = NSBezierPath()
        let top = CGPoint(x: center.x, y: center.y + size * 0.21)
        candy.move(to: CGPoint(x: center.x + size * 0.20, y: center.y - size * 0.38))
        candy.line(to: CGPoint(x: top.x + size * 0.20, y: top.y))
        candy.curve(to: CGPoint(x: top.x - size * 0.25, y: top.y - size * 0.025),
                    controlPoint1: CGPoint(x: top.x + size * 0.12, y: top.y + size * 0.32),
                    controlPoint2: CGPoint(x: top.x - size * 0.29, y: top.y + size * 0.27))
        candy.lineWidth = size * 0.22
        candy.lineCapStyle = .round
        NSColor(calibratedRed: 1, green: 0.95, blue: 0.85, alpha: 1).setStroke()
        candy.stroke()
        candy.lineCapStyle = .butt
        candy.setLineDash([size * 0.13, size * 0.14], count: 2, phase: 0)
        NSColor(calibratedRed: 0.80, green: 0.16, blue: 0.24, alpha: 1).setStroke()
        candy.stroke()
    }

    private static func drawCookie(at point: CGPoint, size: CGFloat) {
        func shape(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSBezierPath {
            let rect = CGRect(x: point.x + size * x, y: point.y + size * y, width: size * width, height: size * height)
            return NSBezierPath(roundedRect: rect, xRadius: size * 0.11, yRadius: size * 0.11)
        }
        NSColor(calibratedRed: 0.70, green: 0.36, blue: 0.18, alpha: 1).setFill()
        shape(-0.49, -0.14, 0.98, 0.23).fill()
        shape(-0.31, -0.50, 0.22, 0.54).fill()
        shape(0.09, -0.50, 0.22, 0.54).fill()
        shape(-0.24, -0.29, 0.48, 0.62).fill()
        NSBezierPath(ovalIn: CGRect(x: point.x - size * 0.24, y: point.y + size * 0.13,
                                   width: size * 0.48, height: size * 0.45)).fill()
        NSColor(calibratedRed: 1, green: 0.96, blue: 0.88, alpha: 1).setFill()
        for (x, y): (CGFloat, CGFloat) in [(-0.09, 0.34), (0.04, 0.34), (-0.032, -0.04), (-0.032, -0.18)] {
            shape(x, y, 0.066, 0.066).fill()
        }
    }
}

enum WinterLights {
    private static let colors = [
        NSColor(red: 1, green: 0.55, blue: 0.40, alpha: 1),
        NSColor(red: 1, green: 0.82, blue: 0.37, alpha: 1),
        NSColor(red: 0.56, green: 0.86, blue: 1, alpha: 1),
        NSColor(red: 0.69, green: 0.94, blue: 0.69, alpha: 1)
    ]

    static func bulb(at point: CGPoint, radius: CGFloat, colorIndex: Int) {
        let color = colors[colorIndex % colors.count]
        let glow = NSGradient(starting: color.withAlphaComponent(0.64), ending: color.withAlphaComponent(0))
        glow?.draw(fromCenter: point, radius: 0, toCenter: point, radius: radius * 3.1, options: [])
        let bulb = CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius)
        NSGradient(starting: color.blended(withFraction: 0.65, of: .white) ?? .white, ending: color)?
            .draw(in: NSBezierPath(ovalIn: bulb), angle: -60)
    }
}
