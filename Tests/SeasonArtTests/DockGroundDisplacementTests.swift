import AppKit
import XCTest
@testable import SeasonArt

final class DockGroundDisplacementTests: XCTestCase {
    private let body = CGRect(x: 100, y: 6, width: 300, height: 60)
    private let expanded = CGRect(x: 80, y: 6, width: 340, height: 60)
    private let away = SIMD2<Float>(-1_000, -1_000)

    private func scene() throws -> (SnowSimulation, SnowLayer) {
        let value = SnowSimulation(width: 600, height: 200, snowfall: .off)
        value.thaws = false
        value.cursorInteracts = false
        value.dockMagnification = DockMagnificationSettings(enabled: true, normalSize: 48, largeSize: 100)
        value.dockPresentationFrame = body
        value.updateWindows([WindowSurface(id: 42, frame: body, blockers: [], cover: [],
            cornerRadius: 0, cornerExponent: 2, isDock: true)], interval: 1 / 60)
        let ground = try XCTUnwrap(Mirror(reflecting: value).children.first { $0.label == "ground" }?.value as? SnowLayer)
        for i in ground.heights.indices { ground.set(i, 40) }
        ground.refreshTop()
        value.updateDockSnowSurface(dt: 1 / 60, cursor: away)
        return (value, ground)
    }

    private func mass(_ ground: SnowLayer) -> Float {
        ground.heights.reduce(0, +) * ground.columnWidth
    }

    func testРасширениеDockФизическиСдвигаетТолькоЗахваченныйСнегККраям() throws {
        let (value, ground) = try scene()
        let before = mass(ground)
        value.dockPresentationFrame = expanded
        XCTAssertTrue(value.updateDockSnowSurface(dt: 1 / 60, cursor: away))
        XCTAssertLessThan(ground.heights[ground.clampedIndex(at: 90)], 10, "Левая грань убирает снег со своего пути")
        XCTAssertLessThan(ground.heights[ground.clampedIndex(at: 410)], 10, "Правая грань убирает снег со своего пути")
        XCTAssertGreaterThan(ground.heights[ground.clampedIndex(at: 70)], 40, "Слева физически появляется вытесненный снег")
        XCTAssertGreaterThan(ground.heights[ground.clampedIndex(at: 430)], 40, "Справа физически появляется вытесненный снег")
        XCTAssertEqual(ground.heights[ground.clampedIndex(at: 250)], 40, "Старый снег под центром Dock не переносится")
        XCTAssertEqual(mass(ground), before, accuracy: 0.05, "Раздвигание сохраняет массу")
    }

    func testНеподвижныйDockИСжатиеНеПересобираютБоковыеСугробы() throws {
        let (value, ground) = try scene()
        value.dockPresentationFrame = expanded
        value.updateDockSnowSurface(dt: 1 / 60, cursor: away)
        let pushed = ground.heights
        for _ in 0..<300 { value.updateDockSnowSurface(dt: 1 / 60, cursor: away) }
        XCTAssertEqual(ground.heights, pushed, "Неподвижные грани повторно не выталкивают массу")
        value.dockPresentationFrame = body
        value.updateDockSnowSurface(dt: 1 / 60, cursor: away)
        XCTAssertEqual(ground.heights, pushed, "Сжатие оставляет снег в новых местах")
        value.dockPresentationFrame = expanded
        value.updateDockSnowSurface(dt: 1 / 60, cursor: away)
        XCTAssertEqual(ground.heights, pushed, "Повторный проход по очищенной полосе не увеличивает горки")
    }

    func testМедленноеРасширениеСохраняетМассуПриРазнойЧастотеКадров() throws {
        for fps in [30, 60, 120] {
            let (value, ground) = try scene()
            let before = mass(ground)
            for i in 1...fps {
                let shift = CGFloat(i) / CGFloat(fps) * 20
                value.dockPresentationFrame = body.insetBy(dx: -shift, dy: 0)
                value.updateDockSnowSurface(dt: 1 / Float(fps), cursor: away)
            }
            XCTAssertLessThan(ground.heights[ground.clampedIndex(at: 90)], 10)
            XCTAssertEqual(mass(ground), before, accuracy: 0.1, "Масса сохраняется при \(fps) fps")
            XCTAssertLessThan(ground.top, 100, "Небольшое расширение не создаёт огромный пик")
        }
    }

    func testПодDockИСкрытиеНеРаздвигаютНижнийСлой() throws {
        let (value, ground) = try scene()
        let before = ground.heights
        value.dockSnowPosition = .below
        value.dockPresentationFrame = expanded
        value.updateDockSnowSurface(dt: 1 / 60, cursor: away)
        XCTAssertEqual(ground.heights, before)
        value.dockSnowPosition = .above
        value.updateWindows([], interval: 1 / 60)
        value.updateDockSnowSurface(dt: 1 / 60, cursor: away)
        XCTAssertEqual(ground.heights, before, "Старая рамка AX скрытого Dock не сдвигает снег")
    }

    func testПовторныеНаведенияСОседаниемНеСоздаютМассуИОгромныеГоры() throws {
        let (value, ground) = try scene()
        let before = mass(ground)
        for _ in 0..<100 {
            value.dockPresentationFrame = expanded
            for _ in 0..<15 { _ = value.step(dt: 1 / 60, cursor: away) }
            value.dockPresentationFrame = body
            for _ in 0..<15 { _ = value.step(dt: 1 / 60, cursor: away) }
        }
        XCTAssertEqual(mass(ground), before, accuracy: 0.5, "Сто наведений с оседанием сохраняют массу")
        XCTAssertLessThan(ground.top, 120, "Раздвигание узких полос не собирает весь фон в огромные горки")
        print("Сто наведений: максимум \(ground.top) pt, масса \(mass(ground)) pt²")
    }

    func testУКраяЭкранаИПриВозвращенииDockМассаНеТеряется() throws {
        let (value, ground) = try scene()
        let before = mass(ground)
        value.dockPresentationFrame = CGRect(x: -10, y: 6, width: 620, height: 60)
        value.updateDockSnowSurface(dt: 1 / 60, cursor: away)
        XCTAssertEqual(mass(ground), before, accuracy: 0.1, "Если снаружи нет места, снег не исчезает")
        value.updateWindows([], interval: 1 / 60)
        value.updateDockSnowSurface(dt: 1 / 60, cursor: away)
        value.updateWindows([WindowSurface(id: 42, frame: body, blockers: [], cover: [],
            cornerRadius: 0, cornerExponent: 2, isDock: true)], interval: 1 / 60)
        value.dockPresentationFrame = expanded
        let beforeReturn = ground.heights
        value.updateDockSnowSurface(dt: 1 / 60, cursor: away)
        XCTAssertEqual(ground.heights, beforeReturn, "Появление Dock не выталкивает сразу весь скрытый снег")
    }
}
