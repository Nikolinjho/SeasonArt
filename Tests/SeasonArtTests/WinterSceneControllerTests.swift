import AppKit
import XCTest
@testable import SeasonArt

final class WinterSceneControllerTests: XCTestCase {
    func testТракторНеТеряетПроходКогдаDockУходитНаДругойSpace() throws {
        let (controller, _, update) = snowyController()
        defer { controller.close() }
        XCTAssertTrue(controller.startPlow())
        let before = try XCTUnwrap(controller.plow).bladeX
        controller.updateWindows(WindowUpdate(surfaces: [], interval: 0.1, parked: [],
            elsewhere: [42], sliding: true, slideVelocity: 0))
        XCTAssertNotNil(controller.plow, "Переход на другой Space приостанавливает проход")
        RunLoop.current.run(until: Date().addingTimeInterval(0.06))
        XCTAssertEqual(controller.plow?.bladeX, before, "Скрытый проход не продвигается")
        controller.updateWindows(update)
        XCTAssertNotNil(controller.plow, "При возвращении Dock продолжается прежний проход")
        controller.updateWindows(WindowUpdate(surfaces: [], interval: 0.1, parked: [],
            elsewhere: [], sliding: false, slideVelocity: 0))
        XCTAssertNil(controller.plow, "Настоящее исчезновение полки отменяет проход")
    }

    func testСистемныйВыборОкнаЗапрещаетНовыйПроходТрактора() {
        let (controller, _, _) = snowyController()
        defer { controller.close() }
        XCTAssertTrue(controller.canPlow)
        controller.isSuppressed = true
        XCTAssertFalse(controller.canPlow)
        XCTAssertFalse(controller.startPlow())
        XCTAssertNil(controller.plow)
        controller.isSuppressed = false
        XCTAssertTrue(controller.startPlow())
        controller.isSuppressed = true
        XCTAssertNotNil(controller.plow, "Существующий проход приостанавливается без удаления")
        XCTAssertFalse(controller.isRunning)
        controller.isSuppressed = false
        XCTAssertTrue(controller.isRunning)
    }

    private func controller() -> WinterSceneController {
        _ = NSApplication.shared
        return WinterSceneController(screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
                                     simulation: SnowSimulation(width: 800, height: 600, snowfall: .off),
                                     presentsWindows: false)
    }
    func testПадениеПроминаетСнегИОбновляетВысотуОпоры() throws {
        let (controller, simulation, _) = snowyController()
        defer { controller.close() }
        let layer = try XCTUnwrap(simulation.sculptingSource(at: CGPoint(x: 240, y: 61))).layer
        layer.replace(heights: layer.heights.map { _ in 20 })
        layer.refreshTop()
        let before = layer.heights
        _ = controller.create(.large, at: CGPoint(x: 240, y: 300))
        for _ in 0..<120 { controller.scene.step(dt: 1 / 60) }
        XCTAssertLessThan(layer.heights[80], before[80], "Удар проминает центр сугроба")
        let ball = controller.scene.objects[0]
        let under = stride(from: ball.center.x - 28, through: ball.center.x + 28, by: 2).compactMap {
            simulation.winterSurfaceY(at: $0, on: 42)
        }
        XCTAssertGreaterThanOrEqual(ball.visibleBottom, max(60, try XCTUnwrap(under.min()) - 28 * SnowballWorld.footSink) - 0.6,
                                    "Шар лежит в примятом снегу не глубже утопления")
        XCTAssertLessThanOrEqual(ball.visibleBottom, try XCTUnwrap(under.max()) + 0.6, "Шар не висит над снегом")
        let settled = layer.heights
        for _ in 0..<120 { controller.scene.step(dt: 1 / 60) }
        XCTAssertEqual(layer.heights, settled, "Покой не повторяет удар")
    }

