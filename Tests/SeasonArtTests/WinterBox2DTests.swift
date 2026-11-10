import XCTest
import QuartzCore
@testable import SeasonArt

/// Требования к снежкам на Box2D: без перекрытий, устойчивые стопки, толчки и дешёвый покой.
final class WinterBox2DTests: XCTestCase {
    private func run(_ scene: WinterScene, seconds: Double, fps: Int = 60) {
        for _ in 0..<Int(seconds * Double(fps)) { scene.step(dt: 1 / Double(fps)) }
    }

    func testШарВРукеНеПоказываетсяВнутриДругихШаров() throws {
        let scene = WinterScene(width: 900, height: 600)
        for (index, x) in stride(from: 200, through: 700, by: 70).enumerated() {
            _ = scene.create(radius: 14 + CGFloat(index % 3) * 7, at: CGPoint(x: x, y: 40))
        }
        run(scene, seconds: 2)
        let id = try XCTUnwrap(scene.create(radius: 20, at: CGPoint(x: 100, y: 200)))
        scene.beginDragging(id, at: CGPoint(x: 100, y: 200))
        var shown: CGFloat = 0
        var stepped: CGFloat = 0
        for frame in 0..<240 {
            let t = CGFloat(frame) / 240
            // Курсор ныряет к земле и проходит сквозь ряд шаров туда и обратно.
            let cursor = CGPoint(x: 100 + 700 * sin(t * .pi), y: 200 - 180 * sin(t * .pi * 3).magnitude)
            scene.drag(id, to: cursor, dt: 1 / 60)
            shown = max(shown, winterWorstOverlap(scene))
            scene.step(dt: 1 / 60)
            stepped = max(stepped, winterWorstOverlap(scene))
        }
        XCTAssertLessThan(shown, 0.5, "Окно не показывает шар в руке внутри другого")
        XCTAssertLessThan(stepped, 1.5, "Шаг физики расталкивает соседей, а не проводит шар сквозь них")
        scene.endDragging(id, idleTime: 0.2)
        run(scene, seconds: 3)
        XCTAssertLessThan(winterWorstOverlap(scene), 0.3)
        XCTAssertFalse(scene.isMoving)
    }

    func testШарВРукеОтталкиваетСвободныйИУпираетсяВОпёртый() throws {
        let scene = WinterScene(width: 900, height: 600)
        let free = try XCTUnwrap(scene.create(radius: 14, at: CGPoint(x: 300, y: 14)))
        let base = try XCTUnwrap(scene.create(radius: 28, at: CGPoint(x: 600, y: 28)))
        run(scene, seconds: 1)
        let id = try XCTUnwrap(scene.create(radius: 21, at: CGPoint(x: 200, y: 21)))
        scene.beginDragging(id, at: CGPoint(x: 200, y: 21))
        for step in 1...30 {
            scene.drag(id, to: CGPoint(x: 200 + CGFloat(step) * 4, y: 21), dt: 1 / 60)
            scene.step(dt: 1 / 60)
        }
        XCTAssertGreaterThan(try XCTUnwrap(scene.objects.first { $0.id == free }).center.x, 310, "Свободный шар откатывается")
        let held = try XCTUnwrap(scene.objects.first { $0.id == id })
        scene.drag(id, to: CGPoint(x: 600, y: 100), dt: 1 / 60)
        for _ in 0..<30 {
            scene.drag(id, to: CGPoint(x: 600, y: 60), dt: 1 / 60)
            scene.step(dt: 1 / 60)
        }
        let pressed = try XCTUnwrap(scene.objects.first { $0.id == id })
        let lower = try XCTUnwrap(scene.objects.first { $0.id == base })
        XCTAssertEqual(lower.center.y, 28, accuracy: 0.1, "Опёртый шар не продавливается в землю")
        XCTAssertGreaterThan(pressed.center.y, 28 + 49 - 1, "Шар в руке ложится сверху, а не проходит внутрь")
        XCTAssertNotEqual(held.center, pressed.center)
    }

    func testСнеговикСтоитНеподвижноИЗасыпает() throws {
        let scene = WinterScene(width: 800, height: 600)
        for (radius, y): (CGFloat, CGFloat) in [(28, 28), (21, 80), (14, 120)] {
            _ = scene.create(radius: radius, at: CGPoint(x: 300, y: y))
        }
        run(scene, seconds: 3)
        let snowman = try XCTUnwrap(scene.objects.first)
        XCTAssertTrue(snowman.isSnowman)
        XCTAssertFalse(scene.isMoving)
        var drift: CGFloat = 0
        for _ in 0..<600 {
            scene.step(dt: 1 / 60)
            let center = scene.objects[0].center
            drift = max(drift, hypot(center.x - snowman.center.x, center.y - snowman.center.y))
        }
        XCTAssertLessThan(drift, 0.001, "Снеговик не дрожит")
        // Шар, упавший на голову, не раскачивает и не роняет снеговика.
        _ = scene.create(radius: 10, at: CGPoint(x: 302, y: 400))
        run(scene, seconds: 4)
        XCTAssertEqual(scene.objects[0].center.x, snowman.center.x, accuracy: 3)
        XCTAssertEqual(scene.objects[0].visibleBottom, 0, accuracy: 0.6)
    }

