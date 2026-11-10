import CBox2D
import CoreGraphics
import Foundation

/// Колонки опоры в координатах сцены: верх снега и колонки, поднятые увеличенной иконкой Dock.
struct WinterSurfaceProfile {
    let left: CGFloat
    let columnWidth: CGFloat
    let tops: [CGFloat?]
    let lifted: [Bool]

    /// Вершины на границах колонок по верхней огибающей: ломаная не ниже ни одной колонки.
    var vertices: (xs: [CGFloat], heights: [CGFloat?], lifted: [Bool]) {
        guard !tops.isEmpty else { return ([], [], []) }
        var xs: [CGFloat] = []
        var heights: [CGFloat?] = []
        var raised: [Bool] = []
        for k in 0...tops.count {
            let left = k > 0 ? tops[k - 1] : nil
            let right = k < tops.count ? tops[k] : nil
            xs.append(self.left + CGFloat(k) * columnWidth)
            switch (left, right) {
            case let (a?, b?): heights.append(max(a, b))
            case let (a?, nil): heights.append(a)
            case let (nil, b?): heights.append(b)
            default: heights.append(nil)
            }
            raised.append((k > 0 && lifted[k - 1]) || (k < tops.count && lifted[k]))
        }
        return (xs, heights, raised)
    }
}

/// Ломаная опоры в мире Box2D. Снег догоняет поверхность с мёртвой зоной, пересобираются только изменившиеся куски.
final class WinterChainProfile {
    static let chunk = 32
    /// Рост снега меньше этого не двигает лежащие шары.
    static let deadband: CGFloat = 2
    /// Лежащий шар поднимается над снегом не быстрее, пт/с.
    static let riseSpeed: CGFloat = 8
    /// Опускание снега сразу роняет шары.
    static let dropTolerance: CGFloat = 0.5

    private let world: SnowballWorld
    let body: b2BodyId
    private let category: UInt64
    private let mask: UInt64
    private let hysteresis: Bool
    private(set) var xs: [CGFloat] = []
    private(set) var heights: [CGFloat?] = []
    private var rising: [Bool] = []
    private var chains: [[b2ChainId]] = []

    var isRising: Bool { rising.contains(true) }
    var top: CGFloat { heights.compactMap { $0 }.max() ?? -.infinity }

    init(world: SnowballWorld, body: b2BodyId, category: UInt64, mask: UInt64, hysteresis: Bool) {
        self.world = world
        self.body = body
        self.category = category
        self.mask = mask
        self.hysteresis = hysteresis
    }

    func destroy() {
        for chunk in chains { for chain in chunk { b2DestroyChain(chain) } }
        chains = []
        xs = []
        heights = []
        rising = []
    }

    /// Сдвиг вместе с окном сохраняет мёртвую зону снега.
    func shift(dx: CGFloat, dy: CGFloat) {
        guard !xs.isEmpty, dx != 0 || dy != 0 else { return }
        xs = xs.map { $0 + dx }
        heights = heights.map { $0.map { $0 + dy } }
        rebuild(Set(chains.indices))
    }

    /// Новая сетка берётся как есть. На той же сетке рост ждёт мёртвую зону и идёт не быстрее riseSpeed, опускание сразу.
    @discardableResult
    func update(xs newXs: [CGFloat], live: [CGFloat?], immediate: [Bool] = [], dt: CGFloat) -> Bool {
        guard newXs.count == live.count else { return false }
        let sameGrid = newXs.count == xs.count && zip(newXs, xs).allSatisfy { abs($0 - $1) < 0.001 }
        if !sameGrid {
            destroy()
            xs = newXs
            heights = live
            rising = Array(repeating: false, count: live.count)
            chains = Array(repeating: [], count: chunkCount)
            rebuild(Set(chains.indices))
            return true
        }
        var dirty = Set<Int>()
        let step = Self.riseSpeed * max(0, dt)
        for i in live.indices {
            let old = heights[i]
            var next = old
            switch (old, live[i]) {
            case (_, nil):
                next = nil
                rising[i] = false
            case (nil, let target?):
                next = target
                rising[i] = false
            case (let current?, let target?):
                if !hysteresis || (immediate.indices.contains(i) && immediate[i]) {
                    if abs(target - current) > 0.01 { next = target }
                    rising[i] = false
                } else if target < current - Self.dropTolerance {
                    next = target
                    rising[i] = false
                } else if rising[i] || target > current + Self.deadband {
                    next = min(target, current + step)
                    rising[i] = next! < target
                }
            }
            if next != old {
                heights[i] = next
                for c in max(0, (i - 1) / Self.chunk)...min(chunkCount - 1, (i + 1) / Self.chunk) { dirty.insert(c) }
            }
        }
        rebuild(dirty)
        return !dirty.isEmpty
    }

