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
    let displayLeft: CGFloat
    let displayBed: [Float]
    let displayTop: [Float]
    var massColumnWidth: CGFloat { CGFloat(layer.columnWidth) }
    let isDock: Bool
    let face: Float

    init(layer: SnowLayer, visible: [Bool]? = nil, presentationFrame: CGRect? = nil, contour: [Float]? = nil) {
        self.layer = layer
        origin = layer.origin
        base = layer.base
        drift = layer.drift
        right = layer.right
        bed = layer.bed
        heights = layer.heights
        self.visible = visible ?? layer.visible
        displayLeft = presentationFrame?.minX ?? CGFloat(layer.base.x)
        columnWidth = presentationFrame.map { $0.width / CGFloat(layer.count) } ?? CGFloat(layer.columnWidth)
        if let contour, contour.count == layer.count * 2 {
            displayTop = Array(contour.prefix(layer.count))
            displayBed = Array(contour.suffix(layer.count))
        } else {
            displayTop = zip(layer.bed, layer.heights).map(+)
            displayBed = layer.bed
        }
        isDock = layer.isDock
        face = layer.face
    }

    func column(at point: CGPoint) -> Int? {
        guard point.y.isFinite, let index = column(atX: point.x) else { return nil }
        guard visible[index], heights[index].isFinite, heights[index] > 0 else { return nil }
        let floor = CGFloat(base.y + displayBed[index])
        guard point.y >= floor, point.y <= surface(at: index) + 8 else { return nil }
        return index
    }

    func column(atX x: CGFloat) -> Int? {
        guard x.isFinite, columnWidth.isFinite, columnWidth > 0,
              x >= displayLeft, x < displayLeft + CGFloat(heights.count) * columnWidth else { return nil }
        return min(heights.count - 1, Int(((x - displayLeft) / columnWidth).rounded(.down)))
    }

    func surface(at index: Int) -> CGFloat { CGFloat(base.y + displayTop[index]) }
}

struct SculptedBall {
    let radius: CGFloat
    let center: CGPoint
    let collectedArea: CGFloat
}

/// Черновик собирает каждую колонку один раз и не изменяет симуляцию.
struct SnowSculptingGesture {
    static let smallArea: CGFloat = 40
    static let mediumArea: CGFloat = 100
    static let largeArea: CGFloat = 220
    static let maximumColumnHeight: CGFloat = 2

    private(set) var source: SculptingSource
    private(set) var columns: [Int] = []
    private(set) var collectedArea: CGFloat = 0
    private(set) var lastPoint: CGPoint
    private var visited = Set<Int>()
    private var previous: CGPoint?
    private var collectedPoint: CGPoint
    private let paced: Bool
    private var movingTime: TimeInterval = 0

    init(source: SculptingSource, at point: CGPoint, paced: Bool = false) {
        self.paced = paced
        self.source = source
        lastPoint = .zero
        collectedPoint = .zero
        include(point)
    }

    /// Время ограничивает видимую массу, а уникальные колонки — доступный запас снега.
    var effectiveArea: CGFloat {
        guard paced else { return collectedArea }
        guard movingTime + 1e-9 >= 0.25 else { return 0 }
        let progress = CGFloat(min(1, max(0, (movingTime - 0.25) / 1.5)))
        return min(collectedArea, Self.smallArea + progress * (Self.largeArea - Self.smallArea))
    }

    var radius: CGFloat? { Self.radius(for: effectiveArea) }
    var isFull: Bool { effectiveArea >= Self.largeArea - 1e-9 }

    static func radius(for area: CGFloat) -> CGFloat? {
        guard area.isFinite, area >= smallArea else { return nil }
        let progress = min(1, (area - smallArea) / (largeArea - smallArea))
        return WinterBallGeometry.minimumRadius
            + progress * (WinterBallGeometry.maximumRadius - WinterBallGeometry.minimumRadius)
    }

    var center: CGPoint {
        CGPoint(x: collectedPoint.x, y: collectedPoint.y + (radius ?? WinterBallGeometry.minimumRadius))
    }

    /// Изменение размеров иконок обновляет геометрию, сохраняя уже собранные колонки и темп жеста.
    mutating func updateSource(_ fresh: SculptingSource) {
        guard fresh.layer === source.layer, fresh.heights.count == source.heights.count else { return }
        source = fresh
        if let index = fresh.column(atX: collectedPoint.x) { collectedPoint.y = fresh.surface(at: index) }
    }

    mutating func include(_ point: CGPoint, dt: TimeInterval = 0) {
        // События AppKit лежат в пределах экранов. Отсекаем нереальные координаты до интерполяции.
        guard point.x.isFinite, point.y.isFinite, abs(point.x) <= 1_000_000, abs(point.y) <= 1_000_000 else {
            previous = nil
            return
        }
        if let previous, previous != point,
           source.column(at: previous) != nil, source.column(at: point) != nil,
           dt.isFinite, dt > 0 {
            movingTime += min(dt, 0.05)
        }
        lastPoint = point
        defer { previous = point }
        if let previous, previous.x != point.x {
            let left = max(min(previous.x, point.x), source.displayLeft)
            let right = min(max(previous.x, point.x), source.displayLeft + CGFloat(source.heights.count) * source.columnWidth)
            if left < right {
                // Итерация по конечному снимку безопасна даже при огромных координатах.
                let dx = point.x - previous.x
                if dx.isFinite {
                    for index in source.heights.indices {
                        let x = source.displayLeft + (CGFloat(index) + 0.5) * source.columnWidth
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
            collectedPoint = CGPoint(x: point.x, y: source.surface(at: index))
        }
    }

    private mutating func collect(_ point: CGPoint) {
        guard collectedArea < Self.largeArea, let index = source.column(at: point), visited.insert(index).inserted else { return }
        columns.append(index)
        collectedArea = min(Self.largeArea, collectedArea + min(Self.maximumColumnHeight, CGFloat(source.heights[index])) * source.massColumnWidth)
    }
}
