import XCTest
@testable import SeasonArt

final class SnowRelaxTimingTests: XCTestCase {
    private func pile(fps: Int, seconds: Float) throws -> [Float] {
        let value = SnowSimulation(width: 600, height: 200, snowfall: .off)
        value.thaws = false
        value.cursorInteracts = false
        let ground = try XCTUnwrap(Mirror(reflecting: value).children.first { $0.label == "ground" }?.value as? SnowLayer)
        let center = ground.clampedIndex(at: 300)
        for i in (center - 3)...(center + 3) { ground.set(i, 80) }
        ground.refreshTop()
        for _ in 0..<Int(seconds * Float(fps)) { _ = value.step(dt: 1 / Float(fps), cursor: SIMD2(-1_000, -1_000)) }
        return ground.heights
    }

    func testСклонОседаетОдинаковоПри30И60Кадрах() throws {
        let slow = try pile(fps: 30, seconds: 0.5)
        let fast = try pile(fps: 60, seconds: 0.5)
        let difference = zip(slow, fast).map { abs($0 - $1) }.max() ?? 0
        XCTAssertLessThan(difference, 1, "Скорость оседания не зависит от частоты кадров")
    }
}
