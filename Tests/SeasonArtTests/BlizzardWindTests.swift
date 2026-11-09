import XCTest
@testable import SeasonArt

final class BlizzardWindTests: XCTestCase {
    func testМетельПлавноНачинаетсяИЗатихаетПриРазнойЧастотеКадров() {
        var levels: [Float] = []
        for fps in [30, 60, 120] {
            var wind = BlizzardWind()
            XCTAssertEqual(wind.velocity(at: SIMD2(100, 200), phase: 1, depth: 1), .zero)
            wind.step(dt: 1 / Float(fps), enabled: true)
            XCTAssertGreaterThan(wind.amount, 0)
            XCTAssertLessThan(wind.amount, 0.1, "Включение не даёт резкого порыва")
            for _ in 1..<fps { wind.step(dt: 1 / Float(fps), enabled: true) }
            levels.append(wind.amount)
            let before = wind.amount
            wind.step(dt: 1 / Float(fps), enabled: false)
            XCTAssertLessThan(wind.amount, before)
            XCTAssertGreaterThan(wind.amount, before * 0.9, "Выключение плавно ослабляет ветер")
            for _ in 0..<(fps * 12) { wind.step(dt: 1 / Float(fps), enabled: false) }
            XCTAssertEqual(wind.amount, 0)
            XCTAssertEqual(wind.velocity(at: SIMD2(100, 200), phase: 1, depth: 1), .zero)
        }
        XCTAssertEqual(levels[0], levels[1], accuracy: 0.0001)
        XCTAssertEqual(levels[1], levels[2], accuracy: 0.0001)
    }

    func testПорывыМеняютсяВоВремениИПространствеБезСкачков() {
        var wind = BlizzardWind()
        for _ in 0..<240 { wind.step(dt: 1 / 60, enabled: true) }
        let position = SIMD2<Float>(500, 400)
        let first = wind.velocity(at: position, phase: 2, depth: 1)
        let nearby = wind.velocity(at: position + SIMD2(1, 1), phase: 2, depth: 1)
        let far = wind.velocity(at: position + SIMD2(300, 300), phase: 2, depth: 1)
        XCTAssertLessThan(abs(first.x - nearby.x), 2)
        XCTAssertLessThan(abs(first.y - nearby.y), 2)
        XCTAssertNotEqual(first, far, "Разные области не двигаются единым листом")
        wind.step(dt: 1 / 120, enabled: true)
        let next = wind.velocity(at: position, phase: 2, depth: 1)
        XCTAssertLessThan(abs(first.x - next.x), 2)
        XCTAssertLessThan(abs(first.y - next.y), 2)
        for _ in 0..<600 { wind.step(dt: 1 / 60, enabled: true) }
        XCTAssertNotEqual(first, wind.velocity(at: position, phase: 2, depth: 1))
    }

    func testВетерОграниченИУчитываетГлубинуХлопьев() {
        var wind = BlizzardWind()
        var minimum: Float = 0
        var maximum: Float = 0
        for frame in 0..<1_800 {
            wind.step(dt: 1 / 30, enabled: true)
            let position = SIMD2<Float>(Float(frame % 400) * 8, Float(frame % 250) * 7)
            let velocity = wind.velocity(at: position, phase: Float(frame % 60), depth: 1)
            minimum = min(minimum, velocity.x)
            maximum = max(maximum, velocity.x)
            XCTAssertTrue(velocity.x.isFinite && velocity.y.isFinite)
            XCTAssertLessThanOrEqual(abs(velocity.x), 100)
            XCTAssertLessThanOrEqual(abs(velocity.y), 20)
            let distant = wind.velocity(at: position, phase: Float(frame % 60), depth: 0)
            XCTAssertLessThanOrEqual(abs(distant.x), abs(velocity.x))
            XCTAssertLessThanOrEqual(abs(distant.y), abs(velocity.y))
        }
        XCTAssertLessThan(minimum, -20, "Метель меняет направление, а не сносит весь снег в одну сторону")
        XCTAssertGreaterThan(maximum, 20)
    }

    func testНеверныйШагВремениНеПортитВетер() {
        var wind = BlizzardWind()
        for dt: Float in [0, -1, .nan, .infinity] { wind.step(dt: dt, enabled: true) }
        XCTAssertEqual(wind.amount, 0)
        wind.step(dt: 1 / 60, enabled: true)
        XCTAssertTrue(wind.amount.isFinite)
    }

    func testМетельМеняетПолётНастоящихХлопьев() {
        let simulation = SnowSimulation(width: 1_000, height: 2_000, snowfall: .light)
        let away = SIMD2<Float>(-1_000, -1_000)
        _ = simulation.step(dt: 1 / 60, cursor: away)
        func meanHorizontalSpeed() -> Float {
            let count = simulation.spriteCount
            let buffer = UnsafeMutablePointer<Sprite>.allocate(capacity: max(1, count))
            defer { buffer.deallocate() }
            let written = simulation.writeSprites(into: buffer, capacity: count)
            XCTAssertGreaterThan(written, 0)
            return (0..<written).reduce(Float(0)) { $0 + buffer[$1].velocity.x } / Float(max(1, written))
        }
        let calm = meanHorizontalSpeed()
        let count = simulation.spriteCount
        simulation.blizzard = true
        for _ in 0..<120 { _ = simulation.step(dt: 1 / 60, cursor: away) }
        XCTAssertGreaterThan(meanHorizontalSpeed(), calm + 8, "Порыв действительно меняет горизонтальную скорость снега")
        XCTAssertEqual(simulation.spriteCount, count, "Переключатель не увеличивает число частиц")
    }

    func testВыключенныйСнегНеЗапускаетсяОтМетели() {
        let simulation = SnowSimulation(width: 600, height: 400, snowfall: .off)
        simulation.blizzard = true
        for _ in 0..<120 { _ = simulation.step(dt: 1 / 60, cursor: SIMD2(-1_000, -1_000)) }
        XCTAssertEqual(simulation.spriteCount, 0)
        XCTAssertTrue(simulation.isEmpty)
    }

    func testПереключательБудитРендерПриИзмененииЗначения() {
        let simulation = SnowSimulation(width: 600, height: 400, snowfall: .off)
        var wakes = 0
        simulation.stirred = { wakes += 1 }
        simulation.blizzard = true
        XCTAssertEqual(wakes, 1)
        simulation.blizzard = true
        XCTAssertEqual(wakes, 1)
        simulation.blizzard = false
        XCTAssertEqual(wakes, 2)
    }
}
