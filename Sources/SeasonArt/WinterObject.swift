import Foundation
import CoreGraphics

enum WinterBallSize: Int, CaseIterable {
    case small, medium, large

    var radius: CGFloat {
        switch self {
        case .small: return 14
        case .medium: return 21
        case .large: return 28
        }
    }
}

enum WinterBallGeometry {
    static let minimumRadius: CGFloat = 6
    static let maximumRadius: CGFloat = 36
    static let jointOverlap: CGFloat = 0.6

    static func isValid(_ radius: CGFloat) -> Bool {
        radius.isFinite && (minimumRadius...maximumRadius).contains(radius)
    }
}

struct WinterObject: Identifiable {
    let id: UUID
    /// Состав снизу вверх. center задаёт центр нижнего шара.
    var radii: [CGFloat]
    var center: CGPoint
    var velocity: CGVector
    var support: CGWindowID?
    var parked: Bool
    var isDragged: Bool

    var rotation: CGFloat = 0
    /// Угловая скорость одиночного шара, рад/с, положительная против часовой стрелки.
    var spin: CGFloat = 0
    var ballDamage: [WinterBallDamage] = []

    /// Локальные границы шаров: стык перекрывает 30% диаметра меньшего из соседей.
    var ballFrames: [CGRect] {
        let widest = radii.max() ?? 0
        var bottom: CGFloat = 0
        return radii.enumerated().map { index, radius in
            if index > 0 { bottom -= min(radii[index - 1], radius) * WinterBallGeometry.jointOverlap }
            let rect = CGRect(x: widest - radius, y: bottom,
                              width: radius * 2, height: radius * 2)
            bottom = rect.maxY
            return rect
        }
    }

    var frame: CGRect {
        let radius = radii.max() ?? 0
        return CGRect(x: center.x - radius, y: center.y - (radii.first ?? 0),
                      width: radius * 2, height: ballFrames.last?.maxY ?? 0)
    }

    var isSnowman: Bool { radii.count == 3 }

    /// Круги шаров в координатах сцены.
    var ballCircles: [(center: CGPoint, radius: CGFloat)] {
        let origin = frame.origin
        return ballFrames.map { (CGPoint(x: origin.x + $0.midX, y: origin.y + $0.midY), $0.width / 2) }
    }
}

/// Геометрия украшений использует радиус соответствующего шара.
struct WinterDecoration {
    let eyes: [CGRect]
    let mouth: [CGRect]
    let buttons: [CGRect]
    let nose: [CGPoint]
    let scarf: [CGRect]
}

extension WinterObject {
    var decoration: WinterDecoration? {
        guard isSnowman else { return nil }
        let frames = ballFrames
        let x = frames[0].midX
        let base = frames[0]
        let torso = frames[1]
        let head = frames[2]
        let headScale = radii[2] / 14
        let torsoScale = radii[1] / 21
        let baseScale = radii[0] / 28
        let neckScale = min(radii[1], radii[2]) / 14
        func dot(x: CGFloat, y: CGFloat, scale: CGFloat) -> CGRect {
            CGRect(x: x - 1.8 * scale, y: y - 1.8 * scale, width: 3.6 * scale, height: 3.6 * scale)
        }
        return WinterDecoration(
            eyes: [-5, 5].map { dot(x: x + CGFloat($0) * headScale, y: head.midY + 3 * headScale, scale: headScale) },
            mouth: [(-6.0, -6.5), (-3.2, -8.2), (0, -8.8), (3.2, -8.2), (6.0, -6.5)].map { dx, dy in
                dot(x: x + dx * headScale, y: head.midY + dy * headScale, scale: headScale * 0.5)
            },
            buttons: [dot(x: x, y: min(torso.midY + 10 * torsoScale,
                                      head.minY - 2 * neckScale - 3.8 * torsoScale), scale: torsoScale),
                      dot(x: x, y: torso.midY - 3 * torsoScale, scale: torsoScale),
                      dot(x: x, y: base.midY + 11 * baseScale, scale: baseScale)],
            nose: [CGPoint(x: x - headScale, y: head.midY - headScale),
                   CGPoint(x: x + 12 * headScale, y: head.midY - 4 * headScale),
                   CGPoint(x: x - headScale, y: head.midY - 6 * headScale)],
            scarf: [CGRect(x: x - 14 * neckScale, y: head.minY - 2 * neckScale,
                           width: 28 * neckScale, height: 6 * neckScale),
                    CGRect(x: x + 6 * neckScale, y: head.minY - 18 * torsoScale,
                           width: 6 * neckScale, height: 20 * torsoScale)])
    }
}

/// Удар до остановки игрушки, с массой относительно маленького шара.
struct WinterImpact {
    let support: CGWindowID?
    let x: CGFloat
    let radius: CGFloat
    let mass: CGFloat
    let velocity: CGVector
}
