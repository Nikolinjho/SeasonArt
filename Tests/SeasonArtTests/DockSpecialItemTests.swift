import AppKit
import ApplicationServices
import XCTest
@testable import SeasonArt

final class DockSpecialItemTests: XCTestCase {
    private func nativeItems() throws -> [(subrole: String, frame: CGRect)] {
        guard AXIsProcessTrusted(),
              let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        else { throw XCTSkip("Нужен видимый Dock и доступ к его AX-геометрии") }
        func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
            var result: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(element, key as CFString, &result)
            return result
        }
        var result: [(String, CGRect)] = []
        for list in value(AXUIElementCreateApplication(pid), kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            for item in value(list, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                guard let role = value(item, kAXSubroleAttribute) as? String,
                      let position = value(item, kAXPositionAttribute), let size = value(item, kAXSizeAttribute),
                      CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { continue }
                var point = CGPoint.zero
                var span = CGSize.zero
                AXValueGetValue(position as! AXValue, .cgPoint, &point)
                AXValueGetValue(size as! AXValue, .cgSize, &span)
                result.append((role, CGRect(origin: point, size: span)))
            }
        }
        return result
    }

    func testКорзинаБезURLУчаствуетВКонтуреDock() throws {
        let items = try nativeItems()
        let trash = try XCTUnwrap(items.first { $0.subrole == "AXTrashDockItem" })
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let geometry = DockIconGeometry()
        func sampleNear(at now: CFTimeInterval) -> (settings: DockMagnificationSettings, icons: [DockSnowIcon]?, dock: CGRect?) {
            geometry.update(now: now, screen: screen.frame, primaryHeight: screen.frame.maxY,
                dock: CGRect(x: 0, y: 6, width: screen.frame.width, height: 60),
                cursor: CGPoint(x: trash.frame.midX, y: 30))
        }
        _ = sampleNear(at: 1)
        geometry.finishPendingSample()
        let sample = sampleNear(at: 1.01)
        guard sample.settings.isActive else { throw XCTSkip("Нужно включённое увеличение Dock") }
        let icons = try XCTUnwrap(sample.icons)
        XCTAssertTrue(icons.contains { abs($0.frame.midX - trash.frame.midX) < 4 },
                      "Корзина с AXTrashDockItem и без AXURL должна иметь снежный контур")
    }

    func testБейджиОстаютсяВГеометрииПослеУходаУказателя() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        _ = try nativeItems()
        let geometry = DockIconGeometry()
        let dock = CGRect(x: 0, y: 6, width: screen.frame.width, height: 60)
        _ = geometry.update(now: 1, screen: screen.frame, primaryHeight: screen.frame.maxY,
                            dock: dock, cursor: CGPoint(x: screen.frame.midX, y: 30))
        geometry.finishPendingSample()
        let near = geometry.update(now: 1.01, screen: screen.frame, primaryHeight: screen.frame.maxY,
                                   dock: dock, cursor: CGPoint(x: screen.frame.midX, y: 30))
        guard near.icons?.contains(where: { $0.badge != nil }) == true else {
            throw XCTSkip("Нужен видимый бейдж Dock и включённое увеличение")
        }
        _ = geometry.update(now: 3, screen: screen.frame, primaryHeight: screen.frame.maxY,
                            dock: dock, cursor: CGPoint(x: -1000, y: -1000))
        geometry.finishPendingSample()
        let away = geometry.update(now: 3.01, screen: screen.frame, primaryHeight: screen.frame.maxY,
                                   dock: dock, cursor: CGPoint(x: -1000, y: -1000))
        XCTAssertTrue(away.icons?.contains(where: { $0.badge != nil }) == true,
                      "Уведомления остаются опорой для снега без наведения")
    }
}
