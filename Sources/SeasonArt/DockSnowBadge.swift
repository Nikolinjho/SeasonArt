import AppKit

/// Dock сообщает текст бейджа без отдельной AX-рамки. Геометрия привязана к нативному масштабу значка.
struct DockSnowBadge: Equatable {
    let frame: CGRect

    init?(label: String?, iconFrame: CGRect) {
        guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty,
              iconFrame.minX.isFinite, iconFrame.minY.isFinite,
              iconFrame.width.isFinite, iconFrame.height.isFinite,
              iconFrame.width > 0, iconFrame.height > 0 else { return nil }
        let side = iconFrame.width
        let diameter = side * 0.38
        // Один шрифт-образец масштабируется вместе со значком без скачков оптического размера.
        let font = NSFont.systemFont(ofSize: 10, weight: .medium)
        let textWidth = (String(label.prefix(16)) as NSString).size(withAttributes: [.font: font]).width * side * 0.021
        let width = min(side * 1.4, max(diameter, textWidth + side * 0.08))
        // Рамка изображения включает прозрачные поля. Верх бейджа чуть выше её верхнего края.
        frame = CGRect(x: iconFrame.maxX - width, y: iconFrame.maxY + side * 0.02 - diameter,
                       width: width, height: diameter)
    }

    func top(at x: Float) -> Float? {
        guard x.isFinite, x >= Float(frame.minX), x <= Float(frame.maxX) else { return nil }
        let radius = Float(frame.height / 2)
        let center = min(max(x, Float(frame.minX) + radius), Float(frame.maxX) - radius)
        let dx = x - center
        return Float(frame.midY) + sqrt(max(0, radius * radius - dx * dx))
    }
}
