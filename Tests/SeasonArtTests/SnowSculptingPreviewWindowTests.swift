import AppKit
import XCTest
@testable import SeasonArt

final class SnowSculptingPreviewWindowTests: XCTestCase {
    func testПредпросмотрМаленькийПропускаетВводИНеПринимаетФокус() throws {
        _ = NSApplication.shared
        let window = SnowSculptingPreviewWindow()
        defer { window.close() }
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)
        XCTAssertTrue(window.styleMask.contains(.nonactivatingPanel))
        let layer = SnowLayer(origin: .zero, columns: 400, columnWidth: 2, depth: 40, opensAtEdges: false, phases: (0, 0))
        layer.replace(heights: layer.heights.map { _ in 5 })
        var gesture = SnowSculptingGesture(source: SculptingSource(layer: layer), at: CGPoint(x: 100, y: 1))
        gesture.include(CGPoint(x: 130, y: 1))
        window.display(gesture, screenFrame: CGRect(x: -800, y: 100, width: 800, height: 600))
        XCTAssertLessThan(window.frame.width, 150)
        XCTAssertLessThan(window.frame.height, 150)
        XCTAssertFalse(window.isVisible, "Проверка не показывает окно на рабочем столе")
        window.showsInScreenshots = true
        XCTAssertEqual(window.sharingType, .readOnly)
    }
    func testПредпросмотрРастётПромежуточнымиРадиусами() throws {
        _ = NSApplication.shared
        let window = SnowSculptingPreviewWindow()
        defer { window.close() }
        let layer = SnowLayer(origin: .zero, columns: 200, columnWidth: 2, depth: 40, opensAtEdges: false, phases: (0, 0))
        layer.replace(heights: layer.heights.map { _ in 8 })
        var gesture = SnowSculptingGesture(source: SculptingSource(layer: layer), at: CGPoint(x: 1, y: 1))
        var previous: CGFloat = 0
        for x: CGFloat in [19, 35, 49, 67, 91, 109] {
            gesture.include(CGPoint(x: x, y: 1))
            window.display(gesture, screenFrame: .zero)
            let radius = try XCTUnwrap(gesture.radius)
            XCTAssertEqual(window.frame.width, radius * 2 + 4, accuracy: 1)
            XCTAssertEqual(window.frame.midY, gesture.center.y, accuracy: 0.5)
            XCTAssertGreaterThan(window.frame.width, previous)
            previous = window.frame.width
        }
        XCTAssertFalse(window.isVisible)
    }

}