    private var chunkCount: Int { max(1, (xs.count - 2) / Self.chunk + 1) }

    private func rebuild(_ dirty: Set<Int>) {
        for c in dirty.sorted() where chains.indices.contains(c) {
            for chain in chains[c] { b2DestroyChain(chain) }
            chains[c] = []
            let first = c * Self.chunk
            let last = min(xs.count - 1, (c + 1) * Self.chunk)
            guard first < last else { continue }
            var start: Int?
            for i in first...last {
                if heights[i] != nil {
                    if start == nil { start = i }
                } else {
                    if let s = start, i - 1 > s { chains[c].append(makeRun(s, i - 1)) }
                    start = nil
                }
            }
            if let s = start, last > s { chains[c].append(makeRun(s, last)) }
        }
    }

    /// Справа налево, с призраками соседей. На краю опоры призрак уходит вниз: шар скатывается с кромки.
    private func makeRun(_ start: Int, _ end: Int) -> b2ChainId {
        func point(_ i: Int) -> CGPoint { CGPoint(x: xs[i], y: heights[i]!) }
        var points: [CGPoint] = []
        if end + 1 < xs.count, heights[end + 1] != nil {
            points.append(point(end + 1))
        } else {
            points.append(CGPoint(x: xs[end] + 2, y: heights[end]! - 50))
        }
        for i in stride(from: end, through: start, by: -1) {
            let next = point(i)
            if let last = points.last, abs(last.x - next.x) < 0.3, abs(last.y - next.y) < 0.3, points.count > 1 { continue }
            points.append(next)
        }
        if start > 0, heights[start - 1] != nil {
            points.append(point(start - 1))
        } else {
            points.append(CGPoint(x: xs[start] - 2, y: heights[start]! - 50))
        }
        if points.count < 4 {
            points.insert(CGPoint(x: (points[0].x + points[1].x) / 2, y: (points[0].y + points[1].y) / 2), at: 1)
        }
        return world.makeChain(on: body, points: points, category: category, mask: mask)
    }
}

/// Твёрдое тело Dock: суперэллипс углов, как основание SnowLayer, без высоты снега.
extension WindowSurface {
    func winterRoof(at x: CGFloat) -> CGFloat {
        let radius = max(0, min(cornerRadius, frame.width / 2, frame.height / 2))
        guard radius > 0 else { return frame.maxY }
        let distance = max(0, min(x - frame.minX, frame.maxX - x))
        let u = max(0, 1 - distance / radius)
        let exponent = max(1, cornerExponent)
        return frame.maxY - radius * (1 - pow(max(0, 1 - pow(u, exponent)), 1 / exponent))
    }

