import CoreGraphics
import XCTest
@testable import SeasonArt

final class SnowInteractionTests: XCTestCase {
    private let away = SIMD2<Float>(-1_000, -1_000)
    private let dt: Float = 1 / 60

    private struct RenderedPile {
        let layer: PileLayer
        let heights: [Float]

        var area: Float { heights.reduce(0, +) * 2 }

        func height(at x: Float) -> Float {
            heights[Int((x - layer.origin.x) / 2)]
        }
    }

    private func window(width: CGFloat = 240) -> WindowSurface {
        WindowSurface(id: 42, frame: CGRect(x: 80, y: 80, width: width, height: 120),
                      blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: false)
    }

    private func piles(_ simulation: SnowSimulation) -> [RenderedPile] {
        let capacity = max(1, simulation.columnCount)
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        return simulation.writeLayers(into: buffer, capacity: capacity).map { layer in
            let heights = (0..<layer.count).map { i in
                buffer[layer.offset + i] - buffer[layer.offset + layer.count + i]
            }
            return RenderedPile(layer: layer, heights: heights)
        }
    }

    private func sprites(_ simulation: SnowSimulation) -> [Sprite] {
        let capacity = max(1, simulation.spriteCount)
        let buffer = UnsafeMutablePointer<Sprite>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        let count = simulation.writeSprites(into: buffer, capacity: capacity)
        return Array(UnsafeBufferPointer(start: buffer, count: count))
    }

    private func advance(_ simulation: SnowSimulation, frames: Int) {
        for _ in 0..<frames { _ = simulation.step(dt: dt, cursor: away) }
    }

    private func accumulatedWindow() throws -> (SnowSimulation, RenderedPile) {
        let simulation = SnowSimulation(width: 400, height: 400, snowfall: .off)
        simulation.updateWindows([window()], interval: dt)
        // Плотная полоса даёт заметный сугроб при любом случайном размере хлопьев.
        let pieces = (0..<6_000).map { i in
            ScatterPiece(position: SIMD2(104 + Float(i % 96) * 2, 250),
                         velocity: SIMD2(0, -200), color: SIMD3(repeating: 1))
        }
        simulation.scatter(pieces)
        advance(simulation, frames: 180)
        let pile = try XCTUnwrap(piles(simulation).first { $0.layer.origin.y == 200 },
                                 "Снег должен осесть на верхней грани окна")
        XCTAssertGreaterThan(pile.height(at: 200), 8, "Для проверки взаимодействия нужен заметный сугроб")
        XCTAssertTrue(sprites(simulation).isEmpty, "Перед взаимодействием исходные хлопья должны осесть")
        return (simulation, pile)
    }

    func testScatteredSnowAccumulatesOnWindowInsteadOfPassingThrough() throws {
        let (simulation, pile) = try accumulatedWindow()

        XCTAssertEqual(pile.layer.origin, SIMD2(80, 200), "Сугроб лежит на верхней грани окна в координатах экрана")
        XCTAssertEqual(pile.layer.count, 120, "Ширина сугроба соответствует опоре с шагом два пункта")
        XCTAssertGreaterThan(pile.area, 1_000, "Осевшие хлопья образуют слой снега")
        XCTAssertFalse(piles(simulation).contains { $0.layer.origin.y == 0 },
                       "Снег над окном не должен проходить сквозь него на землю")
    }

    func testCursorCarvesAtOffsetHeightWithinTenPointRadius() throws {
        let (simulation, before) = try accumulatedWindow()
        let surface = before.height(at: 200)
        // Центр кисти совпадает с поверхностью после смещения курсора на (4, -8).
        _ = simulation.step(dt: dt, cursor: SIMD2(196, 200 + surface + 8))
        let after = try XCTUnwrap(piles(simulation).first { $0.layer.origin.y == 200 })

        XCTAssertLessThan(after.height(at: 200), surface - 4,
                          "Курсор вырезает снег на видимой поверхности с учётом смещения вниз на восемь пунктов")
        for x: Float in [189, 211] {
            XCTAssertGreaterThanOrEqual(after.height(at: x), before.height(at: x) - 0.25,
                                        "За радиусом десять пунктов снег не вырезается")
        }
        XCTAssertEqual(after.height(at: 160), before.height(at: 160), accuracy: 0.25,
                       "Удалённый участок сугроба сохраняется")
        XCTAssertEqual(simulation.pace, .interactive, "Реальное перемещение снега включает интерактивную частоту")
    }

