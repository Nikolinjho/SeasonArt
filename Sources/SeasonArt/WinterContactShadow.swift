import CoreGraphics
import Foundation

/// Мягкое затемнение на принимающем шаре, в локальных координатах его окна.
struct WinterContactShadow: Equatable {
    let ballIndex: Int
    let center: CGPoint
    let halfWidth: CGFloat
    let depth: CGFloat
    let angle: CGFloat
    let opacity: CGFloat

    static func shadows(on object: WinterObject, among objects: [WinterObject]) -> [Self] {
        guard !object.parked else { return [] }
        let frames = object.ballFrames
        var result: [Self] = []
        for index in frames.indices {
            if index + 1 < frames.count,
               let shadow = contact(receiver: frames[index], caster: frames[index + 1], index: index) {
                result.append(shadow)
            }
        }
        guard !object.isDragged else { return result }
        for other in objects where other.id != object.id && !other.parked && !other.isDragged {
            guard object.frame.insetBy(dx: -4, dy: -4).intersects(other.frame) else { continue }
            let offset = CGPoint(x: other.frame.minX - object.frame.minX,
                                 y: other.frame.minY - object.frame.minY)
            for caster in other.ballFrames {
                let localCaster = caster.offsetBy(dx: offset.x, dy: offset.y)
                for index in frames.indices {
                    if let shadow = contact(receiver: frames[index], caster: localCaster, index: index) {
                        result.append(shadow)
                    }
                }
            }
        }
        return result
    }

    private static func contact(receiver: CGRect, caster: CGRect, index: Int) -> Self? {
        let dx = caster.midX - receiver.midX
        let dy = caster.midY - receiver.midY
        let distance = hypot(dx, dy)
        let radius = receiver.width / 2
        let upperRadius = caster.width / 2
        let size = min(radius, upperRadius)
        let gap = distance - radius - upperRadius
        // Боковой контакт не является опорой. Небольшой зазор плавно ослабляет тень при отрыве.
        guard distance > 0, dy / distance > 0.65, gap < min(4, size * 0.3),
              gap >= -size * (WinterBallGeometry.jointOverlap + 0.05) else { return nil }
        let reach = min(radius, distance - upperRadius) - size * 0.06
        return Self(ballIndex: index,
                    center: CGPoint(x: receiver.midX + dx / distance * reach,
                                    y: receiver.midY + dy / distance * reach),
                    halfWidth: size * 0.95, depth: size * 0.48,
                    angle: atan2(dy, dx) - .pi / 2,
                    opacity: 0.36 * (1 - max(0, gap) / min(4, size * 0.3)))
    }
}