    func testСтопкаИзТрёхОтдельныхШаровНеДрожитДоСборки() {
        let scene = WinterScene(width: 800, height: 600)
        for (radius, y): (CGFloat, CGFloat) in [(28, 28), (21, 77.5), (14, 113)] {
            _ = scene.create(radius: radius, at: CGPoint(x: 300, y: y))
        }
        var lowest = CGFloat.infinity
        for _ in 0..<12 {
            scene.step(dt: 1 / 60)
            lowest = min(lowest, scene.objects.map(\.center.y).max() ?? 0)
        }
        XCTAssertGreaterThan(lowest, 105, "Голова не проваливается в стопку")
        run(scene, seconds: 2)
        XCTAssertEqual(scene.objects.count, 1)
    }

    func testНовыйШарУпёршисьВСтенуНеСдвигаетСоседей() {
        let scene = WinterScene(width: 200, height: 600)
        _ = scene.create(radius: 20, at: CGPoint(x: 160, y: 20))
        _ = scene.create(radius: 20, at: CGPoint(x: 120, y: 20))
        run(scene, seconds: 1)
        let before = scene.objects.map(\.center)
        XCTAssertFalse(scene.makeRoom(radius: 20, at: CGPoint(x: 100, y: 20)), "Цепочка упирается в край экрана")
        XCTAssertEqual(scene.objects.map(\.center), before)
    }

    func testУвеличенныйDockРасталкиваетНесколькоШаров() throws {
        let scene = WinterScene(width: 800, height: 600)
        let dock = WindowSurface(id: 42, frame: CGRect(x: 100, y: 6, width: 300, height: 60),
                                 blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: true)
        scene.updateWindows(WindowUpdate(surfaces: [dock], interval: 0.1, parked: [], elsewhere: [], sliding: false, slideVelocity: 0))
        var presented = dock.frame
        scene.dockBody = { _ in presented }
        _ = scene.create(radius: 14, at: CGPoint(x: 416, y: 14))
        _ = scene.create(radius: 14, at: CGPoint(x: 446, y: 14))
        run(scene, seconds: 1)
        XCTAssertFalse(scene.isMoving)
        for step in 1...10 {
            presented = CGRect(x: 100 - CGFloat(step) * 4, y: 6, width: 300 + CGFloat(step) * 8, height: 60)
            scene.synchronizeDockSupports()
            scene.step(dt: 1 / 60)
        }
        run(scene, seconds: 2)
        let xs = scene.objects.map(\.center.x).sorted()
        XCTAssertGreaterThanOrEqual(xs[0], presented.maxX + 14 - 0.6, "Корпус отодвигает ближний шар")
        XCTAssertGreaterThanOrEqual(xs[1] - xs[0], 28 - 0.3, "Ближний шар толкает дальний, а не входит в него")
        XCTAssertLessThan(winterWorstOverlap(scene), 0.3)
    }

    func testШестьдесятЧетыреСпящихШараПочтиНичегоНеСтоят() {
        let scene = WinterScene(width: 1800, height: 1100)
        for i in 0..<64 {
            _ = scene.create(radius: 14 + CGFloat(i % 4) * 6,
                             at: CGPoint(x: 60 + CGFloat(i % 16) * 105, y: 300 + CGFloat(i / 16) * 120))
        }
        var moving = 0
        let fallStart = CACurrentMediaTime()
        for _ in 0..<600 where scene.isMoving {
            scene.step(dt: 1.0 / 60)
            moving += 1
        }
        let perMovingFrame = (CACurrentMediaTime() - fallStart) / Double(max(1, moving)) * 1000
        XCTAssertFalse(scene.isMoving)
        let start = CACurrentMediaTime()
        for _ in 0..<600 { scene.step(dt: 1.0 / 60) }
        let perStep = (CACurrentMediaTime() - start) / 600 * 1000
        print("64 шара: падение \(perMovingFrame) мс на кадр (\(moving) кадров), покой \(perStep) мс на шаг")
        XCTAssertLessThan(perStep, 0.2, "Спящие тела почти бесплатны")
    }
}
