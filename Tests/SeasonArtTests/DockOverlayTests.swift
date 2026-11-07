import AppKit
import Metal
import QuartzCore
import XCTest
@testable import SeasonArt

final class DockOverlayTests: XCTestCase {
    func testСнежнаяПолосаНаходитсяПередСистемнымDockВПорядкеОкон() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let overlay = DockOverlay(screen: screen, device: device)
        defer { overlay.close() }
        let frame = try XCTUnwrap(overlay.nextFrame(reaching: 80))
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(commands.makeRenderCommandEncoder(descriptor: frame.pass))
        encoder.endEncoding()
        commands.present(frame.drawable)
        commands.commit()
        commands.waitUntilCompleted()
        CATransaction.flush()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        let windows = try XCTUnwrap(CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]])
        guard let dock = windows.firstIndex(where: {
            $0[kCGWindowOwnerName as String] as? String == "Dock"
                && $0[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(.dockWindow))
        }) else { throw XCTSkip("Для проверки нужен видимый системный Dock") }
        let snow = try XCTUnwrap(windows.firstIndex {
            $0[kCGWindowNumber as String] as? Int == overlay.window.windowNumber
        })
        XCTAssertLessThan(snow, dock, "Настоящий порядок окон должен держать снег перед стеклом Dock")
    }

    func testПолосаDockИспользуетФизическиеПикселиЭкрана() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let overlay = DockOverlay(screen: screen, device: device)
        defer { overlay.close() }
        let layer = try XCTUnwrap(overlay.window.contentView?.layer as? CAMetalLayer)
        let scale = screen.backingScaleFactor
        XCTAssertEqual(layer.contentsScale, scale, "Содержимое полосы учитывает масштаб Retina")
        XCTAssertEqual(layer.drawableSize.width, screen.frame.width * scale,
                       "Пиксели снежной кромки не растягиваются на Retina")
        XCTAssertEqual(layer.drawableSize.height, overlay.height * scale)
    }

    func testСнегНаDockРисуетсяНадСтекломИНеПерехватываетМышь() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let overlay = DockOverlay(screen: screen, device: device)
        defer { overlay.close() }
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
        XCTAssertGreaterThan(overlay.window.level.rawValue, dockLevel,
                             "Стекло Dock не должно размывать накопленный снег")
        XCTAssertTrue(overlay.window.ignoresMouseEvents, "Снежный слой пропускает клики к иконкам Dock")
        XCTAssertFalse(overlay.window.canBecomeKey)
        overlay.fit(to: screen)
        overlay.window.orderFrontRegardless()
        XCTAssertGreaterThan(overlay.window.level.rawValue, dockLevel,
                             "Обновление геометрии и порядка окон сохраняет снег над Dock")
    }
}