    func testModeLimitAndClearManageAllOwnedWindows() {
        let controller = controller()
        defer { controller.close() }
        XCTAssertFalse(controller.canCreate, "До включения снежного режима игрушки не создаются")
        controller.isEnabled = true
        for i in 0..<WinterScene.maximumObjects { XCTAssertNotNil(controller.create(.small, at: CGPoint(x: 50 + i * 50, y: 100))) }
        XCTAssertFalse(controller.canCreate, "Предохранительный лимит учитывает все окна")
        XCTAssertEqual(controller.objectWindowCount, WinterScene.maximumObjects)
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

    func testПослеДвенадцатиИгрушекЛепкаПродолжаетСоздаватьСнежки() {
        let (controller, simulation, _) = snowyController()
        defer { controller.close() }
        for i in 0..<12 { XCTAssertNotNil(controller.create(.small, at: CGPoint(x: i * 35, y: 200))) }
        frame(controller, simulation, x: 160)
        move(controller, simulation, from: 160, to: 260)
        frame(controller, simulation, x: 260, dt: 0.36)
        XCTAssertEqual(controller.scene.objects.count, 13, "Лепка не останавливается после двенадцатой игрушки")
    }

    private func move(_ controller: WinterSceneController, _ simulation: SnowSimulation,
                      from start: CGFloat, to end: CGFloat, y: CGFloat = 61, frames: Int = 20) {
        for i in 1...frames {
            frame(controller, simulation, x: start + (end - start) * CGFloat(i) / CGFloat(frames), y: y, dt: 0.025)
        }
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

    func testПервоеКасаниеИРезкийПроходНеПоказываютШар() {
        let (controller, simulation, _) = snowyController()
        defer { controller.close() }
        frame(controller, simulation, x: 160)
        frame(controller, simulation, x: 160.25)
        XCTAssertNil(controller.sculptingPreview, "До движения длительностью 0.25 секунды снежок скрыт")
        frame(controller, simulation, x: 400)
        XCTAssertTrue(controller.scene.objects.isEmpty, "Прыжок курсора не создаёт максимальный шар")
        XCTAssertNil(controller.sculptingPreview)
    }

    private func snowArea(_ simulation: SnowSimulation) -> Float {
        let fields = Mirror(reflecting: simulation).children
        let layers = fields.first { $0.label == "layers" }!.value as! [SnowLayer]
        let grains = fields.first { $0.label == "grains" }!.value
        let airborne = Mirror(reflecting: grains).children.reduce(Float(0)) { sum, grain in
            sum + (Mirror(reflecting: grain.value).children.first { $0.label == "area" }!.value as! Float)
        }
        return layers.reduce(airborne) { $0 + $1.heights.reduce(0, +) * $1.columnWidth }
    }

    func testДвижениеСначалаПоказываетМаленькийШарИПаузаСохраняетРазмер() throws {
        let (controller, simulation, _) = snowyController()
        defer { controller.close() }
        let before = snowArea(simulation)
        frame(controller, simulation, x: 160)
        for i in 1...5 { frame(controller, simulation, x: 160 + CGFloat(i) * 25, dt: 0.05) }
        let preview = try XCTUnwrap(controller.sculptingPreview)
        XCTAssertEqual(preview.frame.width, 16, accuracy: 0.001, "Первый видимый радиус равен шести")
        XCTAssertTrue(controller.scene.objects.isEmpty)
        controller.updateAutomaticSculpting(at: CGPoint(x: 285 - 600, y: 61 + 100), dt: 0.36, mouseButtons: 0)
        XCTAssertEqual(try XCTUnwrap(controller.scene.objects.first).radii[0], 6, accuracy: 0.001)
        let removed = before - snowArea(simulation)
        XCTAssertEqual(removed, 40, accuracy: 0.01, "Масса слоя и пыли уменьшается только на массу видимого шара")
    }

    func testКороткийПроходПослеПаузыПозволяетПовторитьБезВыхода() {
        let (controller, simulation, _) = snowyController()
        defer { controller.close() }
        frame(controller, simulation, x: 160)
        frame(controller, simulation, x: 180)
        frame(controller, simulation, x: 180, dt: 0.36)
        XCTAssertTrue(controller.scene.objects.isEmpty)
        move(controller, simulation, from: 180, to: 280)
        XCTAssertNotNil(controller.sculptingPreview)
        frame(controller, simulation, x: 280, dt: 0.36)
        XCTAssertEqual(controller.scene.objects.count, 1)
    }

    func testРадиусЗависитОтВремениДвиженияПриРазнойЧастотеКадров() throws {
        for fps in [24, 30, 60, 120] {
            let (controller, simulation, _) = snowyController()
            defer { controller.close() }
            frame(controller, simulation, x: 160)
            for i in 1...fps {
                frame(controller, simulation, x: 160 + 140 * CGFloat(i) / CGFloat(fps), dt: 1 / Double(fps))
            }
            XCTAssertNotNil(controller.sculptingPreview)
            frame(controller, simulation, x: 300, dt: 0.36)
            XCTAssertEqual(try XCTUnwrap(controller.scene.objects.first).radii[0], 21, accuracy: 0.001, "Частота \(fps)")
        }
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
        move(controller, simulation, from: 160, to: 400)
        XCTAssertTrue(controller.isSculpting)
        XCTAssertEqual(try XCTUnwrap(simulation.sculptingSource(at: CGPoint(x: 300, y: 61))).heights[100], 0.5, accuracy: 0.001, "Предпросмотр не снимает снег")
        let radius: CGFloat = 11
        frame(controller, simulation, x: 400, dt: 0.36)
        XCTAssertEqual(controller.scene.objects.first?.radii[0] ?? 0, radius, accuracy: 0.001)
        XCTAssertNotEqual(layer.heights, before)
    }

    func testПаузаПодтверждаетРазмерИБлокируетНовыйШарДоВыхода() {
        for distance: CGFloat in [24, 60, 83] {
            let (controller, simulation, _) = snowyController()
            defer { controller.close() }
            frame(controller, simulation, x: 160)
            move(controller, simulation, from: 160, to: 160 + distance)
            let radius = min(11, SnowSculptingGesture.radius(for: (floor(distance / 2) + 1) * 4)!)
            frame(controller, simulation, x: 160 + distance, dt: 0.34)
            XCTAssertTrue(controller.scene.objects.isEmpty)
            frame(controller, simulation, x: 160 + distance, dt: 0.02)
            XCTAssertEqual(controller.scene.objects.first?.radii[0] ?? 0, radius, accuracy: 0.001)
            frame(controller, simulation, x: 320)
            frame(controller, simulation, x: 400, dt: 0.4)
            XCTAssertEqual(controller.scene.objects.count, 1)
            frame(controller, simulation, x: 400, y: 250)
            frame(controller, simulation, x: 320)
            move(controller, simulation, from: 320, to: 400)
            frame(controller, simulation, x: 400, dt: 0.36)
            XCTAssertEqual(controller.scene.objects.count, 2, "Выход разрешает новый проход")
        }
    }

    func testМаксимумСоздаетОдинБольшойШарБезПовторногоНасыщения() {
        let (controller, simulation, _) = snowyController()
        defer { controller.close() }
        frame(controller, simulation, x: 160)
        move(controller, simulation, from: 160, to: 300, frames: 70)
        XCTAssertEqual(controller.scene.objects.first?.radii[0] ?? 0, 36, accuracy: 0.001)
        for x in [160, 400, 200, 450] { frame(controller, simulation, x: CGFloat(x)) }
        XCTAssertEqual(controller.scene.objects.count, 1)
    }

    func testВыходПодтверждаетАПовторныеКолонкиНеУвеличиваютЗапас() {
        let (controller, simulation, _) = snowyController()
        defer { controller.close() }
        frame(controller, simulation, x: 160)
        for i in 0..<72 { frame(controller, simulation, x: i.isMultiple(of: 2) ? 184 : 160, dt: 0.025) }
        frame(controller, simulation, x: 184, y: 250)
        XCTAssertEqual(controller.scene.objects.first?.radii[0] ?? 0, SnowSculptingGesture.radius(for: 52)!, accuracy: 0.001)
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

    func testИзменениеДругогоОкнаНеПрерываетЛепкуНаDock() {
        let (controller, simulation, initial) = snowyController()
        defer { controller.close() }
        frame(controller, simulation, x: 160)
        for i in 1...30 {
            let other = WindowSurface(id: 77, frame: CGRect(x: 500, y: 200 + i, width: 80, height: 100),
                                      blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2, isDock: false)
            let surfaces = initial.surfaces + [other]
            controller.updateWindows(WindowUpdate(surfaces: surfaces, interval: 1 / 60, parked: [], elsewhere: [], sliding: false, slideVelocity: 0))
            simulation.updateWindows(surfaces, interval: 1 / 60)
            frame(controller, simulation, x: 160 + CGFloat(i) * 4)
        }
        frame(controller, simulation, x: 280, dt: 0.36)
        XCTAssertEqual(controller.scene.objects.count, 1, "Обновления постороннего окна не сбрасывают время лепки")
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

    func testСдвигИПерекрытиеТекущейОпорыОтменяютЛепку() {
        for moved in [true, false] {
            let (controller, simulation, initial) = snowyController()
            defer { controller.close() }
            frame(controller, simulation, x: 160)
            frame(controller, simulation, x: 220)
            XCTAssertTrue(controller.isSculpting)
            let dock = initial.surfaces[0]
            let changed = moved ? dock.shifted(by: 20) : WindowSurface(
                id: dock.id, frame: dock.frame, blockers: [CGRect(x: 150, y: 40, width: 150, height: 100)],
                cover: [], cornerRadius: dock.cornerRadius, cornerExponent: dock.cornerExponent, isDock: true)
            controller.updateWindows(WindowUpdate(surfaces: [changed], interval: 0.1, parked: [], elsewhere: [], sliding: false, slideVelocity: 0))
            XCTAssertFalse(controller.isSculpting)
            XCTAssertTrue(controller.scene.objects.isEmpty)
        }
    }

    func testКликПослеПаузыИМаксимумаНеСнимаетБлокировкуДоВыхода() {
        for maximum in [false, true] {
            let (controller, simulation, _) = snowyController()
            defer { controller.close() }
            frame(controller, simulation, x: 160)
            move(controller, simulation, from: 160, to: maximum ? 300 : 220, frames: maximum ? 70 : 20)
            if !maximum { frame(controller, simulation, x: 220, dt: 0.36) }
            XCTAssertEqual(controller.scene.objects.count, 1)
            frame(controller, simulation, x: 320, buttons: 1)
            frame(controller, simulation, x: 340)
            frame(controller, simulation, x: 420)
            frame(controller, simulation, x: 420, dt: 0.36)
            XCTAssertFalse(controller.isSculpting)
            XCTAssertEqual(controller.scene.objects.count, 1, "Нажатие и отпускание не заменяют выход со снега")
            frame(controller, simulation, x: 420, y: 250)
            frame(controller, simulation, x: 340)
            move(controller, simulation, from: 340, to: 420)
            frame(controller, simulation, x: 420, dt: 0.36)
            XCTAssertEqual(controller.scene.objects.count, 2, "Выход разрешает следующий проход")
        }
    }

    func testТонкийДоступныйСнегПоддерживаетКадрыБезСнегопада() throws {
        _ = NSApplication.shared
        let simulation = SnowSimulation(width: 600, height: 400, snowfall: .off)
        simulation.thaws = false
        simulation.scatter((0..<2_000).map { i in
            ScatterPiece(position: SIMD2(100 + Float(i % 180) * 2, 100),
                         velocity: SIMD2(0, -200), color: SIMD3(repeating: 1))
        })
        for _ in 0..<180 { _ = simulation.step(dt: 1 / 60, cursor: SIMD2(-1_000, -1_000)) }
        let layer = try XCTUnwrap(simulation.sculptingSource(at: CGPoint(x: 160, y: 1))).layer
        let controller = WinterSceneController(screenFrame: CGRect(x: 0, y: 0, width: 600, height: 400),
                                               simulation: simulation, presentsWindows: false)
        defer { controller.close() }
        controller.isEnabled = true
        for height: Float in [0.2, 0.5] {
            layer.replace(heights: layer.heights.map { _ in height })
            layer.refreshTop()
            XCTAssertFalse(simulation.hasSnow, "Общий порог остальных режимов остаётся прежним")
            XCTAssertNotNil(simulation.sculptingSource(at: CGPoint(x: 160, y: 0.1)))
            XCTAssertTrue(controller.needsUpdates, "Любой доступный снег продолжает замечать указатель: \(height)")
        }
        layer.replace(heights: layer.heights.map { _ in 0 })
        layer.refreshTop()
        XCTAssertFalse(controller.needsUpdates, "Пустой слой не поддерживает постоянный опрос")
    }

    func testПереходНаДругуюОпоруЗавершаетПервыйПроходИНовыйТребуетДвижения() {
        _ = NSApplication.shared
        let simulation = SnowSimulation(width: 600, height: 400, snowfall: .off)
        simulation.thaws = false
        let supports = [
            WindowSurface(id: 51, frame: CGRect(x: 80, y: 0, width: 200, height: 60),
                          blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: true),
            WindowSurface(id: 52, frame: CGRect(x: 320, y: 0, width: 220, height: 120),
                          blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: true)
        ]
        simulation.updateWindows(supports, interval: 1 / 60)
        simulation.scatter((0..<4_000).map { i in
            ScatterPiece(position: SIMD2(100 + Float(i % 200) * 2, 180),
                         velocity: SIMD2(0, -200), color: SIMD3(repeating: 1))
        })
        for _ in 0..<180 { _ = simulation.step(dt: 1 / 60, cursor: SIMD2(-1_000, -1_000)) }
        let controller = WinterSceneController(screenFrame: CGRect(x: -600, y: 100, width: 600, height: 400),
                                               simulation: simulation, presentsWindows: false)
        defer { controller.close() }
        controller.isEnabled = true
        controller.updateWindows(WindowUpdate(surfaces: supports, interval: 0.1, parked: [], elsewhere: [], sliding: false, slideVelocity: 0))
        frame(controller, simulation, x: 160)
        move(controller, simulation, from: 160, to: 220)
        XCTAssertTrue(controller.isSculpting)
        frame(controller, simulation, x: 360, y: 121)
        XCTAssertEqual(controller.scene.objects.count, 1)
        XCTAssertFalse(controller.isSculpting, "Переход не начинает второй проход тем же кадром")
        frame(controller, simulation, x: 360, y: 121, dt: 0.4)
        XCTAssertFalse(controller.isSculpting, "Неподвижный указатель на другой опоре не начинает проход")
        move(controller, simulation, from: 360, to: 420, y: 121)
        XCTAssertTrue(controller.isSculpting)
        frame(controller, simulation, x: 420, y: 250)
        XCTAssertEqual(controller.scene.objects.count, 2)
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
        let layer = try XCTUnwrap(simulation.sculptingSource(at: CGPoint(x: 160, y: 61))).layer
        let before = layer.heights
        for i in 0..<WinterScene.maximumObjects { controller.create(.small, at: CGPoint(x: i * 40, y: 150)) }
        for i in 0...20 {
            controller.updateAutomaticSculpting(at: CGPoint(x: 160 + CGFloat(i) * 7 - 600, y: 161),
                                                dt: 0.025, mouseButtons: 0)
        }
        controller.updateAutomaticSculpting(at: CGPoint(x: -300, y: 161), dt: 0.36, mouseButtons: 0)
        XCTAssertFalse(controller.isSculpting)
        XCTAssertEqual(controller.scene.objects.count, WinterScene.maximumObjects)
        XCTAssertEqual(layer.heights, before, "При полном лимите лепка не снимает снег")
    }
    func testПеретаскиваниеБезАппаратнойКнопкиОтменяетАвтолёпку() throws {
        let (controller, simulation, _) = snowyController()
        defer { controller.close() }
        let id = try XCTUnwrap(controller.create(.small, at: CGPoint(x: 100, y: 150)))
        frame(controller, simulation, x: 160)
        frame(controller, simulation, x: 220)
        XCTAssertTrue(controller.isSculpting)
        controller.scene.beginDragging(id, at: CGPoint(x: 100, y: 150))
        frame(controller, simulation, x: 240, buttons: 0)
        XCTAssertFalse(controller.isSculpting)
        frame(controller, simulation, x: 300, buttons: 0)
        XCTAssertFalse(controller.isSculpting)
        XCTAssertEqual(controller.scene.objects.count, 1)
    }

    func testСкрытиеКонтроллераОтменяетПеретаскиваниеБезОкна() throws {
        let (controller, _, _) = snowyController()
        defer { controller.close() }
        let id = try XCTUnwrap(controller.create(.small, at: CGPoint(x: 100, y: 150)))
        controller.scene.beginDragging(id, at: CGPoint(x: 100, y: 150))
        controller.scene.drag(id, to: CGPoint(x: 130, y: 150), dt: 0.1)
        controller.isSuppressed = true
        XCTAssertFalse(controller.scene.objects[0].isDragged)
        XCTAssertEqual(controller.scene.objects[0].velocity, .zero)
    }

}
