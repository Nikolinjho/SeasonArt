import CoreGraphics
import simd

struct DockMagnificationSettings {
    var enabled: Bool
    var normalSize: CGFloat
    var largeSize: CGFloat

    static let disabled = Self(enabled: false, normalSize: 48, largeSize: 48)

    var isActive: Bool {
        enabled && normalSize.isFinite && largeSize.isFinite
            && normalSize >= 16 && largeSize > normalSize && largeSize <= 512
    }
}

/// Рамка самого изображения без служебных полей Dock и верхний контур его непрозрачных пикселей.
struct DockSnowIcon {
    let frame: CGRect
    let roof: [Float]
    var badge: DockSnowBadge? = nil

    func top(at x: Float) -> Float? {
        let badgeTop = badge?.top(at: x)
        guard roof.count > 1, frame.width > 0,
              x >= Float(frame.minX), x < Float(frame.maxX) else { return badgeTop }
        let index = min(Float(roof.count - 1), max(0, (x - Float(frame.minX)) / Float(frame.width) * Float(roof.count - 1)))
        let first = Int(index)
        let next = min(first + 1, roof.count - 1)
        let height = roof[first] + (roof[next] - roof[first]) * (index - Float(first))
        guard height > 0 else { return badgeTop }
        let iconTop = Float(frame.minY) + height * Float(frame.height)
        return badgeTop.map { max($0, iconTop) } ?? iconTop
    }
}

/// Цельная поверхность снега над Dock. Толщина берётся из накопленных физических колонок.
struct DockSnowSurface {
    private(set) var offsets: [Float] = []
    private var frame: CGRect?
    var maximum: Float { offsets.max() ?? 0 }

    @discardableResult
    mutating func step(dt: Float, frame: CGRect?, columns: Int, columnWidth: Float,
                       cursor: SIMD2<Float>, settings: DockMagnificationSettings, icons: [DockSnowIcon]?) -> Bool {
        guard let frame, columns > 0, columnWidth.isFinite, columnWidth > 0 else {
            let changed = !offsets.isEmpty
            offsets = []
            self.frame = nil
            return changed
        }
        guard dt.isFinite, dt > 0 else { return false }
        var fresh = [Float](repeating: 0, count: columns)
        let icons = settings.isActive ? (icons ?? []).filter { icon in
            icon.frame.minX.isFinite && icon.frame.minY.isFinite
                && icon.frame.width.isFinite && icon.frame.height.isFinite
                && icon.frame.width > 0 && icon.frame.height > 0
                && icon.roof.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }
        } : []
        for i in 0..<columns {
            let x = Float(frame.minX) + (Float(i) + 0.5) * columnWidth
            for icon in icons {
                if let roof = icon.top(at: x) {
                    fresh[i] = max(fresh[i], roof - Float(frame.maxY) - 0.8)
                }
            }
        }
        let changed = fresh != offsets || self.frame != frame
        offsets = fresh
        self.frame = frame
        return changed
    }

    /// Меняет только буфер отображения. Пустые физические участки не создают снежную массу.
    func apply(to buffer: UnsafeMutablePointer<Float>, columnWidth: Float, originX: Float)
        -> (top: Float, bottom: Float)? {
        let count = offsets.count
        guard count > 2, maximum > 0 else { return nil }
        var depths = [Float](repeating: 0, count: count)
        var beds = depths
        var tops = depths
        for i in 0..<count {
            let bed = buffer[count + i]
            let depth = max(0, buffer[i] - bed)
            depths[i] = depth
            beds[i] = offsets[i] > 0 ? max(bed, offsets[i]) : bed
            let x = originX + (Float(i) + 0.5) * columnWidth
            let grain = (0.55 * sin(x * 0.13 + 1.2) + 0.3 * cos(x * 0.37) + 0.16 * sin(x * 0.79)) * min(1, depth / 7)
            tops[i] = beds[i] + depth + grain
        }
        guard depths.contains(where: { $0 > 0.001 }) else { return nil }
        let raw = tops
        for i in 0..<count where depths[i] > 0.001 {
            var envelope = raw[i]
            for j in max(0, i - 18)...min(count - 1, i + 18) where depths[j] > 0.001 {
                let distance = Float(abs(i - j)) * columnWidth
                envelope = max(envelope, raw[j] - 0.16 * distance - 0.033 * distance * distance)
            }
            // Мелкая пыль почти не перекрывает промежутки, накопленный сугроб образует мягкие плечи.
            tops[i] += (envelope - raw[i]) * min(1, depths[i] / 7)
        }
        for _ in 0..<3 {
            let previous = tops
            for i in 1..<(count - 1) where depths[i] > 0.001 {
                let smoothed = previous[i - 1] * 0.25 + previous[i] * 0.5 + previous[i + 1] * 0.25
                let blended = previous[i] + (smoothed - previous[i]) * min(1, depths[i] / 7)
                tops[i] = max(beds[i] + depths[i] * 0.65, blended)
            }
        }
        for i in 0..<count {
            let edge = min(Float(i) * columnWidth, Float(count - i - 1) * columnWidth)
            let t = max(0, min(1, edge / 6))
            let depth = depths[i] > 0.001 ? max(0, tops[i] - beds[i]) * t * t * (3 - 2 * t) : 0
            buffer[i] = beds[i] + depth
            buffer[count + i] = beds[i]
        }
        return ((0..<count).map { buffer[$0] }.max() ?? 0, beds.min() ?? 0)
    }
}
