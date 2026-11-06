import CoreGraphics
import XCTest
@testable import SeasonArt

final class SnowSculptingTests: XCTestCase {
    private func layer(height: Float = 8, columns: Int = 160) -> SnowLayer {
        let layer = SnowLayer(origin: .zero, columns: columns, columnWidth: 2,
                              depth: 40, opensAtEdges: false, phases: (0, 0))
        layer.replace(heights: Array(repeating: height, count: columns))
        layer.refreshTop()
        return layer
    }

    private func draft(_ layer: SnowLayer, end: CGFloat) -> SnowSculptingGesture {
        var gesture = SnowSculptingGesture(source: SculptingSource(layer: layer), at: CGPoint(x: 1, y: 1))
        gesture.include(CGPoint(x: end, y: 1))
        return gesture
    }

    func testUniqueColumnsAndSizeBoundaries() {
        let source = layer()
        var gesture = draft(source, end: 17)
        XCTAssertNil(gesture.radius, "Девяти колонок недостаточно для маленького шара")
        gesture.include(CGPoint(x: 19, y: 1))
        XCTAssertEqual(gesture.collectedArea, 40)
        XCTAssertEqual(gesture.radius, 6)
        gesture.include(CGPoint(x: 47, y: 1))
        XCTAssertEqual(gesture.radius, SnowSculptingGesture.radius(for: 96))
        gesture.include(CGPoint(x: 49, y: 1))
        XCTAssertEqual(gesture.radius, SnowSculptingGesture.radius(for: gesture.collectedArea))
        gesture.include(CGPoint(x: 107, y: 1))
        XCTAssertEqual(gesture.radius, SnowSculptingGesture.radius(for: gesture.collectedArea))
        gesture.include(CGPoint(x: 109, y: 1))
        XCTAssertEqual(gesture.radius, 36)
        gesture.include(CGPoint(x: 319, y: 1))
        gesture.include(CGPoint(x: 1, y: 1))
        XCTAssertEqual(gesture.collectedArea, 220, "Повторный проход и длинный жест не увеличивают лимит")
        XCTAssertEqual(source.heights, Array(repeating: 8, count: 160), "Предпросмотр не меняет снег")
    }

    func testPreviewFollowsValidSnowAfterCapAndRepeatedColumns() {
        var gesture = draft(layer(), end: 319)
        XCTAssertEqual(gesture.center.x, 319, "Полный шар следует за указателем по снегу")
        gesture.include(CGPoint(x: 21, y: 1))
        XCTAssertEqual(gesture.center.x, 21, "Возврат по пройденным колонкам перемещает предпросмотр")
        XCTAssertEqual(gesture.collectedArea, 220)
        gesture.include(CGPoint(x: 500, y: 200))
        XCTAssertEqual(gesture.center.x, 21, "За пределами снега центр остаётся на опоре")
    }

    func testAirAndInvalidCoordinatesDoNotCollectSnow() {
        var gesture = SnowSculptingGesture(source: SculptingSource(layer: layer()), at: CGPoint(x: 1, y: 100))
        gesture.include(CGPoint(x: 200, y: 100))
        for value: CGFloat in [.nan, .infinity, -.infinity, 1e100, -1e100] {
            gesture.include(CGPoint(x: value, y: 1))
            gesture.include(CGPoint(x: 1, y: value))
        }
        XCTAssertEqual(gesture.collectedArea, 0, "Воздух и некорректные координаты не дают снег")
    }

    func testHugeFiniteEndpointsDoNotInterpolateThroughPile() {
        let source = SculptingSource(layer: layer())
        var gesture = SnowSculptingGesture(source: source, at: CGPoint(x: 1e100, y: 1))
        gesture.include(CGPoint(x: -1e100, y: 1))
        XCTAssertEqual(gesture.collectedArea, 0, "Непредставимые события мыши не пересекают сугроб")
        XCTAssertNil(gesture.radius)
    }

    func testThinSnowAndHiddenColumnsRestrictCollection() {
        let thin = layer(height: 0.5, columns: 100)
        thin.updateVisibility(screenWidth: 200, blockers: [SIMD4(0, 0, 100, 20)])
        let gesture = draft(thin, end: 199)
        XCTAssertEqual(gesture.collectedArea, 50, "Скрытая половина не участвует, тонкий снег не умножается до двух пунктов")
        XCTAssertEqual(gesture.radius, SnowSculptingGesture.radius(for: 50))
    }

    private func surface(x: CGFloat = 80, blockers: [CGRect] = [], dock: Bool = true) -> WindowSurface {
        WindowSurface(id: 42, frame: CGRect(x: x, y: 0, width: 400, height: 60),
                      blockers: blockers, cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: dock)
    }

