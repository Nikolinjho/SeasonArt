import CoreGraphics
import Foundation

/// Один проход по подтверждённой горизонтальной полке Dock.
struct WinterPlowPass {
    let surfaceID: CGWindowID
    let shelf: CGRect
    private(set) var bladeX: CGFloat

    var frame: CGRect { CGRect(x: bladeX, y: shelf.maxY, width: 108, height: 58) }
    var finished: Bool { frame.maxX < shelf.minX }

    init?(surface: WindowSurface) {
        let frame = surface.frame
        guard surface.isDock, frame.width >= 80, frame.height > 0,
              frame.width >= frame.height * 2,
              [frame.minX, frame.minY, frame.width, frame.height, frame.maxX, frame.maxY, frame.maxX + 24].allSatisfy({ $0.isFinite }) else { return nil }
        surfaceID = surface.id
        shelf = frame
        bladeX = frame.maxX + 24
    }

    /// Возвращает только пройденную часть полки, а не всю рамку машины.
    mutating func advance(dt: TimeInterval) -> ClosedRange<CGFloat>? {
        guard dt.isFinite, dt > 0, !finished else { return nil }
        let before = bladeX
        bladeX -= CGFloat(min(dt, 1 / 30)) * 160
        let left = max(bladeX, shelf.minX)
        let right = min(before, shelf.maxX)
        return left < right ? left...right : nil
    }
}
