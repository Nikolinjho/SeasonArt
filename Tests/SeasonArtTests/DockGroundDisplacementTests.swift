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

    func testГраньСдвигаетСнегПологимВаломБезТреугольника() throws {
        let (value, ground) = try scene()
        let before = mass(ground)
        // Увеличение идёт за несколько кадров, как при настоящем наведении.
        for step in 1...10 {
            let grow = CGFloat(step) * 2
            value.dockPresentationFrame = body.insetBy(dx: -grow, dy: 0)
            value.updateDockSnowSurface(dt: 1 / 60, cursor: away)
        }
        func surface(_ x: Float) -> Float { ground.heights[ground.clampedIndex(at: x)] }
        var steepest: Float = 0
        // Колонки под корпусом скрыты: склон меряется до последней видимой колонки у грани.
        for x in stride(from: Float(4), to: 76, by: ground.columnWidth) {
            steepest = max(steepest, abs(surface(x + ground.columnWidth) - surface(x)) / ground.columnWidth)
        }
        XCTAssertLessThan(steepest, 0.45, "Сдвинутый снег образует пологий вал, а не клин под углом откоса")
        XCTAssertGreaterThan(surface(78), 40, "Вал начинается у самой грани")
        XCTAssertGreaterThan(surface(40), 40, "Сдвинутый снег уходит вбок, а не копится у грани")
        XCTAssertEqual(mass(ground), before, accuracy: 0.05)
    }

    func testСлепленныйВалНеРассыпаетсяПослеСжатияDock() throws {
        let (value, ground) = try scene()
        let before = mass(ground)
        for step in 1...10 {
            value.dockPresentationFrame = body.insetBy(dx: -CGFloat(step) * 2, dy: 0)
            value.updateDockSnowSurface(dt: 1 / 60, cursor: away)
        }
        let shaped = ground.heights
        value.dockPresentationFrame = body
        for _ in 0..<600 { _ = value.step(dt: 1 / 60, cursor: away) }
        // Срез у бывшей грани может стать крутым округлым краем, сам вал держит форму.
        let berm = ground.heights.indices.filter { ground.centerX($0) < 50 || ground.centerX($0) > 450 }
        let worst = berm.map { abs(shaped[$0] - ground.heights[$0]) }.max() ?? 0
        XCTAssertLessThan(worst, 0.01, "Клейкий снег держит форму, которую ему придал Dock")
        var steepest: Float = 0
        for i in ground.heights.indices.dropLast() where ground.centerX(i) < 98 {
            steepest = max(steepest, abs(ground.heights[i + 1] - ground.heights[i]) / ground.columnWidth)
        }
        XCTAssertLessThan(steepest, 2.2, "Срез у борозды крутой, но не отвесный")
        XCTAssertEqual(mass(ground), before, accuracy: 0.05)
    }

    func testБыстроеРасширениеНеОставляетСтолбиковВБорозде() throws {
        let (value, ground) = try scene()
        // Крупные шаги, не кратные ширине колонки, как при быстром жесте.
        for grow: CGFloat in [7, 19, 33] {
            value.dockPresentationFrame = body.insetBy(dx: -grow, dy: 0)
            value.updateDockSnowSurface(dt: 1 / 60, cursor: away)
        }
        for i in ground.heights.indices where ground.centerX(i) >= 67 && ground.centerX(i) < 100 {
            XCTAssertLessThanOrEqual(ground.heights[i], 6.01, "Колонка x=\(ground.centerX(i)) осталась в полосе грани")
        }
    }

    func testПропущенныйСнимокDockНеСоздаётВторойВал() throws {
        let (value, ground) = try scene()
        let before = mass(ground)
        value.dockPresentationFrame = body.insetBy(dx: -10, dy: 0)
        value.updateDockSnowSurface(dt: 1 / 60, cursor: away)
        value.dockPresentationFrame = nil
        value.updateDockSnowSurface(dt: 1 / 60, cursor: away)
        value.dockPresentationFrame = body.insetBy(dx: -20, dy: 0)
        value.updateDockSnowSurface(dt: 1 / 60, cursor: away)
        for i in ground.heights.indices where ground.centerX(i) >= 81 && ground.centerX(i) < 100 {
            XCTAssertLessThanOrEqual(ground.heights[i], 6.01, "После пропуска грань продолжает расчищать полосу")
        }
        var peaks = 0
        for i in ground.heights.indices.dropFirst().dropLast() where ground.centerX(i) < 80 {
            if ground.heights[i] > ground.heights[i - 1] + 0.01 && ground.heights[i] > ground.heights[i + 1] + 0.01 { peaks += 1 }
        }
        XCTAssertEqual(peaks, 1, "Слева один пологий вал: единственный гребень у грани")
        XCTAssertEqual(mass(ground), before, accuracy: 0.05)
    }

    func testОтодвинутыйСнегНеСтекаетОбратноПодDock() throws {
        let (value, ground) = try scene()
        value.dockPresentationFrame = expanded
        value.updateDockSnowSurface(dt: 1 / 60, cursor: away)
        let cleared = ground.heights[ground.clampedIndex(at: 90)]
        let bank = ground.heights[ground.clampedIndex(at: 70)]
        for _ in 0..<600 { _ = value.step(dt: 1 / 60, cursor: away) }
        XCTAssertEqual(ground.heights[ground.clampedIndex(at: 90)], cleared, accuracy: 0.5,
                       "Под расширенным Dock снег из боковой горки не появляется")
        XCTAssertGreaterThan(ground.heights[ground.clampedIndex(at: 70)], bank * 0.8, "Горка у грани не утекает под корпус")
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