    private func simulation() -> SnowSimulation {
        let simulation = SnowSimulation(width: 600, height: 400, snowfall: .off)
        simulation.thaws = false
        simulation.updateWindows([surface()], interval: 1 / 60)
        simulation.scatter((0..<4_000).map { i in
            ScatterPiece(position: SIMD2(100 + Float(i % 180) * 2, 130),
                         velocity: SIMD2(0, -200), color: SIMD3(repeating: 1))
        })
        for _ in 0..<180 { _ = simulation.step(dt: 1 / 60, cursor: SIMD2(-1_000, -1_000)) }
        return simulation
    }

    private func values(_ simulation: SnowSimulation) -> [Float] {
        let count = max(1, simulation.columnCount)
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: count)
        buffer.initialize(repeating: 0, count: count)
        defer { buffer.deinitialize(count: count); buffer.deallocate() }
        _ = simulation.writeLayers(into: buffer, capacity: count)
        return Array(UnsafeBufferPointer(start: buffer, count: count))
    }

    private func gesture(_ simulation: SnowSimulation, end: CGFloat = 300) throws -> SnowSculptingGesture {
        let start = CGPoint(x: 160, y: 61)
        let source = try XCTUnwrap(simulation.sculptingSource(at: start), "Сугроб Dock доступен для лепки")
        var gesture = SnowSculptingGesture(source: source, at: start)
        gesture.include(CGPoint(x: end, y: 61))
        return gesture
    }

    func testCommitRemovesOnlyChosenColumnsWithAreaAndHeightCaps() throws {
        let simulation = simulation()
        let before = values(simulation)
        let distant = simulation.winterSurfaceY(at: 380, on: 42)
        let draft = try gesture(simulation)
        XCTAssertEqual(values(simulation), before, "До отпускания сугроб не меняется")
        let result = try XCTUnwrap(simulation.commitSculpting(draft))
        XCTAssertEqual(result.radius, 36)
        XCTAssertTrue(result.center.x.isFinite && result.center.y.isFinite)
        XCTAssertEqual(result.collectedArea, 220, accuracy: 0.001)
        let after = values(simulation)
        XCTAssertEqual((before.reduce(0, +) - after.reduce(0, +)) * 2, 220, accuracy: 0.1)
        XCTAssertEqual(simulation.winterSurfaceY(at: 380, on: 42), distant, "Дальний участок не меняется")
        XCTAssertTrue(zip(before, after).allSatisfy { $0 - $1 <= 2.001 && $1 >= 0 }, "Высота каждой колонки уменьшается не больше чем на два пункта")
    }

    func testReducedLiveSnowCreatesSmallerBallWithActualArea() throws {
        let simulation = simulation()
        let draft = try gesture(simulation)
        XCTAssertEqual(draft.radius, 36)
        _ = simulation.plowDock(id: 42, fromX: 150, toX: 210)
        let before = values(simulation)
        let result = try XCTUnwrap(simulation.commitSculpting(draft))
        XCTAssertEqual(result.radius, SnowSculptingGesture.radius(for: result.collectedArea))
        XCTAssertLessThan(result.radius, try XCTUnwrap(draft.radius))
        XCTAssertEqual(result.center.y - result.radius, draft.center.y - (try XCTUnwrap(draft.radius)), accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(result.collectedArea, SnowSculptingGesture.mediumArea)
        XCTAssertLessThan(result.collectedArea, SnowSculptingGesture.largeArea)
        let after = values(simulation)
        XCTAssertEqual(CGFloat((before.reduce(0, +) - after.reduce(0, +)) * 2), result.collectedArea, accuracy: 0.1)
    }

    func testInsufficientLiveSnowIsAtomic() throws {
        let simulation = simulation()
        let draft = try gesture(simulation)
        _ = simulation.plowDock(id: 42, fromX: 150, toX: 320)
        let before = values(simulation)
        XCTAssertNil(simulation.commitSculpting(draft), "Недостаток снега при подтверждении отменяет весь жест")
        XCTAssertEqual(values(simulation), before)
    }

    func testMovedRemovedReplacedAndCoveredSourcesCancelWithoutMutation() throws {
        for change in 0..<4 {
            let simulation = simulation()
            let draft = try gesture(simulation)
            switch change {
            case 0: simulation.updateWindows([surface(x: 100)], interval: 1 / 60)
            case 1: simulation.updateWindows([], interval: 1 / 60)
            case 2:
                simulation.updateWindows([], interval: 1 / 60)
                simulation.updateWindows([surface()], interval: 1 / 60)
            default: simulation.updateWindows([surface(blockers: [CGRect(x: 140, y: 0, width: 200, height: 200)])], interval: 1 / 60)
            }
            let before = values(simulation)
            XCTAssertNil(simulation.commitSculpting(draft), "Изменившаяся опора отменяет жест целиком")
            XCTAssertEqual(values(simulation), before)
        }
    }

    func testРадиусРастётНепрерывноИОграничен() throws {
        XCTAssertNil(SnowSculptingGesture.radius(for: 39.999))
        XCTAssertEqual(SnowSculptingGesture.radius(for: 40), 6)
        XCTAssertEqual(SnowSculptingGesture.radius(for: 220), 36)
        XCTAssertEqual(SnowSculptingGesture.radius(for: 999), 36)
        for area: CGFloat in [41, 75.5, 100, 140.25, 219] {
            let radius = try XCTUnwrap(SnowSculptingGesture.radius(for: area))
            let next = try XCTUnwrap(SnowSculptingGesture.radius(for: area + 0.001))
            XCTAssertGreaterThan(next, radius)
            XCTAssertLessThan(next - radius, 0.001, "Порог не меняет размер скачком")
        }
        XCTAssertNil(SnowSculptingGesture.radius(for: .nan))
        XCTAssertNil(SnowSculptingGesture.radius(for: .infinity))
    }

    func testGroundBesideDockCanBeSculptedAboveWindows() throws {
        let simulation = SnowSimulation(width: 600, height: 400, snowfall: .off)
        simulation.thaws = false
        simulation.updateWindows([surface(x: 100)], interval: 1 / 60)
        simulation.scatter((0..<4_000).map { i in
            let x: Float = (i % 2 == 0 ? 20 : 540) + Float(i % 30)
            return ScatterPiece(position: SIMD2(x, 130), velocity: SIMD2(0, -200), color: SIMD3(repeating: 1))
        })
        for _ in 0..<240 { _ = simulation.step(dt: 1 / 60, cursor: SIMD2(-1_000, -1_000)) }
        simulation.windowFrames = [SIMD4(0, 0, 600, 350)]
        for x: CGFloat in [20, 540] {
            let start = CGPoint(x: x, y: 1)
            let source = try XCTUnwrap(simulation.sculptingSource(at: start), "Видимый снег сбоку Dock доступен поверх окна")
            var draft = SnowSculptingGesture(source: source, at: start)
            draft.include(CGPoint(x: x + 28, y: 1))
            XCTAssertNotNil(simulation.commitSculpting(draft), "Проход по снегу создаёт шар с обеих сторон Dock")
        }
    }

    func testGroundHiddenByWindowOrDockCannotBeSculpted() throws {
        let simulation = SnowSimulation(width: 600, height: 400, snowfall: .off)
        simulation.groundBehindWindows = true
        simulation.thaws = false
        simulation.scatter((0..<4_000).map { i in
            ScatterPiece(position: SIMD2(100 + Float(i % 180) * 2, 130),
                         velocity: SIMD2(0, -200), color: SIMD3(repeating: 1))
        })
        for _ in 0..<240 { _ = simulation.step(dt: 1 / 60, cursor: SIMD2(-1_000, -1_000)) }
        let start = CGPoint(x: 160, y: 1)
        var draft = SnowSculptingGesture(source: try XCTUnwrap(simulation.sculptingSource(at: start)), at: start)
        draft.include(CGPoint(x: 300, y: 1))
        simulation.windowFrames = [SIMD4(140, 0, 340, 200)]
        XCTAssertNil(simulation.sculptingSource(at: start), "Снег за окном не участвует в лепке")
        let before = values(simulation)
        XCTAssertNil(simulation.commitSculpting(draft), "Новое перекрытие отменяет подтверждение")
        XCTAssertEqual(values(simulation), before)
        simulation.windowFrames = []
        simulation.groundBehindWindows = false
        simulation.updateWindows([surface()], interval: 1 / 60)
        XCTAssertNil(simulation.sculptingSource(at: start), "Снег под телом Dock скрыт")
    }

    func testEmptyAndInvalidPointsAndOtherModesHaveNoSource() {
        let simulation = SnowSimulation(width: 600, height: 400, snowfall: .off)
        for value: CGFloat in [0, .nan, .infinity, 1e100, -1e100] {
            XCTAssertNil(simulation.sculptingSource(at: CGPoint(x: value, y: 0)))
        }
        let filled = self.simulation()
        filled.mode = .autumn
        XCTAssertNil(filled.sculptingSource(at: CGPoint(x: 160, y: 61)))
    }
}
