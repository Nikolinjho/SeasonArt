import CoreGraphics
@testable import SeasonArt

extension WinterObject {
    /// Нижняя точка видимого силуэта: смятый шар опускается на свою вмятину.
    var visibleBottom: CGFloat { frame.minY + (outline(for: 0).map(\.y).min() ?? 0) }
    /// Верхняя точка видимого силуэта верхнего шара.
    var visibleTop: CGFloat { frame.minY + (outline(for: radii.count - 1).map(\.y).max() ?? frame.height) }
}

/// Шар лежит на снегу, утопленный на 15% радиуса нижнего шара, но не ниже ложа.
func winterRestingBottom(snow: CGFloat, bed: CGFloat = 0, radius: CGFloat) -> CGFloat {
    max(bed, snow - radius * SnowballWorld.footSink)
}

/// Наибольшее перекрытие кругов шаров разных фигур. Смятый шар законно заходит в соседа на глубину вмятины.
func winterWorstOverlap(_ scene: WinterScene) -> CGFloat {
    var worst: CGFloat = 0
    let circles = scene.objects.filter { !$0.parked }.map { object in
        object.ballCircles.enumerated().map { index, circle in
            (center: circle.center, radius: circle.radius * (1 - object.damage(for: index).depth * 1.25))
        }
    }
    for a in circles.indices {
        for b in circles.indices where b > a {
            for first in circles[a] {
                for second in circles[b] {
                    let distance = hypot(first.center.x - second.center.x, first.center.y - second.center.y)
                    worst = max(worst, first.radius + second.radius - distance)
                }
            }
        }
    }
    return worst
}
