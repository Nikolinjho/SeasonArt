import CoreGraphics

enum WinterSnowmanGaze {
    static func target(from head: CGPoint, toward pointer: CGPoint, headWidth: CGFloat) -> CGPoint {
        let offset = CGVector(dx: pointer.x - head.x, dy: pointer.y - head.y)
        let distance = hypot(offset.dx, offset.dy)
        let reach = max(77, headWidth * 3.2)
        guard distance > 0, distance < reach else { return .zero }
        let strength = min(1, distance / (headWidth * 0.55), (reach - distance) / 25)
        return CGPoint(x: offset.dx / distance * strength, y: offset.dy / distance * strength)
    }
}
