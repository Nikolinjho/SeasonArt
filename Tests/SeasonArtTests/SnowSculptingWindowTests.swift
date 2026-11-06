import AppKit
import XCTest
@testable import SeasonArt

final class SnowSculptingWindowTests: XCTestCase {
    func testPanelOwnsOnlyTemporaryInputAndClosesIdempotently() throws {
        _ = NSApplication.shared
        let panel = SnowSculptingWindow(screenFrame: CGRect(x: -800, y: 100, width: 800, height: 600))
        XCTAssertTrue(panel.canBecomeKey, "Панель принимает Esc")
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(try XCTUnwrap(panel.contentView).acceptsFirstResponder)
        XCTAssertFalse(panel.ignoresMouseEvents)
        panel.showsInScreenshots = true
        XCTAssertEqual(panel.sharingType, .readOnly)
        var cancelled = 0
        panel.cancelled = { cancelled += 1 }
        panel.cancelOperation(nil)
        panel.cancelOperation(nil)
        panel.close()
        XCTAssertEqual(cancelled, 1, "Отмена происходит ровно один раз")
        XCTAssertFalse(panel.isVisible)
    }

    func testOnlyEscapeConsumesKeyboardEquivalent() throws {
        _ = NSApplication.shared
        let panel = SnowSculptingWindow(screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600))
        defer { panel.close() }
        let view = try XCTUnwrap(panel.contentView)
        let command = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 1, windowNumber: panel.windowNumber, context: nil, characters: "q",
            charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12))
        XCTAssertFalse(view.performKeyEquivalent(with: command), "Необработанная команда остаётся цепочке responder приложения")
        var cancelled = 0
        panel.cancelled = { cancelled += 1 }
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 2, windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        XCTAssertTrue(view.performKeyEquivalent(with: escape))
        XCTAssertEqual(cancelled, 1, "Esc отменяет ровно один жест")
    }

    func testMouseCallbacksUseGlobalCoordinatesAndIgnoreClosedPanel() throws {
        _ = NSApplication.shared
        let panel = SnowSculptingWindow(screenFrame: CGRect(x: -800, y: 100, width: 800, height: 600))
        defer { panel.close() }
        let view = try XCTUnwrap(panel.contentView)
        let location = CGPoint(x: 30, y: 20)
        var points: [CGPoint] = []
        panel.began = { points.append($0) }
        panel.moved = { points.append($0) }
        panel.ended = { points.append($0) }
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 1,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        view.mouseDown(with: try event(.leftMouseDown))
        view.mouseDragged(with: try event(.leftMouseDragged))
        view.mouseUp(with: try event(.leftMouseUp))
        XCTAssertEqual(points, Array(repeating: CGPoint(x: -770, y: 120), count: 3))
        panel.close()
        view.mouseDown(with: try event(.leftMouseDown))
        XCTAssertEqual(points.count, 3, "Закрытая панель больше не вызывает обработчики")
    }
}
