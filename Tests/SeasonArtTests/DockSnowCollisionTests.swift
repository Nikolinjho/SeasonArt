import AppKit
import XCTest
@testable import SeasonArt

final class DockSnowCollisionTests: XCTestCase {
    private let dt: Float = 1 / 60
    private let away = SIMD2<Float>(-1_000, -1_000)
    private let body = CGRect(x: 100, y: 6, width: 300, height: 60)

    private func dock(radius: CGFloat = 0) -> WindowSurface {
        WindowSurface(id: 42, frame: body, blockers: [], cover: [],
                      cornerRadius: radius, cornerExponent: 2.5, isDock: true)
    }

    private func simulation(radius: CGFloat = 0) -> SnowSimulation {
        let value = SnowSimulation(width: 600, height: 200, snowfall: .off)
        value.thaws = false
        value.updateWindows([dock(radius: radius)], interval: dt)
        return value
    }

    private func layers(_ value: SnowSimulation) -> [SnowLayer] {
        Mirror(reflecting: value).children.first { $0.label == "layers" }!.value as! [SnowLayer]
    }

    private func sprites(_ value: SnowSimulation) -> [Sprite] {
        let buffer = UnsafeMutablePointer<Sprite>.allocate(capacity: max(1, value.spriteCount))
        defer { buffer.deallocate() }
        return Array(UnsafeBufferPointer(start: buffer, count: value.writeSprites(into: buffer, capacity: max(1, value.spriteCount))))
    }

    private func scatter(_ value: SnowSimulation, x: Float, y: Float, dx: Float = 0) {
        value.scatter((0..<100).map { _ in ScatterPiece(position: SIMD2(x, y), velocity: SIMD2(dx, -20), color: SIMD3(repeating: 1)) })
    }

    private func assertNoParticlesInside(_ value: SnowSimulation, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(sprites(value).contains { body.contains(CGPoint(x: CGFloat($0.position.x), y: CGFloat($0.position.y))) },
                       "Частицы не проходят через тело Dock: \(sprites(value).filter { body.contains(CGPoint(x: CGFloat($0.position.x), y: CGFloat($0.position.y))) }.map { "\($0.position) size=\($0.size)" })", file: file, line: line)
    }