    /// Нижняя точка шара над выпуклым силуэтом учитывает всю ширину касания.
    func winterRestHeight(at x: CGFloat, radius: CGFloat) -> CGFloat {
        guard radius > 0, cornerRadius > 0 else { return winterRoof(at: x) }
        let corner = min(cornerRadius, frame.width / 2, frame.height / 2)
        if x >= frame.minX + corner && x <= frame.maxX - corner { return frame.maxY }
        var low = max(frame.minX, x - radius)
        var high = min(frame.maxX, x + radius)
        guard low <= high else { return winterRoof(at: x) }
        func clearance(_ sample: CGFloat) -> CGFloat {
            winterRoof(at: sample) + sqrt(max(0, radius * radius - pow(sample - x, 2)))
        }
        for _ in 0..<40 {
            let a = low + (high - low) / 3
            let b = high - (high - low) / 3
            if clearance(a) < clearance(b) { low = a } else { high = b }
        }
        return clearance((low + high) / 2) - radius
    }

    func winterClosestPoint(to point: CGPoint) -> CGPoint {
        let body = frame
        if point.x >= body.minX, point.x <= body.maxX,
           point.y >= body.minY, point.y <= winterRoof(at: point.x) { return point }
        let radius = max(0, min(cornerRadius, body.width / 2, body.height / 2))
        let sideTop = body.maxY - radius
        if point.y >= body.maxY, point.x >= body.minX + radius, point.x <= body.maxX - radius {
            return CGPoint(x: point.x, y: body.maxY)
        }
        if point.x <= body.minX, point.y >= body.minY, point.y <= sideTop { return CGPoint(x: body.minX, y: point.y) }
        if point.x >= body.maxX, point.y >= body.minY, point.y <= sideTop { return CGPoint(x: body.maxX, y: point.y) }
        var candidates = [CGPoint(x: min(max(point.x, body.minX), body.maxX), y: body.minY),
                          CGPoint(x: body.minX, y: min(max(point.y, body.minY), sideTop)),
                          CGPoint(x: body.maxX, y: min(max(point.y, body.minY), sideTop)),
                          CGPoint(x: min(max(point.x, body.minX + radius), body.maxX - radius), y: body.maxY)]
        func squaredDistance(_ x: CGFloat) -> CGFloat { pow(x - point.x, 2) + pow(winterRoof(at: x) - point.y, 2) }
        if radius > 0 {
            for start in [body.minX, body.maxX - radius] {
                var low = start
                var high = start + radius
                for _ in 0..<40 {
                    let a = low + (high - low) / 3
                    let b = high - (high - low) / 3
                    if squaredDistance(a) < squaredDistance(b) { high = b } else { low = a }
                }
                let x = (low + high) / 2
                candidates.append(CGPoint(x: x, y: winterRoof(at: x)))
            }
        }
        return candidates.min { hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y) }!
    }

    /// Контур против часовой стрелки: цепочка-петля сталкивается снаружи.
    var winterOutline: [CGPoint] {
        let body = frame
        let radius = max(0, min(cornerRadius, body.width / 2, body.height / 2))
        var points = [CGPoint(x: body.minX, y: body.minY), CGPoint(x: body.maxX, y: body.minY)]
        let exponent = max(1, cornerExponent)
        if radius > 0.5 {
            let steps = 16
            for k in 0...steps {
                let t = CGFloat(k) / CGFloat(steps) * .pi / 2
                points.append(CGPoint(x: body.maxX - radius + radius * pow(cos(t), 2 / exponent),
                                      y: body.maxY - radius + radius * pow(sin(t), 2 / exponent)))
            }
            for k in 0...steps {
                let t = CGFloat(k) / CGFloat(steps) * .pi / 2
                points.append(CGPoint(x: body.minX + radius - radius * pow(sin(t), 2 / exponent),
                                      y: body.maxY - radius + radius * pow(cos(t), 2 / exponent)))
            }
        } else {
            points += [CGPoint(x: body.maxX, y: body.maxY), CGPoint(x: body.minX, y: body.maxY)]
        }
        var result: [CGPoint] = []
        for point in points where result.last.map({ hypot($0.x - point.x, $0.y - point.y) > 0.3 }) ?? true {
            result.append(point)
        }
        if let first = result.first, let last = result.last, hypot(first.x - last.x, first.y - last.y) <= 0.3 { result.removeLast() }
        return result
    }
}
