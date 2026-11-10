import AppKit
import XCTest
@testable import SeasonArt

final class DockSnowSurfaceTests: XCTestCase {
    private let frame = CGRect(x: 100, y: 6, width: 500, height: 60)
    private let settings = DockMagnificationSettings(enabled: true, normalSize: 47, largeSize: 88)

    private func icon(side: CGFloat = 88) -> DockSnowIcon {
        DockSnowIcon(frame: CGRect(x: 300, y: 10, width: side, height: side), roof: (0..<64).map {
            let edge = abs(Float($0) / 63 * 2 - 1)
            return edge > 0.96 ? 0 : 0.94 - 0.18 * pow(edge, 8)
        })
    }

    func testЛепкаНаУвеличеннойИконкеИспользуетВидимыйСнегИСоздаётШарНадНим() throws {
        let simulation = SnowSimulation(width: 800, height: 400, snowfall: .off)
        simulation.thaws = false
        simulation.cursorInteracts = false
        simulation.dockMagnification = settings
        simulation.dockIconFrames = [icon()]
        simulation.dockPresentationFrame = CGRect(x: 80, y: 6, width: 540, height: 60)
        simulation.updateWindows([WindowSurface(id: 42, frame: frame, blockers: [], cover: [],
            cornerRadius: 0, cornerExponent: 2, isDock: true)], interval: 1 / 60)
        let layers = Mirror(reflecting: simulation).children.first { $0.label == "layers" }!.value as! [SnowLayer]
        let dock = try XCTUnwrap(layers.first { $0.isDock })
        for i in 1..<(dock.count - 1) { dock.set(i, 7) }
        dock.refreshTop()
        _ = simulation.step(dt: 1 / 60, cursor: SIMD2(340, 40))
        let y = try XCTUnwrap(simulation.winterSurfaceY(at: 320, on: 42)) - 1
        let start = CGPoint(x: 320, y: y)
        let source = try XCTUnwrap(simulation.sculptingSource(at: start), "Лепка попадает в видимую горку над большой иконкой")
        XCTAssertNil(source.column(at: CGPoint(x: 320, y: 68)), "В старом месте под поднятым снегом лепка не начинается")
        var gesture = SnowSculptingGesture(source: source, at: start)
        for x in stride(from: CGFloat(322), through: 360, by: 2) {
            let top = try XCTUnwrap(simulation.winterSurfaceY(at: x, on: 42))
            gesture.include(CGPoint(x: x, y: top - 1))
        }
        XCTAssertNotNil(gesture.radius)
        XCTAssertGreaterThan(gesture.center.y - (gesture.radius ?? 0), 90, "Черновик находится над поднятой поверхностью")
        XCTAssertEqual(gesture.collectedArea, min(220, CGFloat(gesture.columns.count) * 4), accuracy: 0.001,
            "Растяжение Dock не увеличивает собранную физическую массу")
        let collected = gesture.collectedArea
        let oldHeight = gesture.center.y
        simulation.dockIconFrames = [icon(side: 110)]
        _ = simulation.step(dt: 1 / 60, cursor: SIMD2(360, 40))
        gesture.updateSource(simulation.sculptingSource(for: dock))
        XCTAssertEqual(gesture.collectedArea, collected, "Обновление контура не собирает колонки повторно")
        XCTAssertGreaterThan(gesture.center.y, oldHeight + 10, "Черновик следует за ростом иконки во время лепки")
        let ball = try XCTUnwrap(simulation.commitSculpting(gesture))
        let contact = try XCTUnwrap(simulation.winterDockContact(on: 42, at: ball.center.x, radius: ball.radius))
        XCTAssertGreaterThanOrEqual(ball.center.y - ball.radius, contact.top - 0.1,
            "Готовый шар сразу создаётся снаружи горки")
    }

