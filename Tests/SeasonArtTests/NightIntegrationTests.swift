import XCTest
@testable import SeasonArt

final class NightIntegrationTests: XCTestCase {
    func testЗвездопадСоздаётИскрыТолькоНаОткрытойВерхушкеОкна() {
        for covered in [false, true] {
            let simulation = SnowSimulation(width: 800, height: 600, snowfall: .steady)
            simulation.mode = .starfall
            let frame = CGRect(x: 0, y: 100, width: 800, height: 200)
            let surface = WindowSurface(id: 42, frame: frame,
                blockers: covered ? [CGRect(x: 0, y: 250, width: 800, height: 350)] : [],
                cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: false)
            simulation.updateWindows([surface], interval: 1 / 60)
            var windowSparks = false
            for _ in 0..<600 {
                _ = simulation.step(dt: 1 / 60, cursor: SIMD2(-1_000, -1_000))
                windowSparks = windowSparks || sprites(simulation).contains { $0.trail == 0 && $0.position.y > 200 }
            }
            XCTAssertEqual(windowSparks, !covered)
        }
    }

    private func sprites(_ simulation: SnowSimulation) -> [Sprite] {
        let capacity = max(1, simulation.spriteCount)
        let buffer = UnsafeMutablePointer<Sprite>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        let count = simulation.writeSprites(into: buffer, capacity: capacity)
        return Array(UnsafeBufferPointer(start: buffer, count: count))
    }

    func testНочныеРежимыРисуютСветБезСнежинокИНакопления() {
        for mode: Mode in [.fireflies, .starfall] {
            let simulation = SnowSimulation(width: 800, height: 600, snowfall: .steady)
            simulation.mode = mode
            for _ in 0..<300 { _ = simulation.step(dt: 1 / 60, cursor: SIMD2(400, 300)) }
            let frame = sprites(simulation)
            XCTAssertFalse(frame.isEmpty)
            XCTAssertTrue(frame.allSatisfy { $0.glow > 0 })
            XCTAssertFalse(simulation.hasSnow)
            XCTAssertEqual(simulation.pileTop, 0)
            XCTAssertFalse(simulation.isEmpty)
            simulation.snowfall = .off
            _ = simulation.step(dt: 1 / 60, cursor: SIMD2(400, 300))
            XCTAssertTrue(sprites(simulation).isEmpty)
            XCTAssertTrue(simulation.isEmpty)
        }
    }

    func testПереходОтНочногоРежимаКСнегуУбираетСвет() {
        let simulation = SnowSimulation(width: 800, height: 600, snowfall: .steady)
        simulation.mode = .fireflies
        _ = simulation.step(dt: 1 / 60, cursor: SIMD2(400, 300))
        XCTAssertTrue(sprites(simulation).contains { $0.glow > 0 })
        simulation.switchMode(to: .snow, direction: 1, calm: true)
        for _ in 0..<600 { _ = simulation.step(dt: 1 / 60, cursor: SIMD2(-1_000, -1_000)) }
        XCTAssertEqual(simulation.mode, .snow)
        XCTAssertTrue(sprites(simulation).allSatisfy { $0.glow == 0 })
    }
}
