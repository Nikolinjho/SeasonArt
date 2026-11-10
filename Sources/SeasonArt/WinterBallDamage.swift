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
        // Смятый шар касается опоры физически: Box2D опускает тело на вмятину.
        return points
    }
}

struct WinterBallChip {
    let center: CGPoint
    let radius: CGFloat
    let strength: CGFloat
}

extension WinterObject {
    /// Шары фигуры для Box2D в координатах тела с началом в центре нижнего шара.
    /// Смятый шар — скруглённый многоугольник: над каждой из трёх глубоких вмятин плоская хорда по её краям,
    /// остальное — дуга. Шар ложится на края вмятины, как и нарисованный силуэт.
    var physicalParts: [SnowballPart] {
        let frames = ballFrames
        guard let base = frames.first else { return [] }
        return frames.enumerated().map { index, frame in
            let radius = frame.width / 2
            var part = SnowballPart(center: CGPoint(x: frame.midX - base.midX, y: frame.midY - base.midY), radius: radius)
            let damage = damage(for: index)
            guard damage.depth > 0 else { return part }
            let contour = damage.contour(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), rotation: 0)
            let rounding = radius * 0.75
            let inner = radius - rounding
            var angles: [CGFloat] = []
            var spans: [(angle: CGFloat, width: CGFloat)] = []
            for dent in damage.dents.sorted(by: { $0.depth > $1.depth }).prefix(3) {
                // Опорная функция контура вдоль вмятины даёт расстояние до хорды по её краям.
                let support = contour.map { $0.x * cos(dent.angle) + $0.y * sin(dent.angle) }.max() ?? radius
                let width = acos(min(1, max(-1, (support - rounding) / inner)))
                spans.append((dent.angle, width))
                angles += [dent.angle - width, dent.angle + width]
            }
            func covered(_ angle: CGFloat) -> Bool {
                spans.contains { abs(atan2(sin(angle - $0.angle), cos(angle - $0.angle))) < $0.width + 0.05 }
            }
            let free = (0..<64).map { CGFloat($0) * .pi / 32 }.filter { !covered($0) }
            let count = 8 - angles.count
            if !free.isEmpty {
                for k in 0..<count { angles.append(free[k * free.count / count]) }
            }
            part.rounding = rounding
            part.hull = angles.map { CGPoint(x: cos($0) * inner, y: sin($0) * inner) }
            return part
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
