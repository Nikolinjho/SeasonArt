import AppKit
import XCTest
@testable import SeasonArt

final class WinterObjectWindowTests: XCTestCase {
    private let screen = CGRect(x: -1440, y: 180, width: 1440, height: 900)

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    private func object(sizes: [WinterBallSize] = [.large], center: CGPoint = CGPoint(x: 200, y: 100)) -> WinterObject {
        WinterObject(id: UUID(), radii: sizes.map(\.radius), center: center, velocity: .zero,
                     support: nil, parked: false, isDragged: false)
    }

    func testObjectFrameUsesGlobalScreenOrigin() {
        let model = object()
        let window = WinterObjectWindow(object: model, screenFrame: screen)
        defer { window.close() }
        XCTAssertEqual(window.frame, model.frame.offsetBy(dx: screen.minX, dy: screen.minY), "Окно учитывает начало второго экрана")
        XCTAssertFalse(window.isVisible, "Создание объекта не показывает окно")
    }

    func testObjectPanelDoesNotActivateApplication() {
        let window = WinterObjectWindow(object: object(), screenFrame: screen)
        defer { window.close() }
        XCTAssertTrue(window.styleMask.contains(.nonactivatingPanel), "Перетаскивание не активирует приложение")
        XCTAssertFalse(window.canBecomeKey, "Снежок не забирает клавиатурный фокус")
        XCTAssertFalse(window.canBecomeMain, "Снежок не становится главным окном")
        XCTAssertFalse(window.ignoresMouseEvents, "Снежок принимает перетаскивание")
        XCTAssertFalse(window.hidesOnDeactivate, "Снежок остаётся при переключении приложения")
        XCTAssertEqual(window.level.rawValue, NSWindow.Level.statusBar.rawValue + 1)
        XCTAssertTrue(window.contentView!.acceptsFirstMouse(for: nil), "Первый клик сразу начинает перетаскивание")
    }

    func testScreenshotPreferenceChangesSharingType() {
        let window = WinterObjectWindow(object: object(), screenFrame: screen)
        defer { window.close() }
        XCTAssertEqual(window.sharingType, .none)
        window.showsInScreenshots = true
        XCTAssertEqual(window.sharingType, .readOnly, "Разрешённый объект попадает в снимки экрана")
        window.showsInScreenshots = false
        XCTAssertEqual(window.sharingType, .none)
    }

    func testDisplayReusesViewAndResizesSnowman() throws {
        var model = object()
        let window = WinterObjectWindow(object: model, screenFrame: screen)
        defer { window.close() }
        let view = try XCTUnwrap(window.contentView as? WinterObjectView)
        model.center = CGPoint(x: 400, y: 250)
        window.display(object: model, screenFrame: screen)
        XCTAssertTrue(window.contentView === view, "Движение сохраняет представление объекта")
        XCTAssertEqual(window.frame, model.frame.offsetBy(dx: screen.minX, dy: screen.minY))
        model.radii = [28, 21, 14]
        window.display(object: model, screenFrame: screen)
        XCTAssertEqual(window.frame.height, 116, "Окно вмещает три слегка утопленных друг в друга шара")
        XCTAssertEqual(view.object.id, model.id, "Обновление сохраняет идентификатор модели")
        XCTAssertTrue(view.object.isSnowman)
    }

    func testDragCallbacksUseGlobalPointsAndPositiveElapsedTime() throws {
        let window = WinterObjectWindow(object: object(), screenFrame: screen)
        defer { window.close() }
        let view = try XCTUnwrap(window.contentView)
        let location = CGPoint(x: 15, y: 20)
        let expected = window.convertPoint(toScreen: location)
        var began: CGPoint?
        var moved: CGPoint?
        var elapsed: TimeInterval?
        var ended = false
        window.dragBegan = { began = $0 }
        window.dragged = { moved = $0; elapsed = $1 }
        window.dragEnded = { ended = true }
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                timestamp: 7, windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1))
        }
        view.mouseDown(with: try event(.leftMouseDown))
        view.mouseDragged(with: try event(.leftMouseDragged))
        view.mouseUp(with: try event(.leftMouseUp))
        XCTAssertEqual(began, expected, "Начало жеста использует координаты экрана")
        XCTAssertEqual(moved, expected, "Движение использует координаты экрана")
        XCTAssertGreaterThan(try XCTUnwrap(elapsed), 0, "Совпадающие метки времени не дают нулевой интервал")
        XCTAssertTrue(ended, "Отпускание завершает жест")
    }

    func testPlowUsesRequestedFrameAndPassesClicksThrough() {
        let frame = CGRect(x: -900, y: 180, width: 108, height: 58)
        let window = WinterPlowWindow(frame: frame)
        defer { window.close() }
        XCTAssertEqual(window.frame, frame)
        XCTAssertFalse(window.isVisible, "Создание машины не показывает окно")
        XCTAssertTrue(window.ignoresMouseEvents, "Машина пропускает клики на рабочий стол")
        XCTAssertTrue(window.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)
        XCTAssertFalse(window.hidesOnDeactivate)
        let moved = frame.offsetBy(dx: 200, dy: 0)
        window.display(frame: moved)
        XCTAssertEqual(window.frame, moved, "Машина следует кадрам симуляции")
        XCTAssertEqual(window.sharingType, .none)
        window.showsInScreenshots = true
        XCTAssertEqual(window.sharingType, .readOnly)
        window.showsInScreenshots = false
        XCTAssertEqual(window.sharingType, .none)
    }
}
