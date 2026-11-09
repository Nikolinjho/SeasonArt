import AppKit

/// Вмятины хранятся в координатах шара и поворачиваются вместе с ним.
struct WinterBallDamage: Equatable {
    struct Dent: Equatable {
        var angle: CGFloat
        var depth: CGFloat
    }

    private(set) var dents: [Dent] = []
    var depth: CGFloat { dents.map(\.depth).max() ?? 0 }

    func rotated(by angle: CGFloat) -> Self {
        var result = self
        result.dents = dents.map { Dent(angle: $0.angle + angle, depth: $0.depth) }
        return result
    }

    /// Небольшой удар не портит шар. Повторные удары не могут полностью его разрушить.
    @discardableResult
    mutating func hit(speed: CGFloat, angle: CGFloat) -> CGFloat {
        guard speed.isFinite, angle.isFinite, speed > 180 else { return 0 }
        let amount = min(0.24, (speed - 180) / 2_800)
        let direction = atan2(sin(angle), cos(angle))
        if let index = dents.firstIndex(where: { abs(atan2(sin($0.angle - direction), cos($0.angle - direction))) < 0.45 }) {
            let previous = dents[index].depth
            dents[index].depth = min(0.32, previous + amount * 0.5)
            return dents[index].depth - previous
        }
        guard dents.count < 6 else { return 0 }
        dents.append(Dent(angle: direction, depth: amount))
        return amount
    }

    func contour(in rect: CGRect, rotation: CGFloat) -> [CGPoint] {
        let radius = rect.width / 2
        var points: [CGPoint] = []
        for i in 0..<128 {
            let angle = CGFloat(i) * 2 * .pi / 128
            var distance = radius
            for dent in dents {
                let delta = atan2(sin(angle - rotation - dent.angle), cos(angle - rotation - dent.angle))
                let width: CGFloat = 0.9
                guard abs(delta) < width else { continue }
                let weight = pow(cos(delta / width * .pi / 2), 2)
                // Сколы имеют неровный край, но без случайного мерцания между кадрами.
                let grain = 1 + 0.14 * sin(delta * 23) + 0.08 * cos(delta * 37)
                distance -= radius * dent.depth * weight * grain
            }
            distance = max(radius * 0.55, distance)
            points.append(CGPoint(x: rect.midX + cos(angle) * distance,
                                  y: rect.midY + sin(angle) * distance))
        }
        // После смятия шар продолжает касаться опоры, а не висит над ней.
        let lift = (points.map(\.y).min() ?? rect.minY) - rect.minY
        return points.map { CGPoint(x: $0.x, y: $0.y - lift) }
    }
}

struct WinterBallChip {
    let center: CGPoint
    let radius: CGFloat
    let strength: CGFloat
}

extension WinterObject {
    /// Контакты учитывают высоту смятого силуэта. Целые шары сохраняют прежнюю геометрию.
    var collisionBallFrames: [CGRect] {
        ballFrames.enumerated().map { index, frame in
            guard damage(for: index).depth > 0 else { return frame }
            let points = outline(for: index)
            let left = points.map(\.x).min() ?? frame.minX
            let bottom = points.map(\.y).min() ?? frame.minY
            return CGRect(x: left, y: bottom, width: (points.map(\.x).max() ?? frame.maxX) - left,
                          height: (points.map(\.y).max() ?? frame.maxY) - bottom)
        }
    }

    var assembledDamage: [WinterBallDamage] {
        radii.indices.map { damage(for: $0).rotated(by: radii.count == 1 ? rotation : 0) }
    }

    func damage(for index: Int) -> WinterBallDamage {
        ballDamage.indices.contains(index) ? ballDamage[index] : WinterBallDamage()
    }

    func outline(for index: Int) -> [CGPoint] {
        damage(for: index).contour(in: ballFrames[index], rotation: radii.count == 1 ? rotation : 0)
    }

    func ballPath(for index: Int) -> NSBezierPath {
        let rect = ballFrames[index]
        guard damage(for: index).depth > 0 else { return NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)) }
        let path = NSBezierPath()
        for (i, point) in outline(for: index).enumerated() {
            if i == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        path.close()
        return path
    }
}