    func testРасширеннаяГоркаПодхватываетСнежокРядомСОбычнымDock() throws {
        _ = NSApplication.shared
        let simulation = SnowSimulation(width: 800, height: 400, snowfall: .off)
        simulation.thaws = false
        simulation.cursorInteracts = false
        let surface = WindowSurface(id: 42, frame: frame, blockers: [], cover: [],
            cornerRadius: 0, cornerExponent: 2, isDock: true)
        simulation.updateWindows([surface], interval: 1 / 60)
        let layers = Mirror(reflecting: simulation).children.first { $0.label == "layers" }!.value as! [SnowLayer]
        let dock = try XCTUnwrap(layers.first { $0.isDock })
        for i in 1..<(dock.count - 1) { dock.set(i, 7) }
        dock.refreshTop()
        let controller = WinterSceneController(screenFrame: CGRect(x: 0, y: 0, width: 800, height: 400),
            simulation: simulation, presentsWindows: false)
        defer { controller.close() }
        controller.isEnabled = true
        controller.updateWindows(WindowUpdate(surfaces: [surface], interval: 1 / 60,
            parked: [], elsewhere: [], sliding: false, slideVelocity: 0))
        XCTAssertNotNil(controller.scene.create(.small, at: CGPoint(x: 70, y: 30)))
        for _ in 0..<180 { controller.scene.step(dt: 1 / 60) }
        XCTAssertNil(controller.scene.objects[0].support)
        simulation.dockMagnification = settings
        simulation.dockPresentationFrame = CGRect(x: 40, y: 6, width: 560, height: 60)
        simulation.dockIconFrames = [DockSnowIcon(frame: CGRect(x: 40, y: 10, width: 88, height: 88),
            roof: [Float](repeating: 0.94, count: 64))]
        _ = simulation.step(dt: 1 / 60, cursor: SIMD2(70, 40))
        controller.updateDockContacts()
        XCTAssertEqual(controller.scene.objects[0].support, 42, "Расширение Dock подхватывает шар рядом с его прежними границами")
        XCTAssertGreaterThan(controller.scene.objects[0].frame.minY, 80)
        controller.scene.removeAll()
        XCTAssertNotNil(controller.scene.create(.small, at: CGPoint(x: 70, y: 30)))
        XCTAssertEqual(controller.scene.objects[0].support, 42, "При создании опора учитывается до первого кадра")
        XCTAssertGreaterThan(controller.scene.objects[0].frame.minY, 80)
    }