    func testFastCursorSweepCarvesThePathAndThrowsSnowIntoAir() throws {
        let (simulation, before) = try accumulatedWindow()
        _ = simulation.step(dt: dt, cursor: SIMD2(126, 213))
        _ = simulation.step(dt: dt, cursor: SIMD2(266, 213))
        let after = try XCTUnwrap(piles(simulation).first { $0.layer.origin.y == 200 })

        XCTAssertLessThan(after.height(at: 200), before.height(at: 200) * 0.5,
                          "Быстрое движение очищает середину пройденного пути между кадрами")
        XCTAssertFalse(sprites(simulation).isEmpty, "Вырезанный быстрым движением снег разлетается частицами")
        XCTAssertTrue(after.heights.allSatisfy { $0.isFinite && $0 >= 0 },
                      "Вырезание не создаёт отрицательных или бесконечных высот")
    }

    func testCursorPassingAbovePileDoesNotCarveSnow() throws {
        let (simulation, before) = try accumulatedWindow()
        let cursorY = 200 + before.layer.top + 8 + 11
        _ = simulation.step(dt: dt, cursor: SIMD2(126, cursorY))
        _ = simulation.step(dt: dt, cursor: SIMD2(266, cursorY))
        let after = try XCTUnwrap(piles(simulation).first { $0.layer.origin.y == 200 })

        XCTAssertEqual(after.area, before.area, accuracy: 1,
                       "Кисть выше сугроба сохраняет снег с учётом обычного осыпания краёв")
        XCTAssertEqual(after.height(at: 200), before.height(at: 200), accuracy: 0.25,
                       "Движение выше радиуса кисти не оставляет борозду")
        XCTAssertTrue(sprites(simulation).isEmpty, "Проход над снегом не выбрасывает частицы")
    }

    func testShrinkingWindowShedsUnsupportedSnowAndKeepsSupportedPart() throws {
        let (simulation, before) = try accumulatedWindow()
        simulation.updateWindows([window(width: 120)], interval: dt)
        let after = try XCTUnwrap(piles(simulation).first { $0.layer.origin.y == 200 })

        XCTAssertEqual(after.layer.count, 60, "При сужении опора заканчивается на новой правой границе")
        XCTAssertGreaterThan(after.area, 0, "Снег на оставшейся части окна сохраняется")
        XCTAssertLessThan(after.area, before.area * 0.75, "Снег за удалённой частью опоры покидает слой")
        XCTAssertEqual(after.height(at: 140), before.height(at: 140), accuracy: 0.001,
                       "Неподвижная часть окна не сдвигает лежащий на ней снег")
        XCTAssertTrue(sprites(simulation).contains { $0.position.x > 200 },
                      "Снег за новой правой границей превращается в падающие частицы")
    }

    func testRemovedWindowLeavesNoFloatingPileAndItsSnowFallsToGround() throws {
        let (simulation, _) = try accumulatedWindow()
        simulation.updateWindows([], interval: dt)

        XCTAssertFalse(piles(simulation).contains { $0.layer.origin.y == 200 },
                       "Закрытое окно сразу перестаёт поддерживать сугроб")
        XCTAssertFalse(sprites(simulation).isEmpty, "Снег закрытого окна продолжает падать частицами")

        advance(simulation, frames: 240)
        let ground = try XCTUnwrap(piles(simulation).first { $0.layer.origin.y == 0 },
                                   "Снег с закрытого окна должен достичь земли")
        XCTAssertGreaterThan(ground.area, 100, "Удаление окна сохраняет видимый снег в нижнем сугробе")
        simulation.updateWindows([window()], interval: dt)
        XCTAssertFalse(piles(simulation).contains { $0.layer.origin.y == 200 },
                       "Повторно появившееся окно не восстанавливает уже осыпавшийся сугроб")
    }
}
