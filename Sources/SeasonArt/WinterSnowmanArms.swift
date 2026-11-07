import CoreGraphics

extension WinterObject {
    /// Ветки растут из среднего шара. Координаты совпадают с ballFrames.
    var arms: [[CGPoint]] {
        guard isSnowman else { return [] }
        let torso = ballFrames[1]
        let radius = radii[1]
        return [-1.0, 1.0].flatMap { side -> [[CGPoint]] in
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: torso.midX + side * radius * x, y: torso.midY + radius * y)
            }
            let tipHeight: CGFloat = side < 0 ? 0.68 : 0.55
            return [[point(0.68, 0.18), point(1.22, 0.30), point(1.90, tipHeight)],
                    [point(1.46, 0.43), point(1.49, 0.85)],
                    [point(1.63, 0.51), point(2.01, 0.38)]]
        }
    }

    var armLineWidth: CGFloat { isSnowman ? max(0.8, radii[1] / 21 * 2.6) : 0 }

    /// Окно вмещает ветки, физическая геометрия шаров остаётся прежней.
    var drawingBounds: CGRect {
        var bounds = CGRect(origin: .zero, size: frame.size)
        let margin = armLineWidth / 2 + 0.5
        for point in arms.flatMap({ $0 }) {
            bounds = bounds.union(CGRect(x: point.x - margin, y: point.y - margin,
                                         width: margin * 2, height: margin * 2))
        }
        return bounds
    }

    var presentationFrame: CGRect {
        drawingBounds.offsetBy(dx: frame.minX, dy: frame.minY)
    }
}