    func testСнежокПоднимаетсяСГоркойDockИОпускаетсяПослеНаведения() throws {
        _ = NSApplication.shared
        let simulation = SnowSimulation(width: 800, height: 400, snowfall: .off)
        simulation.thaws = false
        simulation.cursorInteracts = false
        let surface = WindowSurface(id: 42, frame: frame, blockers: [], cover: [],
            cornerRadius: 0, cornerExponent: 2, isDock: true)
        simulation.updateWindows([surface], interval: 1 / 60)
        let layers = Mirror(reflecting: simulation).children.first { $0.label == "layers" }!.value as! [SnowLayer]
        let dock = try XCTUnwrap(layers.first { $0.isDock })
        for i in 1..<(dock.count - 1) { dock.set(i, 7) }
        _ = simulation.step(dt: 1 / 60, cursor: SIMD2(-1000, -1000))
        let controller = WinterSceneController(screenFrame: CGRect(x: 0, y: 0, width: 800, height: 400),
            simulation: simulation, presentsWindows: false)
        defer { controller.close() }
        controller.isEnabled = true
        controller.updateWindows(WindowUpdate(surfaces: [surface], interval: 1 / 60,
            parked: [], elsewhere: [], sliding: false, slideVelocity: 0))
        XCTAssertNotNil(controller.scene.create(.small, at: CGPoint(x: 350, y: 150)))
        for _ in 0..<180 { controller.scene.step(dt: 1 / 60) }
        XCTAssertEqual(controller.scene.objects[0].support, 42)
        let before = controller.scene.objects[0].frame.minY
        simulation.dockMagnification = settings
        simulation.dockIconFrames = [icon()]
        _ = simulation.step(dt: 1 / 60, cursor: SIMD2(350, 40))
        controller.updateDockContacts()
        let raised = controller.scene.objects[0].frame.minY
        XCTAssertGreaterThan(raised, before + 20, "Лежащий шар поднимается вместе с увеличенной иконкой")
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: simulation.columnCount)
        defer { buffer.deallocate() }
        let pile = try XCTUnwrap(simulation.writeLayers(into: buffer, capacity: simulation.columnCount).first { $0.isDock })
        let i = Int((350 - pile.origin.x) / pile.columnWidth)
        let visible = CGFloat(pile.origin.y + buffer[pile.offset + i])
        XCTAssertEqual(try XCTUnwrap(simulation.winterSurfaceY(at: 350, on: 42)), visible, accuracy: 0.1,
            "Физика и отрисовка используют один контур")
        XCTAssertGreaterThanOrEqual(raised, visible - 7 * SnowballWorld.footSink - 0.6,
                                    "Шар утоплен в видимую горку не глубже 15% радиуса")
        controller.scene.removeAll()
        XCTAssertNotNil(controller.scene.create(.small, at: CGPoint(x: 310, y: 250)))
        for _ in 0..<180 { controller.scene.step(dt: 1 / 60) }
        let landed = controller.scene.objects[0]
        XCTAssertEqual(landed.support, 42, "Падающий шар приземляется на горку")
        for j in 0..<pile.count {
            let left = CGFloat(pile.origin.x + Float(j) * pile.columnWidth)
            let sample = min(max(landed.center.x, left), left + CGFloat(pile.columnWidth))
            let distance = abs(sample - landed.center.x)
            let radius = landed.radii[0]
            guard distance <= radius else { continue }
            // Утопление одинаково по всему касанию: в снег не уходит круг радиуса 0,85 r.
            let foot = radius * (1 - SnowballWorld.footSink)
            guard distance <= foot else { continue }
            let footBottom = landed.center.y - sqrt(max(0, foot * foot - distance * distance))
            // Удар может примять снег, поэтому читаем текущую поверхность.
            let contact = try XCTUnwrap(simulation.winterSurfaceY(at: sample, on: 42))
            // Валик, выбитый ударом, растёт в мёртвой зоне 2 pt и не толкает лежащий шар.
            XCTAssertGreaterThanOrEqual(footBottom, contact - WinterChainProfile.deadband - 0.1,
                                        "Край шара не прорезает склон горки глубже утопления и мёртвой зоны")
        }
        controller.scene.removeAll()
        XCTAssertNotNil(controller.scene.create(.small, at: CGPoint(x: 350, y: 200)))
        for _ in 0..<180 { controller.scene.step(dt: 1 / 60) }
        simulation.dockIconFrames = nil
        _ = simulation.step(dt: 1 / 60, cursor: SIMD2(-1000, -1000))
        for _ in 0..<120 { controller.scene.step(dt: 1 / 60) }
        let ball = controller.scene.objects[0]
        let under = stride(from: ball.center.x - 12, through: ball.center.x + 12, by: 2).compactMap {
            simulation.winterSurfaceY(at: $0, on: 42)
        }
        XCTAssertGreaterThanOrEqual(ball.visibleBottom, winterRestingBottom(snow: try XCTUnwrap(under.min()), bed: frame.maxY, radius: 14) - 0.6)
        XCTAssertLessThanOrEqual(ball.visibleBottom, winterRestingBottom(snow: try XCTUnwrap(under.max()), bed: frame.maxY, radius: 14) + 0.6,
                                 "После уменьшения иконки шар возвращается на обычную опору")
        XCTAssertLessThan(controller.scene.objects[0].frame.minY, raised - 20)
    }

    func testРаскладкаБерётТекущийСдвигDockВместоУстаревшихКоординатИконок() {
        let list = CGRect(x: 328, y: 1046, width: 206, height: 61)
        let stale = [CGRect(x: 384, y: 1051, width: 49, height: 61),
                     CGRect(x: 433, y: 1051, width: 49, height: 61),
                     CGRect(x: 482, y: 1022, width: 78, height: 90),
                     CGRect(x: 560, y: 1051, width: 24, height: 61)]
        let actual = DockIconGeometry.laidOutFrames(in: list, items: stale)
        XCTAssertEqual(actual.map(\.minX), [331, 380, 429, 507])
        XCTAssertEqual(actual.map(\.size), stale.map(\.size))
        XCTAssertEqual(actual.map(\.minY), stale.map(\.minY))
    }

    func testШапкаНеВырезаетОсновнойСугробИСледуетРасширениюDock() throws {
        let simulation = SnowSimulation(width: 800, height: 400, snowfall: .off)
        simulation.thaws = false
        simulation.cursorInteracts = false
        simulation.dockMagnification = settings
        simulation.dockIconFrames = [icon()]
        simulation.dockPresentationFrame = CGRect(x: 80, y: 6, width: 540, height: 60)
        simulation.updateWindows([WindowSurface(id: 42, frame: frame, blockers: [], cover: [],
            cornerRadius: 0, cornerExponent: 2, isDock: true)], interval: 1 / 60)
        let layers = Mirror(reflecting: simulation).children.first { $0.label == "layers" }!.value as! [SnowLayer]
        let dock = try XCTUnwrap(layers.first { $0.isDock })
        for i in 95..<155 { dock.set(i, 5) }
        for _ in 0..<60 { _ = simulation.step(dt: 1 / 60, cursor: SIMD2(350, 40)) }
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: simulation.columnCount)
        defer { buffer.deallocate() }
        let piles = simulation.writeLayers(into: buffer, capacity: simulation.columnCount).filter { $0.isDock }
        XCTAssertEqual(piles.count, 1, "Dock рисуется одним цельным сугробом")
        let base = try XCTUnwrap(piles.first)
        XCTAssertEqual(base.origin.x, 80)
        XCTAssertEqual(base.columnWidth * Float(base.count), 540, accuracy: 0.001)
        XCTAssertTrue(base.occluders.isEmpty, "В цельном сугробе нет прямоугольных вырезов под иконки")
        let i = 125
        XCTAssertGreaterThan(buffer[base.offset + i] - buffer[base.offset + base.count + i], 0)
        XCTAssertEqual(dock.base.x, 100, "Физическая опора не растягивается вместе с представлением")
    }

    func testБезНастоящихГраницНеРисуетсяВолнаНадУказателем() {
        var cap = DockSnowSurface()
        for _ in 0..<60 {
            cap.step(dt: 1 / 60, frame: frame, columns: 250, columnWidth: 2,
                     cursor: SIMD2(350, 40), settings: settings, icons: nil)
        }
        XCTAssertEqual(cap.maximum, 0, "Без геометрии иконки нельзя подменять шапку волной")
    }

    func testДвижениеУказателяПоDockЗапрашиваетИнтерактивнуюЧастоту() throws {
        let simulation = SnowSimulation(width: 800, height: 400, snowfall: .off)
        simulation.thaws = false
        simulation.cursorInteracts = false
        simulation.dockMagnification = settings
        simulation.dockIconFrames = [icon()]
        simulation.updateWindows([WindowSurface(id: 42, frame: frame, blockers: [], cover: [],
            cornerRadius: 0, cornerExponent: 2, isDock: true)], interval: 1 / 120)
        let layers = Mirror(reflecting: simulation).children.first { $0.label == "layers" }!.value as! [SnowLayer]
        let dock = try XCTUnwrap(layers.first { $0.isDock })
        for i in 95..<155 { dock.set(i, 5) }
        for i in 0..<20 {
            _ = simulation.step(dt: 1 / 120, cursor: SIMD2(320 + Float(i), 40))
        }
        XCTAssertEqual(simulation.pace, .interactive, "Наведение использует частоту дисплея, а не ограничение lively в 60 FPS")
        for _ in 0..<120 { _ = simulation.step(dt: 1 / 120, cursor: SIMD2(339, 40)) }
        XCTAssertEqual(simulation.pace, .calm, "Неподвижная шапка не удерживает максимальную частоту")
    }

    func testТолщинаЦельногоСугробаЗависитОтНакопленногоСнегаАНеОтИнтенсивности() throws {
        func render(_ depth: Float, intensity: Snowfall = .off) throws -> Float {
            let simulation = SnowSimulation(width: 800, height: 400, snowfall: intensity)
            simulation.thaws = false
            simulation.cursorInteracts = false
            simulation.dockMagnification = settings
            simulation.dockIconFrames = [icon()]
            simulation.updateWindows([WindowSurface(id: 42, frame: frame, blockers: [], cover: [],
                cornerRadius: 0, cornerExponent: 2, isDock: true)], interval: 1 / 60)
            let layers = Mirror(reflecting: simulation).children.first { $0.label == "layers" }!.value as! [SnowLayer]
            let dock = try XCTUnwrap(layers.first { $0.isDock })
            for i in 0..<dock.count { dock.set(i, depth) }
            _ = simulation.step(dt: 1 / 60, cursor: SIMD2(350, 40))
            let physical = dock.heights
            let buffer = UnsafeMutablePointer<Float>.allocate(capacity: simulation.columnCount)
            defer { buffer.deallocate() }
            let piles = simulation.writeLayers(into: buffer, capacity: simulation.columnCount).filter { $0.isDock }
            XCTAssertEqual(dock.heights, physical, "Представление не меняет физический запас")
            if depth == 0 {
                XCTAssertTrue(piles.isEmpty, "Без накопленного снега нет искусственной шапки")
                return 0
            }
            XCTAssertEqual(piles.count, 1)
            let pile = try XCTUnwrap(piles.first)
            for i in 10..<(pile.count - 10) {
                XCTAssertGreaterThan(buffer[pile.offset + i] - buffer[pile.offset + pile.count + i], 0,
                                     "В заполненном снегом слое нет разрывов")
            }
            return buffer[pile.offset + 125] - buffer[pile.offset + pile.count + 125]
        }
        XCTAssertEqual(try render(0), 0)
        let dust = try render(0.5)
        let compact = try render(7)
        let fluffy = try render(11)
        XCTAssertLessThan(dust, 1.5, "Тонкий настоящий снег не заменяется фиксированной толстой шапкой")
        XCTAssertGreaterThan(compact, dust + 4)
        XCTAssertGreaterThan(fluffy, compact + 3)
        XCTAssertEqual(try render(7, intensity: .light), try render(7, intensity: .heavy), accuracy: 0.001)
    }

    func testШапкаЛежитНаКонтуреИконкиИДалекоОтНеёНетВолны() throws {
        var cap = DockSnowSurface()
        let icon = icon()
        cap.step(dt: 1 / 60, frame: frame, columns: 250, columnWidth: 2,
                 cursor: SIMD2(350, 40), settings: settings, icons: [icon])
        let roof = try XCTUnwrap(icon.top(at: 351))
        XCTAssertEqual(Float(frame.maxY) + cap.offsets[125], roof - 0.8, accuracy: 0.001,
                       "Основание слегка перекрывает видимый край, воздушного зазора нет")
        XCTAssertEqual(cap.offsets[80], 0, "За пределами иконки не изгибается снежная полоса")
        XCTAssertEqual(cap.offsets[160], 0)
        XCTAssertGreaterThan(cap.maximum, 20)
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: 500)
        defer { buffer.deallocate() }
        for i in 0..<250 { buffer[i] = 7; buffer[250 + i] = 0 }
        XCTAssertNotNil(cap.apply(to: buffer, columnWidth: 2, originX: 100))
        let depths = (110..<135).map { buffer[$0] - buffer[250 + $0] }
        XCTAssertGreaterThan((depths.max() ?? 0) - (depths.min() ?? 0), 0.15, "Верхний край имеет мелкие неровности")
    }

    func testШапкаНеОтстаётОтУменьшающейсяИконкиПриЛюбойЧастотеКадров() throws {
        for fps in [30, 60, 120] {
            var cap = DockSnowSurface()
            cap.step(dt: 1 / Float(fps), frame: frame, columns: 250, columnWidth: 2,
                     cursor: SIMD2(350, 40), settings: settings, icons: [icon()])
            let smaller = icon(side: 65)
            cap.step(dt: 1 / Float(fps), frame: frame, columns: 250, columnWidth: 2,
                     cursor: SIMD2(350, 40), settings: settings, icons: [smaller])
            let roof = try XCTUnwrap(smaller.top(at: 331))
            XCTAssertEqual(Float(frame.maxY) + cap.offsets[115], roof - 0.8, accuracy: 0.001,
                           "На уменьшении шапка не зависает выше иконки")
            cap.step(dt: 1 / Float(fps), frame: frame, columns: 250, columnWidth: 2,
                     cursor: SIMD2(-1_000, -1_000), settings: settings, icons: [])
            XCTAssertEqual(cap.maximum, 0)
        }
    }

    func testСкрытыйDockИВыключенноеУвеличениеНеСоздаютШапку() {
        var cap = DockSnowSurface()
        cap.step(dt: 1 / 60, frame: frame, columns: 250, columnWidth: 2, cursor: SIMD2(350, 40),
                 settings: .disabled, icons: [icon()])
        XCTAssertEqual(cap.maximum, 0)
        cap.step(dt: 1 / 60, frame: nil, columns: 0, columnWidth: 2, cursor: SIMD2(350, 40), settings: settings, icons: [icon()])
        XCTAssertTrue(cap.offsets.isEmpty)
    }

    func testБуферПрилегаетКИконкеБезИзмененияФизическойМассы() throws {
        let simulation = SnowSimulation(width: 800, height: 400, snowfall: .off)
        simulation.thaws = false
        simulation.cursorInteracts = false
        simulation.dockMagnification = settings
        simulation.dockIconFrames = [icon()]
        simulation.updateWindows([WindowSurface(id: 42, frame: frame, blockers: [], cover: [],
            cornerRadius: 0, cornerExponent: 2, isDock: true)], interval: 1 / 60)
        let layers = Mirror(reflecting: simulation).children.first { $0.label == "layers" }!.value as! [SnowLayer]
        let dock = try XCTUnwrap(layers.first { $0.isDock })
        for i in 95..<155 { dock.set(i, 5) }
        let mass = dock.heights.reduce(0, +)
        for _ in 0..<60 { _ = simulation.step(dt: 1 / 60, cursor: SIMD2(350, 40)) }
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: simulation.columnCount)
        defer { buffer.deallocate() }
        let piles = simulation.writeLayers(into: buffer, capacity: simulation.columnCount)
        let pile = try XCTUnwrap(piles.last { $0.isDock })
        let i = 125
        let bottom = buffer[pile.offset + pile.count + i]
        let top = buffer[pile.offset + i]
        XCTAssertEqual(bottom + pile.origin.y, try XCTUnwrap(icon().top(at: 351)) - 0.8, accuracy: 0.001)
        XCTAssertGreaterThan(top - bottom, 3)
        XCTAssertLessThan(top - bottom, 6)
        XCTAssertGreaterThan(pile.top, dock.top + 20)
        XCTAssertEqual(dock.heights.reduce(0, +), mass, accuracy: 0.01)
        XCTAssertEqual(dock.floor(i), 66)
    }

    func testВерхнийКонтурИзображенияНеВключаетПрозрачныеПоля() throws {
        let image = NSImage(size: NSSize(width: 128, height: 128))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 16, y: 48, width: 96, height: 64), xRadius: 20, yRadius: 20).fill()
        image.unlockFocus()
        let roof = try XCTUnwrap(DockIconGeometry.roofProfile(of: image))
        XCTAssertEqual(roof.first, 0)
        XCTAssertEqual(roof.last, 0)
        XCTAssertEqual(roof[32], 0.875, accuracy: 0.02, "Верх шапки привязан к изображению, а не к краю его рамки")
        XCTAssertLessThan(roof[10], roof[32], "Контур учитывает скруглённый угол")
    }
}
