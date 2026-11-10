import XCTest
import QuartzCore
import CBox2D
@testable import SeasonArt

final class SnowballWorldTests: XCTestCase {
    private func profile(_ world: SnowballWorld) -> WinterChainProfile {
        WinterChainProfile(world: world, body: world.makeStaticBody(key: -1), category: SnowballCategory.snow,
                           mask: SnowballCategory.foot, hysteresis: true)
    }

    func testСнегВМёртвойЗонеНеДвигаетОпору() {
        let world = SnowballWorld(gravity: 1200)
        let ground = profile(world)
        let xs = (0...10).map { CGFloat($0) * 2 }
        ground.update(xs: xs, live: xs.map { _ in 20 }, dt: 0)
        XCTAssertFalse(ground.update(xs: xs, live: xs.map { _ in 22 }, dt: 0.2), "Рост до 2 pt не пересобирает опору")
        XCTAssertEqual(ground.heights.compactMap { $0 }, xs.map { _ in 20 })
        XCTAssertTrue(ground.update(xs: xs, live: xs.map { _ in 19 }, dt: 0.2), "Опускание сразу роняет шары")
        XCTAssertEqual(ground.heights.compactMap { $0 }, xs.map { _ in 19 })
    }

    func testСнегВышеМёртвойЗоныПоднимаетОпоруПлавно() {
        let world = SnowballWorld(gravity: 1200)
        let ground = profile(world)
        let xs = (0...10).map { CGFloat($0) * 2 }
        ground.update(xs: xs, live: xs.map { _ in 20 }, dt: 0)
        var previous: CGFloat = 20
        for _ in 0..<60 {
            ground.update(xs: xs, live: xs.map { _ in 40 }, dt: 1 / 60)
            let current = ground.heights[5]!
            XCTAssertLessThanOrEqual(current - previous, 8.0 / 60 + 0.0001, "Подъём не быстрее 8 pt/с")
            previous = current
        }
        XCTAssertTrue(ground.isRising)
        for _ in 0..<180 { ground.update(xs: xs, live: xs.map { _ in 40 }, dt: 1 / 60) }
        XCTAssertEqual(ground.heights[5]!, 40, accuracy: 0.001)
        XCTAssertFalse(ground.isRising)
    }

    func testПересборкаСугробаДешёвая() {
        let world = SnowballWorld(gravity: 1200)
        let ground = profile(world)
        let xs = (0...864).map { CGFloat($0) * 2 }
        var heights = Array(repeating: CGFloat(20), count: xs.count)
        ground.update(xs: xs, live: heights, dt: 0)
        let start = CACurrentMediaTime()
        for frame in 0..<120 {
            heights[frame * 7 % heights.count] += 3
            ground.update(xs: xs, live: heights, dt: 1)
        }
        let perFrame = (CACurrentMediaTime() - start) / 120 * 1000
        print("Обновление сугроба 864 колонки: \(perFrame) мс")
        XCTAssertLessThan(perFrame, 1, "Пересобираются только изменившиеся куски")
    }
}
