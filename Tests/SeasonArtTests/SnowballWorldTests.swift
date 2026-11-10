import XCTest
import QuartzCore
@testable import SeasonArt

final class SnowballWorldTests: XCTestCase {
    private func run(_ world: SnowballWorld, seconds: Double) {
        for _ in 0..<Int(seconds * 240) { world.step(1.0 / 240) }
    }

    private func flatGround(_ world: SnowballWorld, height: CGFloat = 0) {
        world.setGround(heights: Array(repeating: height, count: 400), originX: 0, columnWidth: 2)
    }

    func testСтопкаИзТрёхШаровСтоитИЗасыпает() {
        let world = SnowballWorld(gravity: 1200)
        flatGround(world)
        let base = world.addBall(radius: 28, center: CGPoint(x: 300, y: 28))
        let torso = world.addBall(radius: 21, center: CGPoint(x: 303, y: 80))
        let head = world.addBall(radius: 14, center: CGPoint(x: 301, y: 120))
        run(world, seconds: 4)
        XCTAssertEqual(world.center(of: base).y, 28, accuracy: 0.5)
        XCTAssertEqual(world.center(of: torso).y, 77, accuracy: 1.5, "Средний шар стоит на нижнем")
        XCTAssertGreaterThan(world.center(of: head).y, 100, "Голова стоит на среднем шаре")
        XCTAssertFalse(world.isAwake(base) || world.isAwake(torso) || world.isAwake(head), "Стопка засыпает")
    }

    func testШарСильноСбокуСкатываетсяИКатится() {
        let world = SnowballWorld(gravity: 1200)
        flatGround(world)
        _ = world.addBall(radius: 28, center: CGPoint(x: 300, y: 28))
        let ball = world.addBall(radius: 14, center: CGPoint(x: 326, y: 75))
        run(world, seconds: 3)
        XCTAssertEqual(world.center(of: ball).y, 14, accuracy: 1, "Шар у края скатывается на землю")
        XCTAssertLessThan(world.angle(of: ball), -0.3, "Скатываясь вправо, шар вращается по часовой стрелке")
    }

    func testБыстрыйБросокНеПролетаетСквозьШар() {
        let world = SnowballWorld(gravity: 0)
        flatGround(world, height: -100)
        let wall = world.addBall(radius: 14, center: CGPoint(x: 400, y: 100))
        let ball = world.addBall(radius: 8, center: CGPoint(x: 100, y: 100))
        world.setVelocity(ball, CGVector(dx: 6000, dy: 0))
        for _ in 0..<12 { world.step(1.0 / 60) }
        XCTAssertLessThan(world.center(of: ball).x, world.center(of: wall).x, "Непрерывные столкновения не пропускают удар")
    }

    func testПересборкаСугробаДешёвая() {
        let world = SnowballWorld(gravity: 1200)
        var heights = Array(repeating: CGFloat(20), count: 864)
        let start = CACurrentMediaTime()
        for frame in 0..<120 {
            heights[frame % heights.count] += 1
            world.setGround(heights: heights, originX: 0, columnWidth: 2)
        }
        let perFrame = (CACurrentMediaTime() - start) / 120 * 1000
        print("Пересборка сугроба 864 колонки: \(perFrame) мс")
        XCTAssertLessThan(perFrame, 2, "Пересборка земли укладывается в кадр")
    }
}
