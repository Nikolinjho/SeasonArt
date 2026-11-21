import AppKit

struct WinterScarf {
    let wrap: CGRect
    let tailLength: CGFloat

    var bounds: CGRect {
        CGRect(x: wrap.minX, y: wrap.minY - tailLength,
               width: wrap.width, height: wrap.height + tailLength)
    }
}

enum WinterOutfit: CaseIterable {
    case berry, spruce, night

    init(snowman id: UUID) {
        self = Self.allCases[Int(id.uuid.0) % Self.allCases.count]
    }

    func scarf(between head: CGRect, and torso: CGRect, below face: CGFloat) -> WinterScarf {
        let headRadius = head.width / 2
        let torsoRadius = torso.width / 2
        let smallerRadius = min(headRadius, torsoRadius)
        let distance = head.midY - torso.midY
        // Стык находится там, где пересекаются очертания головы и туловища.
        let seam = (torsoRadius * torsoRadius - headRadius * headRadius + distance * distance) / (2 * distance)
        let halfNeck = sqrt(max(0, torsoRadius * torsoRadius - seam * seam))
        let top = min(torso.midY + seam + smallerRadius * 0.11, face)
        let halfWidth = halfNeck + smallerRadius * 0.10
        let style = scarfStyle
        let height = smallerRadius * style.wrapHeight
        let tail = min(torsoRadius * 0.74, halfNeck * 1.30) * style.tailLength
        return WinterScarf(wrap: CGRect(x: head.midX - halfWidth, y: top - height,
                                       width: halfWidth * 2, height: height), tailLength: tail)
    }

    func hat(on head: CGRect) -> CGRect {
        let style = hatStyle
        let radius = head.width / 2
        let rise = radius * style.seat
        let brim = 2 * sqrt(radius * radius - rise * rise)
        let width = brim * style.width
        let height = width * style.profile
        return CGRect(x: head.midX + radius * style.shift - width / 2,
                      y: head.midY + rise - height * style.brim, width: width, height: height)
    }

    func drawScarf(_ scarf: WinterScarf) {
        let style = scarfStyle
        let source = style.source
        // Петля и свободный конец масштабируются отдельно, сохраняя общий рисунок вязки.
        let wrapSource = CGRect(x: source.minX, y: source.minY, width: source.width, height: style.split)
        let tailSource = CGRect(x: source.minX, y: wrapSource.maxY, width: source.width, height: source.height - style.split)
        let tail = CGRect(x: scarf.wrap.minX, y: scarf.bounds.minY, width: scarf.wrap.width, height: scarf.tailLength)
        draw(from: tailSource, in: tail)
        draw(from: wrapSource, in: scarf.wrap)
    }

    func drawHat(_ rect: CGRect) {
        draw(from: hatStyle.source, in: rect)
    }

    private var scarfStyle: (source: CGRect, split: CGFloat, wrapHeight: CGFloat, tailLength: CGFloat) {
        switch self {
        case .berry: return (CGRect(x: 55, y: 618, width: 419, height: 345), 167, 0.48, 0.96)
        case .spruce: return (CGRect(x: 529, y: 619, width: 434, height: 321), 162, 0.44, 1.00)
        case .night: return (CGRect(x: 1068, y: 618, width: 423, height: 338), 175, 0.52, 0.88)
        }
    }

    private var hatStyle: (source: CGRect, seat: CGFloat, width: CGFloat, profile: CGFloat, brim: CGFloat, shift: CGFloat) {
        switch self {
        case .berry: return (CGRect(x: 87, y: 70, width: 383, height: 435), 0.60, 1.04, 0.94, 0.18, -0.02)
        case .spruce: return (CGRect(x: 566, y: 62, width: 384, height: 465), 0.63, 1.07, 1.03, 0.27, 0.05)
        case .night: return (CGRect(x: 1051, y: 127, width: 428, height: 370), 0.58, 1.10, 0.78, 0.29, 0)
        }
    }

    /// Координаты раскладки в исходном атласе до уменьшения для бандла.
    private func draw(from source: CGRect, in rect: CGRect) {
        guard let atlas = WinterArtwork.clothing else { return }
        let sx = atlas.size.width / 1536
        let sy = atlas.size.height / 1024
        let sample = CGRect(x: source.minX * sx, y: atlas.size.height - source.maxY * sy,
                            width: source.width * sx, height: source.height * sy)
        atlas.draw(in: rect, from: sample, operation: .sourceOver, fraction: 1)
    }
}