    private func assertGroundHiddenByDock(_ value: SnowSimulation, file: StaticString = #filePath, line: UInt = #line) {
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: value.columnCount)
        defer { buffer.deallocate() }
        let piles = value.writeLayers(into: buffer, capacity: value.columnCount)
        for pile in piles where !pile.isDock {
            // Маска повторяет скругление нижних углов, поэтому проверяются точки внутри корпуса.
            for point in [SIMD2<Float>(250, 7), SIMD2<Float>(250, 65), SIMD2<Float>(101, 40), SIMD2<Float>(399, 40)] {
                XCTAssertTrue(pile.occluders.contains { point.x >= $0.x && point.x <= $0.z && point.y >= $0.y && point.y <= $0.w },
                              "Нижний снег скрывается корпусом Dock в \(point)", file: file, line: line)
            }
        }
    }

    func testБоковойВлётНижеПолкиНеПроходитВТелоDock() {
        let value = simulation()
        scatter(value, x: 98, y: 35, dx: 200)
        for _ in 0..<60 {
            _ = value.step(dt: dt, cursor: away)
            assertNoParticlesInside(value)
        }
        assertGroundHiddenByDock(value)
    }

    func testСнегВнутриDockВыходитЧерезБлижайшуюБоковуюГрань() {
        let value = simulation()
        scatter(value, x: 102, y: 35)
        _ = value.step(dt: dt, cursor: away)
        assertNoParticlesInside(value)
        XCTAssertTrue(sprites(value).allSatisfy { $0.position.x < 100 }, "Снег у левой грани выходит вбок, а не переносится на крышу")
        for _ in 0..<120 { _ = value.step(dt: dt, cursor: away) }
        assertGroundHiddenByDock(value)
    }

    func testОбычноеПадениеСверхуСохраняетОседаниеНаПолке() {
        let value = simulation()
        scatter(value, x: 250, y: 130)
        for _ in 0..<240 { _ = value.step(dt: dt, cursor: away) }
        XCTAssertGreaterThan(layers(value).first { $0.isDock }!.heights.reduce(0, +), 0)
        assertGroundHiddenByDock(value)
    }

    func testВлётПодСкруглённымКраемНеВозвращаетСнегВDock() {
        let value = simulation(radius: 25)
        scatter(value, x: 98, y: 42, dx: 140)
        for _ in 0..<120 {
            _ = value.step(dt: dt, cursor: away)
            assertNoParticlesInside(value)
        }
        assertGroundHiddenByDock(value)
    }

    func testСкрытыйDockНеОставляетНевидимуюСтену() {
        let value = simulation()
        value.updateWindows([], interval: dt)
        scatter(value, x: 102, y: 35)
        _ = value.step(dt: dt, cursor: away)
        XCTAssertTrue(sprites(value).contains { body.contains(CGPoint(x: CGFloat($0.position.x), y: CGFloat($0.position.y))) })
    }

    func testМетельНеПроталкиваетХлопьяСквозьDock() {
        for fps in [30, 60, 120] {
            let value = simulation(radius: 25)
            value.blizzard = true
            scatter(value, x: 98, y: 35, dx: 200)
            scatter(value, x: 250, y: 130)
            for _ in 0..<(fps * 5) {
                _ = value.step(dt: 1 / Float(fps), cursor: away)
                assertNoParticlesInside(value)
            }
            assertGroundHiddenByDock(value)
        }
    }

    func testКрупныеНеоседающиеХлопьяНеПроходятЧерезDock() {
        let value = SnowSimulation(width: 600, height: 200, snowfall: .heavy)
        value.thaws = false
        value.updateWindows([dock()], interval: dt)
        var sawNear = false
        for _ in 0..<1_800 {
            _ = value.step(dt: dt, cursor: away)
            sawNear = sawNear || sprites(value).contains { $0.size >= 8 }
            assertNoParticlesInside(value)
        }
        XCTAssertTrue(sawNear, "Проверка охватывает крупные неоседающие хлопья")
    }

    func testПорывВетраНеПроталкиваетСнегСквозьDock() {
        let value = simulation()
        scatter(value, x: 50, y: 35, dx: 100)
        value.blowAway(direction: 1, calm: false)
        for _ in 0..<300 {
            _ = value.step(dt: dt, cursor: away)
            assertNoParticlesInside(value)
        }
    }
    func testОтключённоеНакоплениеНеСоздаётСнегНаDock() {
        let value = simulation()
        value.accumulates = false
        scatter(value, x: 250, y: 130)
        for _ in 0..<300 {
            _ = value.step(dt: dt, cursor: away)
            assertNoParticlesInside(value)
        }
        XCTAssertEqual(layers(value).reduce(Float(0)) { $0 + $1.heights.reduce(0, +) }, 0)
    }

    func testХлопьяБезНакопленияНеЗависаютРазмытойПолосойНаDock() {
        let value = simulation()
        value.accumulates = false
        scatter(value, x: 250, y: 130)
        for _ in 0..<300 { _ = value.step(dt: dt, cursor: away) }
        XCTAssertTrue(sprites(value).isEmpty, "Хлопья заканчивают падение, а не остаются подскакивать над полкой")
    }

    func testПередниеРазмытыеХлопьяИсчезаютПослеОстановкиСнегопада() {
        let value = SnowSimulation(width: 6_000, height: 400, snowfall: .heavy)
        value.thaws = false
        let fullDock = WindowSurface(id: 42, frame: CGRect(x: 0, y: 6, width: 6_000, height: 60),
                                     blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2, isDock: true)
        value.updateWindows([fullDock], interval: dt)
        _ = value.step(dt: dt, cursor: away)
        XCTAssertTrue(sprites(value).contains { $0.size >= 8 }, "Сцена содержит передние мягкие хлопья")
        value.snowfall = .off
        for _ in 0..<900 { _ = value.step(dt: dt, cursor: away) }
        XCTAssertFalse(sprites(value).contains { $0.size >= 8 }, "Мягкие хлопья не образуют постоянную полосу над Dock")
    }

    func testСкрытиеСуществующегоСнегаКорпусомDockСохраняетМассу() {
        let value = simulation()
        let ground = layers(value)[0]
        for i in 65..<85 { ground.set(i, 4) }
        let before = ground.heights.reduce(0, +)
        _ = value.step(dt: dt, cursor: away)
        assertGroundHiddenByDock(value)
        XCTAssertEqual(ground.heights.reduce(0, +), before, accuracy: 0.001,
                       "Снег остаётся на месте без потери массы")
    }

    func testДесятьМинутСнегопадаСНакопленнымСлоемНеСоздаютБоковыхГор() {
        let value = simulation()
        value.cursorInteracts = false
        value.snowfall = .heavy
        let ground = layers(value)[0]
        for i in ground.heights.indices { ground.set(i, 30) }
        ground.refreshTop()
        let seconds = Double(ProcessInfo.processInfo.environment["SEASONART_LONG_SNOW_SECONDS"] ?? "600") ?? 600
        for _ in 0..<Int(seconds * 30) { _ = value.step(dt: 1 / 30, cursor: away) }
        let outside = ground.heights.indices.filter { ground.centerX($0) < 100 || ground.centerX($0) > 400 }
        let outsidePeak = outside.map { ground.heights[$0] }.max() ?? 0
        let peakIndex = ground.heights.indices.max { ground.heights[$0] < ground.heights[$1] }!
        XCTAssertLessThan(outsidePeak, Float(body.maxY) + 20,
                          "Видимый пик \(outsidePeak), полный пик \(ground.heights[peakIndex]) при x=\(ground.centerX(peakIndex))")
        if seconds > 600 { print("Длительность \(seconds) с, боковой максимум \(outsidePeak) pt") }
        assertGroundHiddenByDock(value)
    }

    func testНакопленныйНижнийСнегНеСобираетсяВБоковыеГорыПриПоявленииDock() {
        let value = simulation()
        let ground = layers(value)[0]
        for i in ground.heights.indices { ground.set(i, 40) }
        ground.refreshTop()
        let before = ground.heights
        _ = value.step(dt: dt, cursor: away)
        XCTAssertEqual(ground.heights, before, "Ровный накопленный слой остаётся на месте под Dock")
        XCTAssertLessThanOrEqual(ground.heights.max() ?? 0, 40.1)
    }

    func testДвижениеDockНеПерестраиваетНижнийСугробРывками() {
        let value = simulation()
        let ground = layers(value)[0]
        for i in ground.heights.indices { ground.set(i, 30) }
        ground.refreshTop()
        let before = ground.heights
        for step in 0..<300 {
            let dx = CGFloat(step % 2 == 0 ? -2 : 2)
            value.updateWindows([WindowSurface(id: 42, frame: body.offsetBy(dx: dx, dy: 0),
                blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: true)], interval: dt)
            _ = value.step(dt: dt, cursor: away)
        }
        XCTAssertEqual(ground.heights, before, "Перемещение Dock не должно тасовать уже лежащий снег")
    }

    func testКорпусDockСкрываетНижнийСнегВБуфереОтрисовки() throws {
        let value = simulation()
        let ground = layers(value)[0]
        for i in ground.heights.indices { ground.set(i, 30) }
        ground.refreshTop()
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: value.columnCount)
        defer { buffer.deallocate() }
        let piles = value.writeLayers(into: buffer, capacity: value.columnCount)
        let pile = try XCTUnwrap(piles.first { !$0.isDock })
        XCTAssertTrue(pile.occluders.contains { $0.x <= 100 && $0.z >= 400 && $0.y <= 6 && $0.w >= 66 },
                      "Корпус Dock скрывает лежащий под ним снег без переноса массы")
    }

    func testКороткаяПолкаDockНеОтбрасываетсяКакМаленькоеОкно() {
        let screen = CGRect(x: 0, y: 0, width: 600, height: 400)
        let entry: NSDictionary = [
            kCGWindowNumber: NSNumber(value: 42), kCGWindowOwnerPID: NSNumber(value: Int32(99999)),
            kCGWindowLayer: NSNumber(value: Int(CGWindowLevelForKey(.dockWindow))),
            kCGWindowAlpha: NSNumber(value: 1.0), kCGWindowOwnerName: "Dock",
            kCGWindowBounds: screen.dictionaryRepresentation, kCGWindowIsOnscreen: kCFBooleanTrue!
        ]
        let tracker = WindowTracker(windowListProvider: { [entry] as CFArray },
                                    fullScreenSpaceProvider: { [] },
                                    dockReservedProvider: { CGRect(x: 100, y: 364, width: 300, height: 36) })
        tracker.screen = screen
        tracker.primaryHeight = 400
        tracker.menuBarHeight = 24
        let surfaces = tracker.poll(now: 100, eager: true)?.surfaces ?? []
        XCTAssertEqual(surfaces.count, 1, "Низкий видимый Dock сохраняет тело и опору")
        XCTAssertEqual(surfaces.first?.frame.height, 29)
        XCTAssertEqual(surfaces.first?.isDock, true)
    }

    func testПереполненныйБуферСохраняетСкрытуюМассуНаЗемле() throws {
        let value = SnowSimulation(width: 9_000, height: 400, snowfall: .off)
        value.thaws = false
        let flood = WindowSurface(id: 43, frame: CGRect(x: 0, y: 100, width: 9_000, height: 100),
                                  blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2, isDock: false)
        value.updateWindows([dock(), flood], interval: dt)
        let floodLayer = try XCTUnwrap(layers(value).first { !$0.isDock && $0.origin.y == 200 })
        for i in 0..<floodLayer.count { floodLayer.set(i, 100) }
        value.updateWindows([dock()], interval: dt)
        let grains = Mirror(reflecting: value).children.first { $0.label == "grains" }!.value
        XCTAssertEqual(Mirror(reflecting: grains).children.count, 12_000, "Буфер частиц заполнен до воспроизведения")
        let ground = layers(value)[0]
        for i in 0..<ground.count { ground.set(i, 0) }
        let low = WindowSurface(id: 44, frame: CGRect(x: 200, y: 10, width: 100, height: 20),
                                blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2, isDock: false)
        value.updateWindows([dock(), low], interval: dt)
        let lowLayer = try XCTUnwrap(layers(value).first { !$0.isDock && $0.origin.y == 30 })
        for i in 0..<lowLayer.count { lowLayer.set(i, 4) }
        let expected = lowLayer.heights.reduce(0, +) * lowLayer.columnWidth
        value.updateWindows([dock()], interval: dt)
        assertGroundHiddenByDock(value)
        XCTAssertEqual(ground.heights.reduce(0, +) * ground.columnWidth, expected, accuracy: 0.01,
                       "Масса при полном буфере сохраняется на земле без бокового переноса")
    }

    func testБыстрыйБоковойБросокНеТуннелируетЧерезВесьDock() {
        let value = simulation()
        scatter(value, x: 50, y: 35, dx: 30_000)
        _ = value.step(dt: dt, cursor: away)
        XCTAssertTrue(sprites(value).allSatisfy { $0.position.x < 100 },
                      "Проверяется весь путь частицы, а не только её конечная координата")
    }

    func testЗёрнаСЗакрывшегосяОкнаВытесняютсяИзТелаDock() throws {
        let value = simulation()
        let low = WindowSurface(id: 44, frame: CGRect(x: 101, y: 10, width: 80, height: 25),
                                blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2, isDock: false)
        value.updateWindows([dock(), low], interval: dt)
        let lowLayer = try XCTUnwrap(layers(value).first { !$0.isDock && $0.origin.y == 35 })
        lowLayer.set(0, 4)
        value.updateWindows([dock()], interval: dt)
        let before = Mirror(reflecting: value).children.first { $0.label == "grains" }!.value
        XCTAssertGreaterThan(Mirror(reflecting: before).children.count, 0, "Закрывшееся окно выпускает зёрна снега")
        for _ in 0..<180 {
            _ = value.step(dt: dt, cursor: away)
            assertNoParticlesInside(value)
        }
        assertGroundHiddenByDock(value)
        let area = layers(value).reduce(Float(0)) { $0 + $1.heights.reduce(0, +) * $1.columnWidth }
        XCTAssertEqual(area, 8, accuracy: 0.01, "Зёрна сохраняют массу при вытеснении из Dock")
    }

    func testДождьИЛистьяСохраняютСвоёПрежнееПоведение() {
        for mode in [Mode.rain, .autumn, .blossom] {
            let value = simulation()
            value.mode = mode
            scatter(value, x: 102, y: 35)
            _ = value.step(dt: dt, cursor: away)
            XCTAssertTrue(sprites(value).contains { body.contains(CGPoint(x: CGFloat($0.position.x), y: CGFloat($0.position.y))) },
                          "Столкновения снега не меняют другие режимы")
        }
    }

    func testСкрытиеСнегаDockУКраяЭкранаНеТеряетМассу() {
        let value = simulation()
        let edgeDock = WindowSurface(id: 42, frame: CGRect(x: 0, y: 6, width: 400, height: 60),
                                     blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2, isDock: true)
        value.updateWindows([edgeDock], interval: dt)
        let ground = layers(value)[0]
        ground.set(5, 4)
        _ = value.step(dt: dt, cursor: away)
        XCTAssertEqual(ground.heights.reduce(0, +), 4, accuracy: 0.001,
                       "Скрытая масса остаётся на месте даже у края экрана")
        XCTAssertEqual(ground.heights.dropFirst(200).reduce(0, +), 0,
                       "Снег не перебрасывается к противоположному краю Dock")
    }

    func testDockВоВсюШиринуНеПоднимаетНижнийСнегНаПолку() {
        let value = simulation()
        let full = WindowSurface(id: 42, frame: CGRect(x: 0, y: 6, width: 600, height: 60),
                                 blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2, isDock: true)
        value.updateWindows([full], interval: dt)
        layers(value)[0].set(5, 4)
        _ = value.step(dt: dt, cursor: away)
        XCTAssertEqual(layers(value).reduce(Float(0)) { $0 + $1.heights.reduce(0, +) }, 4, accuracy: 0.001)
        XCTAssertEqual(layers(value)[0].heights.reduce(0, +), 4, accuracy: 0.001)
        XCTAssertEqual(layers(value).first { $0.isDock }!.heights.reduce(0, +), 0)
    }

    func testПустойУголНадСкруглениемНеПоднимаетСнегНаПлоскуюКрышу() {
        let value = simulation(radius: 25)
        value.accumulates = false
        scatter(value, x: 106, y: 63)
        _ = value.step(dt: dt, cursor: away)
        XCTAssertTrue(sprites(value).allSatisfy { $0.position.y < 66 },
                      "Над скошенным краем есть воздух, а не невидимая плоская крыша")
    }

    func testБыстрыйБросокВышеСкошенногоУглаНеПересекаетСерединуDock() {
        let value = simulation(radius: 25)
        scatter(value, x: 50, y: 50, dx: 30_000)
        _ = value.step(dt: dt, cursor: away)
        XCTAssertTrue(sprites(value).allSatisfy { $0.position.x < 100 },
                      "Середина Dock остаётся сплошной при пролёте выше скошенных углов")
    }

}
