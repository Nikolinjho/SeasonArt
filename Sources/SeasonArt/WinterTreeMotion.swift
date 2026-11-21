import Foundation

/// Вертикальное падение дерева и затухающий отскок на опоре.
struct WinterTreeMotion {
    private(set) var isFalling = false
    private var velocity: CGFloat = 0
    private var impact: CGFloat = 0
    private var springTime: CGFloat?
    private let gravity: CGFloat = 1_250

    var isMoving: Bool { isFalling || springTime != nil }

    var lift: CGFloat {
        guard let springTime, springTime < 0.22 else { return 0 }
        let progress = springTime / 0.22
        return min(7, impact / 85) * 4 * progress * (1 - progress)
    }

    var lean: CGFloat {
        guard let springTime else { return 0 }
        return min(0.11, impact / 4_600) * sin(springTime * 24) * exp(-springTime * 6.5)
    }

    mutating func drop() {
        self = WinterTreeMotion()
        isFalling = true
    }

    mutating func fall(from height: CGFloat, toward support: CGFloat, dt: TimeInterval) -> (height: CGFloat, impact: CGFloat?) {
        guard isFalling, dt.isFinite, dt > 0 else { return (height, nil) }
        let step = CGFloat(dt)
        let next = height + velocity * step - gravity * step * step / 2
        if next > support {
            velocity -= gravity * step
            return (next, nil)
        }
        // Скорость именно в точке контакта, независимо от частоты кадров.
        let speed = sqrt(velocity * velocity + 2 * gravity * max(0, height - support))
        isFalling = false
        velocity = 0
        impact = speed
        springTime = speed >= 80 ? 0 : nil
        return (support, speed)
    }

    mutating func advanceSpring(dt: TimeInterval) {
        guard let springTime, dt.isFinite, dt > 0 else { return }
        let elapsed = springTime + CGFloat(dt)
        self.springTime = elapsed < 0.66 ? elapsed : nil
    }
}
