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
    func testSculptingLifecycleAndLimit() {
        let controller = controller()
        defer { controller.close() }
        XCTAssertFalse(controller.startSculpting())
        controller.isEnabled = true
        XCTAssertTrue(controller.startSculpting())
        XCTAssertTrue(controller.hasObjects, "Лепка поддерживает опрос опор без снегопада")
        XCTAssertTrue(controller.needsUpdates)
        controller.isSuppressed = true
        XCTAssertFalse(controller.isSculpting, "Системный выбор окна отменяет лепку")
        controller.isSuppressed = false
        for cancel in [ { controller.clear() }, { controller.fit(to: CGRect(x: 0, y: 0, width: 800, height: 600)) },
                        { controller.isActive = false }, { controller.isEnabled = false } ] {
            controller.isEnabled = true
            controller.isActive = true
            XCTAssertTrue(controller.startSculpting())
            cancel()
            XCTAssertFalse(controller.isSculpting)
        }
        controller.isEnabled = true
        for i in 0..<12 { controller.create(.small, at: CGPoint(x: i * 40, y: 100)) }
        XCTAssertFalse(controller.startSculpting(), "Предпросмотр не обходит лимит игрушек")
    }
    private func snowyController() -> (WinterSceneController, SnowSimulation, WindowUpdate) {
        _ = NSApplication.shared
        let simulation = SnowSimulation(width: 600, height: 400, snowfall: .off)
        simulation.thaws = false
        let dock = WindowSurface(id: 42, frame: CGRect(x: 80, y: 0, width: 400, height: 60),
                                 blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: true)
        let update = WindowUpdate(surfaces: [dock], interval: 0.1, parked: [], elsewhere: [], sliding: false, slideVelocity: 0)
        simulation.updateWindows([dock], interval: 1 / 60)
        simulation.scatter((0..<4_000).map { i in
            ScatterPiece(position: SIMD2(100 + Float(i % 180) * 2, 130),
                         velocity: SIMD2(0, -200), color: SIMD3(repeating: 1))
        })
        for _ in 0..<180 { _ = simulation.step(dt: 1 / 60, cursor: SIMD2(-1_000, -1_000)) }
        let controller = WinterSceneController(screenFrame: CGRect(x: -600, y: 100, width: 600, height: 400),
                                               simulation: simulation, presentsWindows: false)
        controller.isEnabled = true
        controller.updateWindows(update)
        return (controller, simulation, update)
    }

    func testSculptingCommitsOneBallAndRejectsStaleCallbacks() throws {
        let (controller, simulation, _) = snowyController()
        defer { controller.close() }
        XCTAssertTrue(controller.startSculpting())
        let panel = try XCTUnwrap(controller.sculptingWindow)
        let oldUp = try XCTUnwrap(panel.ended)
        panel.began?(CGPoint(x: -440, y: 161))
        panel.moved?(CGPoint(x: -300, y: 161))
        XCTAssertTrue(controller.scene.objects.isEmpty, "Предпросмотр не создаёт игрушку")
        let before = try XCTUnwrap(simulation.sculptingSource(at: CGPoint(x: 160, y: 61))).layer.heights
        oldUp(CGPoint(x: -300, y: 161))
        XCTAssertFalse(controller.isSculpting)
        XCTAssertEqual(controller.scene.objects.count, 1)
        XCTAssertEqual(controller.scene.objects.first?.sizes, [.large])
        let after = try XCTUnwrap(simulation.sculptingSource(at: CGPoint(x: 160, y: 61))).layer.heights
        XCTAssertNotEqual(before, after, "Отпускание снимает снег")
        XCTAssertTrue(controller.startSculpting())
        oldUp(CGPoint(x: -300, y: 161))
        XCTAssertEqual(controller.scene.objects.count, 1, "Старое отпускание не создаёт второй шар")
        XCTAssertTrue(controller.isSculpting, "Старый callback не закрывает новый режим")
    }

    func testSculptingProtectsThinSnowFromRegularCursorCarving() throws {
        let (controller, simulation, _) = snowyController()
        defer { controller.close() }
        let layer = try XCTUnwrap(simulation.sculptingSource(at: CGPoint(x: 160, y: 61))).layer
        layer.replace(heights: layer.heights.map { min($0, 0.5) })
        layer.refreshTop()
        XCTAssertTrue(controller.startSculpting())
        _ = simulation.step(dt: 1 / 60, cursor: SIMD2(160, 61))
        XCTAssertNotNil(simulation.sculptingSource(at: CGPoint(x: 160, y: 61)),
                        "Обычная расчистка курсором не уничтожает сугроб перед нажатием в режиме лепки")
        let panel = try XCTUnwrap(controller.sculptingWindow)
        panel.began?(CGPoint(x: -440, y: 161))
        panel.moved?(CGPoint(x: -200, y: 161))
        _ = simulation.step(dt: 1 / 60, cursor: SIMD2(400, 61))
        panel.ended?(CGPoint(x: -200, y: 161))
        XCTAssertEqual(controller.scene.objects.count, 1, "Движение мышью до отпускания не расчищает собранные участки")
        XCTAssertEqual(controller.scene.objects.first?.sizes, [.medium])
        XCTAssertNotNil(simulation.sculptingSource(at: CGPoint(x: 450, y: 61)))
        _ = simulation.step(dt: 1 / 60, cursor: SIMD2(450, 61))
        _ = simulation.step(dt: 1 / 60, cursor: SIMD2(454, 61))
        XCTAssertNil(simulation.sculptingSource(at: CGPoint(x: 454, y: 61)),
                     "После завершения обычная расчистка курсором снова работает")
    }

    func testChangedTrackedSupportCancelsBeforeSimulationReceivesUpdate() throws {
        let (controller, _, _) = snowyController()
        defer { controller.close() }
        controller.startSculpting()
        let panel = try XCTUnwrap(controller.sculptingWindow)
        panel.began?(CGPoint(x: -440, y: 161))
        panel.moved?(CGPoint(x: -300, y: 161))
        let up = try XCTUnwrap(panel.ended)
        controller.updateWindows(WindowUpdate(surfaces: [], interval: 0.1, parked: [], elsewhere: [], sliding: false, slideVelocity: 0))
        XCTAssertFalse(controller.isSculpting, "Исчезновение опоры сразу отменяет жест")
        up(CGPoint(x: -300, y: 161))
        XCTAssertTrue(controller.scene.objects.isEmpty, "Старый снимок симуляции не подтверждает пропавшую опору")
    }

    func testEmptyClickCancellationAndInsufficientSnowLeaveNoBall() throws {
        let (controller, simulation, _) = snowyController()
        defer { controller.close() }
        let source = try XCTUnwrap(simulation.sculptingSource(at: CGPoint(x: 160, y: 61)))
        let before = source.layer.heights
        controller.startSculpting()
        controller.sculptingWindow?.began?(CGPoint(x: -500, y: 400))
        XCTAssertFalse(controller.isSculpting)
        controller.startSculpting()
        let panel = try XCTUnwrap(controller.sculptingWindow)
        panel.began?(CGPoint(x: -440, y: 161))
        panel.ended?(CGPoint(x: -440, y: 161))
        XCTAssertFalse(controller.isSculpting)
        XCTAssertTrue(controller.scene.objects.isEmpty)
        XCTAssertEqual(source.layer.heights, before, "Отмена и короткий жест не меняют сугроб")
    }
}
