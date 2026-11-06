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

    private func frame(_ controller: WinterSceneController, _ simulation: SnowSimulation,
                       x: CGFloat, y: CGFloat = 61, dt: TimeInterval = 1 / 60, buttons: Int = 0) {
        controller.updateAutomaticSculpting(at: CGPoint(x: x - 600, y: y + 100), dt: dt, mouseButtons: buttons)
        _ = simulation.step(dt: Float(dt), cursor: SIMD2(Float(x), Float(y)))
    }

    func testЛежащийСнегПоддерживаетКадрыАДругойРежимСохраняетРасчистку() {
        let (controller, simulation, _) = snowyController()
        defer { controller.close() }
        XCTAssertTrue(controller.needsUpdates, "Снег без снегопада продолжает замечать указатель")
        controller.isEnabled = false
        simulation.mode = .autumn
        frame(controller, simulation, x: 160)
        frame(controller, simulation, x: 300)
        XCTAssertTrue(simulation.cursorInteracts)
        XCTAssertFalse(controller.isSculpting)
        XCTAssertFalse(controller.needsUpdates)
        let empty = self.controller()
        defer { empty.close() }
        empty.isEnabled = true
        XCTAssertFalse(empty.needsUpdates, "Пустая сцена не требует постоянного опроса")
    }

    func testМедленноеДвижениеНачинаетЛепкуАКороткийПроходНеСоздаётШар() {
        let (controller, simulation, _) = snowyController()
        defer { controller.close() }
        frame(controller, simulation, x: 160)
        frame(controller, simulation, x: 160.25)
        XCTAssertTrue(controller.isSculpting, "Для движения не требуется минимальная скорость")
        frame(controller, simulation, x: 160.25, y: 250)
        XCTAssertTrue(controller.scene.objects.isEmpty, "Одной колонки недостаточно для шара")
    }

    func testНеподвижныйУказательНеНачинаетЛепкуИТонкийСнегСохраняется() throws {
        let (controller, simulation, _) = snowyController()
        defer { controller.close() }
        let layer = try XCTUnwrap(simulation.sculptingSource(at: CGPoint(x: 160, y: 61))).layer
        layer.replace(heights: layer.heights.map { min($0, 0.5) })
        layer.refreshTop()
        let before = layer.heights
        for _ in 0..<30 { frame(controller, simulation, x: 160) }
        XCTAssertFalse(controller.isSculpting)
        XCTAssertTrue(controller.scene.objects.isEmpty)
        XCTAssertEqual(try XCTUnwrap(simulation.sculptingSource(at: CGPoint(x: 160, y: 61))).heights[40], 0.5, accuracy: 0.001, "Курсор не уничтожает тонкий сугроб перед началом прохода")
        frame(controller, simulation, x: 400)
        XCTAssertTrue(controller.isSculpting)
        XCTAssertEqual(try XCTUnwrap(simulation.sculptingSource(at: CGPoint(x: 300, y: 61))).heights[100], 0.5, accuracy: 0.001, "Предпросмотр не снимает снег")
        frame(controller, simulation, x: 400, dt: 0.36)
        XCTAssertEqual(controller.scene.objects.first?.sizes, [.medium])
        XCTAssertNotEqual(layer.heights, before)
    }

    func testПаузаПодтверждаетРазмерИБлокируетНовыйШарДоВыхода() {
        for (distance, size) in [(CGFloat(24), WinterBallSize.small), (CGFloat(60), .medium)] {
            let (controller, simulation, _) = snowyController()
            defer { controller.close() }
            frame(controller, simulation, x: 160)
            frame(controller, simulation, x: 160 + distance)
            frame(controller, simulation, x: 160 + distance, dt: 0.34)
            XCTAssertTrue(controller.scene.objects.isEmpty)
            frame(controller, simulation, x: 160 + distance, dt: 0.02)
            XCTAssertEqual(controller.scene.objects.first?.sizes, [size])
            frame(controller, simulation, x: 320)
            frame(controller, simulation, x: 400, dt: 0.4)
            XCTAssertEqual(controller.scene.objects.count, 1)
            frame(controller, simulation, x: 400, y: 250)
            frame(controller, simulation, x: 320)
            frame(controller, simulation, x: 400)
            frame(controller, simulation, x: 400, dt: 0.36)
            XCTAssertEqual(controller.scene.objects.count, 2, "Выход разрешает новый проход")
        }
    }

    func testМаксимумСоздаетОдинБольшойШарБезПовторногоНасыщения() {
        let (controller, simulation, _) = snowyController()
        defer { controller.close() }
        frame(controller, simulation, x: 160)
        frame(controller, simulation, x: 300)
        XCTAssertEqual(controller.scene.objects.first?.sizes, [.large])
        for x in [160, 400, 200, 450] { frame(controller, simulation, x: CGFloat(x)) }
        XCTAssertEqual(controller.scene.objects.count, 1)
    }

    func testВыходПодтверждаетАПовторныеКолонкиНеУвеличиваютЗапас() {
        let (controller, simulation, _) = snowyController()
        defer { controller.close() }
        frame(controller, simulation, x: 160)
        for x in [184, 160, 184, 160, 184] { frame(controller, simulation, x: CGFloat(x)) }
        frame(controller, simulation, x: 184, y: 250)
        XCTAssertEqual(controller.scene.objects.first?.sizes, [.small])
    }

    func testКнопкиОтменяютЧерновикИСохраняютПеретаскиваниеИгрушек() throws {
        let (controller, simulation, _) = snowyController()
        defer { controller.close() }
        let layer = try XCTUnwrap(simulation.sculptingSource(at: CGPoint(x: 160, y: 61))).layer
        frame(controller, simulation, x: 160)
        frame(controller, simulation, x: 220)
        let before = layer.heights
        controller.updateAutomaticSculpting(at: CGPoint(x: -380, y: 161), dt: 0.4, mouseButtons: 1)
        XCTAssertFalse(controller.isSculpting)
        XCTAssertTrue(controller.scene.objects.isEmpty)
        XCTAssertEqual(layer.heights, before)
        XCTAssertTrue(simulation.cursorInteracts)
        let id = try XCTUnwrap(controller.create(.small, at: CGPoint(x: 100, y: 150)))
        controller.scene.beginDragging(id, at: CGPoint(x: 100, y: 150))
        controller.scene.drag(id, to: CGPoint(x: 140, y: 180), dt: 0.1)
        XCTAssertEqual(controller.scene.objects.first?.center, CGPoint(x: 140, y: 180))
    }

    func testИзменениеОпорыОтменяетЧерновикБезСнятияСнега() throws {
        let (controller, simulation, _) = snowyController()
        defer { controller.close() }
        let layer = try XCTUnwrap(simulation.sculptingSource(at: CGPoint(x: 160, y: 61))).layer
        frame(controller, simulation, x: 160)
        frame(controller, simulation, x: 220)
        let before = layer.heights
        controller.updateWindows(WindowUpdate(surfaces: [], interval: 0.1, parked: [], elsewhere: [], sliding: false, slideVelocity: 0))
        XCTAssertFalse(controller.isSculpting)
        XCTAssertTrue(controller.scene.objects.isEmpty)
        XCTAssertEqual(layer.heights, before)
    }

    func testЖизненныйЦиклОтменяетЧерновикИЛимитНеОбходится() throws {
        for reason in ["clear", "fit", "pause", "mode", "suppression", "close"] {
            let (controller, simulation, _) = snowyController()
            defer { controller.close() }
            let layer = try XCTUnwrap(simulation.sculptingSource(at: CGPoint(x: 160, y: 61))).layer
            frame(controller, simulation, x: 160)
            frame(controller, simulation, x: 220)
            let before = layer.heights
            switch reason {
            case "clear": controller.clear()
            case "fit": controller.fit(to: CGRect(x: -600, y: 100, width: 600, height: 400))
            case "pause": controller.isActive = false
            case "mode": controller.isEnabled = false
            case "suppression": controller.isSuppressed = true
            default: controller.close()
            }
            XCTAssertFalse(controller.isSculpting, reason)
            XCTAssertTrue(controller.scene.objects.isEmpty, reason)
            XCTAssertEqual(layer.heights, before, reason)
        }
        let (controller, simulation, _) = snowyController()
        defer { controller.close() }
        for i in 0..<12 { controller.create(.small, at: CGPoint(x: i * 40, y: 150)) }
        frame(controller, simulation, x: 160)
        frame(controller, simulation, x: 300)
        XCTAssertFalse(controller.isSculpting)
        XCTAssertEqual(controller.scene.objects.count, 12)
    }
}
