import AppKit
import XCTest
@testable import SeasonArt

final class WinterSceneControllerTests: XCTestCase {
    private func controller() -> WinterSceneController {
        _ = NSApplication.shared
        return WinterSceneController(screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
                                     simulation: SnowSimulation(width: 800, height: 600, snowfall: .off),
                                     presentsWindows: false)
    }
    func testModeLimitAndClearManageAllOwnedWindows() {
        let controller = controller()
        defer { controller.close() }
        XCTAssertFalse(controller.canCreate, "До включения снежного режима игрушки не создаются")
        controller.isEnabled = true
        for i in 0..<12 { XCTAssertNotNil(controller.create(.small, at: CGPoint(x: 50 + i * 50, y: 100))) }
        XCTAssertFalse(controller.canCreate, "Лимит двенадцать учитывает все окна")
        XCTAssertEqual(controller.objectWindowCount, 12)
        controller.clear()
        XCTAssertEqual(controller.objectWindowCount, 0, "Очистка закрывает собственные панели")
        XCTAssertFalse(controller.isRunning, "Пустая сцена не держит таймер")
    }
    func testPauseAndModeSuspendTimerWithoutDroppingObjects() {
        let controller = controller()
        defer { controller.close() }
        controller.isEnabled = true
        _ = controller.create(.large, at: CGPoint(x: 200, y: 100))
        XCTAssertTrue(controller.isRunning)
        controller.isActive = false
        XCTAssertFalse(controller.isRunning, "Пауза останавливает моделирование")
        XCTAssertEqual(controller.scene.objects.count, 1)
        controller.isActive = true
        XCTAssertTrue(controller.isRunning)
        controller.isSuppressed = true
        XCTAssertFalse(controller.isRunning, "Системный выбор окна скрывает интерактивные панели")
        controller.isSuppressed = false
        controller.isEnabled = false
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(controller.scene.objects.count, 1, "Смена режима сохраняет спрятанную игрушку")
    }
    func testPlowRequiresActualShelfAndRejectsSecondPass() {
        let controller = controller()
        defer { controller.close() }
        controller.isEnabled = true
        XCTAssertFalse(controller.canPlow)
        let dock = WindowSurface(id: 77, frame: CGRect(x: 100, y: 0, width: 500, height: 60),
                                 blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: true)
        controller.updateWindows(WindowUpdate(surfaces: [dock], interval: 0.1, parked: [], elsewhere: [], sliding: false, slideVelocity: 0))
        XCTAssertTrue(controller.canPlow)
        XCTAssertTrue(controller.startPlow())
        XCTAssertFalse(controller.startPlow(), "Повторная команда не создаёт вторую машину")
        controller.clear()
        XCTAssertNil(controller.plow)
    }
    func testCloseReleasesTimerAndPreventsNewObjects() {
        let controller = controller()
        controller.isEnabled = true
        _ = controller.create(.small, at: CGPoint(x: 100, y: 100))
        controller.close()
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(controller.objectWindowCount, 0)
        XCTAssertFalse(controller.canCreate)
    }
}
