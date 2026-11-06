import CoreGraphics
import XCTest
@testable import SeasonArt

final class WinterPlowTests: XCTestCase {
    private let dt: Float = 1 / 60
    private let away = SIMD2<Float>(-1_000, -1_000)
    private func surface(_ id: CGWindowID = 42, dock: Bool = true) -> WindowSurface {
        WindowSurface(id: id, frame: CGRect(x: 80, y: 0, width: 400, height: 60),
                      blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: dock)
    }
    private func piles(_ simulation: SnowSimulation) -> [(PileLayer, [Float])] {
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: max(1, simulation.columnCount))
        defer { buffer.deallocate() }
        return simulation.writeLayers(into: buffer, capacity: max(1, simulation.columnCount)).map { layer in
            (layer, Array(UnsafeBufferPointer(start: buffer.advanced(by: layer.offset), count: layer.count)))
        }
    }
    private func accumulated() -> SnowSimulation {
        let simulation = SnowSimulation(width: 600, height: 400, snowfall: .off)
        simulation.thaws = false
        simulation.updateWindows([surface()], interval: dt)
        simulation.scatter((0..<4_000).map { i in
            ScatterPiece(position: SIMD2(100 + Float(i % 180) * 2, 130), velocity: SIMD2(0, -200), color: SIMD3(repeating: 1))
        })
        for _ in 0..<180 { _ = simulation.step(dt: dt, cursor: away) }
        return simulation
    }
    func testCoordinatesOutsideSupportCannotOverflowColumnIndex() {
        let simulation = SnowSimulation(width: 600, height: 400, snowfall: .off)
        simulation.updateWindows([surface()], interval: dt)
        XCTAssertNil(simulation.winterSurfaceY(at: 1e20, on: 42))
        XCTAssertNil(simulation.winterSurfaceY(at: -1e20, on: 42))
        XCTAssertEqual(simulation.plowDock(id: 42, fromX: -1e100, toX: 280), 0,
                       "Пустая полка безопасно обрабатывает диапазон за границей координат Float")
        let huge = CGFloat.greatestFiniteMagnitude * 0.75
        let invalid = WindowSurface(id: 99, frame: CGRect(x: huge, y: 0, width: huge, height: 60),
                                    blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: true)
        XCTAssertNil(WinterPlowPass(surface: invalid), "Переполненная вычисленная граница не создаёт бесконечный проход")
    }

    func testPassRequiresHorizontalDockAndFinishesBeyondItsLeftEnd() throws {
        XCTAssertNil(WinterPlowPass(surface: surface(dock: false)), "Обычное окно не становится полкой Dock")
        var pass = try XCTUnwrap(WinterPlowPass(surface: surface()))
        XCTAssertGreaterThan(pass.bladeX, pass.shelf.maxX, "Машина начинает проход справа")
        var swept = false
        for _ in 0..<2_000 { if let range = pass.advance(dt: 1 / 60) { swept = swept || range.upperBound > range.lowerBound } }
        XCTAssertTrue(swept, "Отвал должен пройти реальную полку")
        XCTAssertTrue(pass.finished, "Проход завершается после ухода всей машины за левый край")
    }
    func testPassRejectsInvalidTimeAndClampsWakeJump() throws {
        var pass = try XCTUnwrap(WinterPlowPass(surface: surface()))
        let before = pass.bladeX
        _ = pass.advance(dt: .nan)
        XCTAssertEqual(pass.bladeX, before)
        _ = pass.advance(dt: 300)
        XCTAssertLessThan(before - pass.bladeX, 10, "Пауза не превращается в мгновенную уборку всей полки")
    }
    func testSurfaceHeightUsesCurrentSnowOnNamedSupport() throws {
        let simulation = accumulated()
        let pile = try XCTUnwrap(piles(simulation).first { $0.0.isDock })
        XCTAssertGreaterThan(pile.1.max() ?? 0, 2)
        let height = try XCTUnwrap(simulation.winterSurfaceY(at: 200, on: 42))
        XCTAssertGreaterThan(height, 60, "Шар лежит над снегом, а не на голой рамке")
        XCTAssertNil(simulation.winterSurfaceY(at: 200, on: 999), "Отсутствующая опора не подменяется землёй")
    }
    func testPlowClearsOnlySweptDockColumnsAndEmitsSnow() throws {
        let simulation = accumulated()
        let before = try XCTUnwrap(piles(simulation).first { $0.0.isDock })
        let ground = (piles(simulation).first { $0.0.origin.y == 0 }?.1 ?? [])
        let mass = simulation.plowDock(id: 42, fromX: 240, toX: 280)
        let after = try XCTUnwrap(piles(simulation).first { $0.0.isDock })
        XCTAssertGreaterThan(mass, 0, "Проход сдвигает накопленную массу")
        for x in stride(from: 242, to: 278, by: 2) {
            let index = Int((Float(x) - before.0.origin.x) / 2)
            XCTAssertEqual(after.1[index], 0, accuracy: 0.001, "Пройденная колонка очищена")
        }
        let distant = Int((Float(380) - before.0.origin.x) / 2)
        XCTAssertEqual(before.1[distant], after.1[distant], "Дальний участок не очищается")
        XCTAssertEqual(ground, (piles(simulation).first { $0.0.origin.y == 0 }?.1 ?? []), "Земля не затронута уборкой Dock")
        XCTAssertGreaterThan(simulation.spriteCount, 0, "Часть снятого снега вылетает частицами")
        let beforeArea = before.1.reduce(0, +) * 2
        let afterArea = after.1.reduce(0, +) * 2
        XCTAssertEqual(beforeArea - afterArea, mass * 0.25, accuracy: 0.5,
                       "Три четверти снятой массы сохраняются в куче перед отвалом, четверть уходит в частицы")
    }
    func testPlowDoesNotClearOrdinaryWindow() {
        let simulation = SnowSimulation(width: 600, height: 400, snowfall: .off)
        simulation.updateWindows([surface(dock: false)], interval: dt)
        XCTAssertEqual(simulation.plowDock(id: 42, fromX: 200, toX: 250), 0)
    }
}
