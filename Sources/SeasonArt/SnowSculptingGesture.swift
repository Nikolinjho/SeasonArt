import CoreGraphics
import Foundation

/// Неизменяемый снимок одной опоры. Ссылка удерживает идентичность удалённого слоя.
struct SculptingSource {
    let layer: SnowLayer
    let origin: SIMD2<Float>
    let base: SIMD2<Float>
    let drift: Float
    let right: Float
    let bed: [Float]
    let heights: [Float]
    let visible: [Bool]
    let columnWidth: CGFloat
    let isDock: Bool
    let face: Float

    init(layer: SnowLayer, visible: [Bool]? = nil) {
        self.layer = layer
        origin = layer.origin
        base = layer.base
        drift = layer.drift
        right = layer.right
        bed = layer.bed
        heights = layer.heights
        self.visible = visible ?? layer.visible
        columnWidth = CGFloat(layer.columnWidth)
        isDock = layer.isDock
        face = layer.face
    }

    func column(at point: CGPoint) -> Int? {
        guard point.x.isFinite, point.y.isFinite, columnWidth.isFinite, columnWidth > 0,
              point.x >= CGFloat(base.x), point.x < CGFloat(base.x) + CGFloat(heights.count) * columnWidth else { return nil }
        let index = Int(((point.x - CGFloat(base.x)) / columnWidth).rounded(.down))
        guard visible[index], heights[index].isFinite, heights[index] > 0 else { return nil }
        let floor = CGFloat(base.y + bed[index])
        guard point.y >= floor, point.y <= floor + CGFloat(heights[index]) + 8 else { return nil }
        return index
    }
}

struct SculptedBall {
    let size: WinterBallSize
    let center: CGPoint
    let collectedArea: CGFloat
}

/// Черновик собирает каждую колонку один раз и не изменяет симуляцию.
struct SnowSculptingGesture {
    static let smallArea: CGFloat = 40
    static let mediumArea: CGFloat = 100
    static let largeArea: CGFloat = 220
    static let maximumColumnHeight: CGFloat = 2

    let source: SculptingSource
    private(set) var columns: [Int] = []
    private(set) var collectedArea: CGFloat = 0
    private(set) var lastPoint: CGPoint
    private var visited = Set<Int>()
    private var previous: CGPoint?
    private var collectedPoint: CGPoint

    init(source: SculptingSource, at point: CGPoint) {
        self.source = source
        lastPoint = .zero
        collectedPoint = .zero
        include(point)
    }

    var size: WinterBallSize? {
        Self.size(for: collectedArea)
    }

    static func size(for area: CGFloat) -> WinterBallSize? {
        guard area.isFinite else { return nil }
        if area >= largeArea { return .large }
        if area >= mediumArea { return .medium }
        return area >= smallArea ? .small : nil
    }

    var center: CGPoint {
        CGPoint(x: collectedPoint.x, y: collectedPoint.y + (size?.radius ?? WinterBallSize.small.radius))
    }

    mutating func include(_ point: CGPoint) {
        // События AppKit лежат в пределах экранов. Отсекаем нереальные координаты до интерполяции.
        guard point.x.isFinite, point.y.isFinite, abs(point.x) <= 1_000_000, abs(point.y) <= 1_000_000 else {
            previous = nil
            return
        }
        lastPoint = point
        defer { previous = point }
        if let previous, previous.x != point.x {
            let left = max(min(previous.x, point.x), CGFloat(source.base.x))
            let right = min(max(previous.x, point.x), CGFloat(source.base.x) + CGFloat(source.heights.count) * source.columnWidth)
            if left < right {
                // Итерация по конечному снимку безопасна даже при огромных координатах.
                let dx = point.x - previous.x
                if dx.isFinite {
                    for index in source.heights.indices {
                        let x = CGFloat(source.base.x) + (CGFloat(index) + 0.5) * source.columnWidth
                        guard x >= left, x <= right else { continue }
                        let fraction = (x - previous.x) / dx
                        let y = previous.y * (1 - fraction) + point.y * fraction
                        collect(CGPoint(x: x, y: y))
                    }
                }
            }
        }
        collect(point)
        if let index = source.column(at: point) {
            collectedPoint = CGPoint(x: point.x, y: CGFloat(source.base.y + source.bed[index] + source.heights[index]))
        }
    }

    private mutating func collect(_ point: CGPoint) {
        guard collectedArea < Self.largeArea, let index = source.column(at: point), visited.insert(index).inserted else { return }
        columns.append(index)
        collectedArea = min(Self.largeArea, collectedArea + min(Self.maximumColumnHeight, CGFloat(source.heights[index])) * source.columnWidth)
    }
}
