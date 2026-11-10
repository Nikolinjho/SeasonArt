import XCTest
import AppKit
@testable import SeasonArt

final class WinterContactTests: XCTestCase {
    private func run(_ scene: WinterScene, seconds: Double, fps: Int = 60) {
        for _ in 0..<Int(seconds * Double(fps)) { scene.step(dt: 1 / Double(fps)) }
    }

    /// Наибольшее перекрытие кругов шаров разных фигур.
    private func worstOverlap(_ scene: WinterScene) -> CGFloat {
        var worst: CGFloat = 0
        let circles = scene.objects.map { object in
            object.ballFrames.map { frame in
                (center: CGPoint(x: object.frame.minX + frame.midX, y: object.frame.minY + frame.midY), radius: frame.width / 2)
            }
        }
        for a in circles.indices {
            for b in circles.indices where b > a {
                for first in circles[a] {
                    for second in circles[b] {
                        let distance = hypot(first.center.x - second.center.x, first.center.y - second.center.y)
                        worst = max(worst, first.radius + second.radius - distance)
                    }
                }
            }
        }
        return worst
    }

    func testУдерживаемыйШарНеПроходитСквозьДругой() throws {
        let scene = WinterScene(width: 800, height: 600)
        _ = scene.create(radius: 30, at: CGPoint(x: 300, y: 30))
        let id = try XCTUnwrap(scene.create(radius: 20, at: CGPoint(x: 150, y: 20)))
        run(scene, seconds: 0.5)
        scene.beginDragging(id, at: CGPoint(x: 150, y: 20))
        var worst: CGFloat = 0
        for step in 0..<60 {
            scene.drag(id, to: CGPoint(x: 150 + CGFloat(step) * 5, y: 22), dt: 1.0 / 60)
            scene.step(dt: 1.0 / 60)
            worst = max(worst, worstOverlap(scene))
        }
        XCTAssertLessThan(worst, 1.5, "Шар в руке расталкивает соседей, а не проходит сквозь них")
        scene.endDragging(id)
        run(scene, seconds: 2)
        XCTAssertLessThan(worstOverlap(scene), 0.2)
    }

    func testШарВРукеСпокойноЛожитсяНаДругойБезДрожи() throws {
        let scene = WinterScene(width: 800, height: 600)
        _ = scene.create(radius: 28, at: CGPoint(x: 300, y: 28))
        let id = try XCTUnwrap(scene.create(radius: 21, at: CGPoint(x: 200, y: 21)))
        run(scene, seconds: 0.5)
        scene.beginDragging(id, at: CGPoint(x: 200, y: 21))
        var jumps: CGFloat = 0
        // Курсор ведёт шар на верх нижнего и продолжает слегка давить вниз.
        for step in 0..<90 {
            let t = min(1, CGFloat(step) / 45)
            let cursor = CGPoint(x: 200 + 100 * t, y: 21 + 70 * t - CGFloat(max(0, step - 45)) * 0.5)
            scene.drag(id, to: cursor, dt: 1.0 / 60)
            let shown = scene.objects.first { $0.id == id }!.center
            XCTAssertLessThan(worstOverlap(scene), 0.5, "Окно не показывает шар внутри другого")
            scene.step(dt: 1.0 / 60)
            let stepped = scene.objects.first { $0.id == id }!.center
            jumps = max(jumps, hypot(stepped.x - shown.x, stepped.y - shown.y))
        }
        XCTAssertLessThan(jumps, 0.5, "Шаг физики не дёргает шар в руке")
        scene.endDragging(id, idleTime: 0.3)
        run(scene, seconds: 1)
        XCTAssertEqual(scene.objects.count, 1, "Поставленный шар собирается в фигуру")
    }

    func testНовыйШарОтталкиваетСоседаИПоявляетсяНаМестеЛепки() throws {
        let scene = WinterScene(width: 800, height: 600)
        _ = scene.create(radius: 30, at: CGPoint(x: 300, y: 30))
        run(scene, seconds: 0.5)
        let id = try XCTUnwrap(scene.place(radius: 20, near: CGPoint(x: 270, y: 20)))
        XCTAssertLessThan(worstOverlap(scene), 0.01, "Шар не создаётся внутри другого")
        let placed = try XCTUnwrap(scene.objects.first { $0.id == id })
        XCTAssertEqual(placed.center.x, 270, accuracy: 0.01, "Новый шар появляется там, где его лепили")
        XCTAssertGreaterThan(scene.objects[0].center.x, 300, "Готовый шар отодвинут дальше")
        run(scene, seconds: 1)
        XCTAssertLessThan(worstOverlap(scene), 0.2)
    }

    func testНовыйШарТолкаетЦепочкуШаров() throws {
        let scene = WinterScene(width: 800, height: 600)
        _ = scene.create(radius: 20, at: CGPoint(x: 300, y: 20))
        _ = scene.create(radius: 20, at: CGPoint(x: 340, y: 20))
        run(scene, seconds: 0.5)
        let id = try XCTUnwrap(scene.place(radius: 20, near: CGPoint(x: 280, y: 20)))
        XCTAssertEqual(scene.objects.first { $0.id == id }!.center.x, 280, accuracy: 0.01)
        XCTAssertLessThan(worstOverlap(scene), 0.01, "Толкаемый шар толкает следующий")
    }

    func testШарБезМестаЛожитсяСверху() throws {
        let scene = WinterScene(width: 120, height: 600)
        _ = scene.create(radius: 30, at: CGPoint(x: 30, y: 30))
        _ = scene.create(radius: 30, at: CGPoint(x: 90, y: 30))
        _ = try XCTUnwrap(scene.place(radius: 20, near: CGPoint(x: 60, y: 20)))
        XCTAssertLessThan(worstOverlap(scene), 0.01)
        XCTAssertGreaterThan(scene.objects[2].center.y, 50)
    }

    func testСмещённыйШарЛежитНаДругомСпокойно() {
        let scene = WinterScene(width: 800, height: 600)
        _ = scene.create(radius: 28, at: CGPoint(x: 300, y: 28))
        _ = scene.create(radius: 14, at: CGPoint(x: 306, y: 120))
        run(scene, seconds: 3)
        XCTAssertGreaterThan(scene.objects[1].frame.minY, 40, "Липкий снег удерживает шар со смещением 6 px")
        XCTAssertFalse(scene.isMoving, "Стопка засыпает, а не дрожит")
        let resting = scene.objects[1].center
        run(scene, seconds: 1)
        XCTAssertEqual(scene.objects[1].center, resting)
    }

    func testШарСильноСбокуСкатываетсяИВращается() {
        let scene = WinterScene(width: 800, height: 600)
        _ = scene.create(radius: 28, at: CGPoint(x: 300, y: 28))
        _ = scene.create(radius: 14, at: CGPoint(x: 324, y: 120))
        run(scene, seconds: 3)
        XCTAssertEqual(scene.objects[1].frame.minY, 0, accuracy: 0.5, "Шар у края скатывается на землю")
        XCTAssertGreaterThan(scene.objects[1].center.x, 330)
        XCTAssertLessThan(scene.objects[1].rotation, -0.3, "Скатываясь вправо, шар вращается по часовой стрелке")
    }
}
