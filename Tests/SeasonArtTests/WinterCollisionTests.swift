import XCTest
import AppKit
@testable import SeasonArt

final class WinterCollisionTests: XCTestCase {
    private func run(_ scene: WinterScene, seconds: Double = 5, fps: Int = 60) {
        for _ in 0..<Int(seconds * Double(fps)) { scene.step(dt: 1 / Double(fps)) }
    }

    private func throwBall(_ scene: WinterScene, radius: CGFloat, from: CGPoint, to: CGPoint, dt: Double = 0.1) throws -> UUID {
        let id = try XCTUnwrap(scene.create(radius: radius, at: from))
        scene.beginDragging(id, at: from)
        scene.drag(id, to: to, dt: dt)
        scene.endDragging(id)
        return id
    }

    func testПадающийШарЛежитНаДругомИЗасыпает() throws {
        let scene = WinterScene(width: 800, height: 600)
        _ = scene.create(.large, at: CGPoint(x: 300, y: 28))
        _ = scene.create(.small, at: CGPoint(x: 300, y: 300))
        run(scene)
        XCTAssertEqual(scene.objects.count, 2)
        XCTAssertEqual(scene.objects[1].visibleBottom, scene.objects[0].visibleTop, accuracy: 0.6)
        XCTAssertEqual(scene.objects[1].center.x, 300, accuracy: 0.5, "Шар точно над центром не скатывается")
        XCTAssertFalse(scene.isMoving)
        let before = scene.objects[1].center
        run(scene)
        XCTAssertEqual(scene.objects[1].center, before)
    }

    func testБросокПередаётДвижениеДругомуШаруСУчётомМассы() throws {
        var displacement: [CGFloat] = []
        for radius: CGFloat in [14, 28] {
            let scene = WinterScene(width: 2000, height: 600)
            _ = scene.create(radius: radius, at: CGPoint(x: 320, y: radius))
            _ = try throwBall(scene, radius: 14, from: CGPoint(x: 200, y: 14), to: CGPoint(x: 240, y: 14))
            run(scene, seconds: 0.6)
            displacement.append(scene.objects[0].center.x - 320)
            XCTAssertGreaterThan(displacement.last!, 1)
            XCTAssertGreaterThanOrEqual(scene.objects[0].frame.minY, -0.01)
        }
        XCTAssertGreaterThan(displacement[0], displacement[1])
    }

    func testБыстрыеМаленькиеШарыНеПроходятСквозьДругДругаПриРазнойЧастоте() throws {
        var positions: [CGFloat] = []
        for fps in [30, 60, 120] {
            let scene = WinterScene(width: 2000, height: 600)
            _ = scene.create(radius: 6, at: CGPoint(x: 300, y: 6))
            _ = try throwBall(scene, radius: 6, from: CGPoint(x: 150, y: 6), to: CGPoint(x: 240, y: 6))
            run(scene, seconds: 0.5, fps: fps)
            XCTAssertLessThan(scene.objects[1].center.x, scene.objects[0].center.x)
            XCTAssertGreaterThan(scene.objects[0].center.x, 310)
            positions.append(scene.objects[0].center.x)
        }
        XCTAssertLessThan(positions.max()! - positions.min()!, 2)
    }

    func testСовпадающиеЦентрыРазделяютсяБезВыходаЗаГраницы() {
        let scene = WinterScene(width: 100, height: 600)
        _ = scene.create(.small, at: CGPoint(x: 14, y: 14))
        _ = scene.create(.small, at: CGPoint(x: 14, y: 14))
        run(scene)
        XCTAssertGreaterThanOrEqual(abs(scene.objects[0].center.x - scene.objects[1].center.x), 27.9)
        for object in scene.objects {
            XCTAssertTrue(object.center.x.isFinite && object.center.y.isFinite)
            XCTAssertGreaterThanOrEqual(object.frame.minX, -0.01)
            XCTAssertGreaterThanOrEqual(object.frame.minY, -0.01)
            XCTAssertLessThanOrEqual(object.frame.maxX, 100.01)
        }
    }

    func testПереносОпорыБудитВерхнийШарИНеМешаетРучнойСборке() throws {
        let scene = WinterScene(width: 800, height: 600)
        let base = try XCTUnwrap(scene.create(.large, at: CGPoint(x: 300, y: 28)))
        _ = scene.create(.small, at: CGPoint(x: 300, y: 300))
        run(scene)
        scene.beginDragging(base, at: scene.objects[0].center)
        scene.drag(base, to: CGPoint(x: 500, y: 28), dt: 0.1)
        let held = scene.objects[0].center
        run(scene)
        XCTAssertEqual(scene.objects[0].center, held)
        XCTAssertEqual(scene.objects[1].visibleBottom, 0, accuracy: 0.6)
        scene.cancelDragging(base)
        let top = scene.objects[1].id
        scene.beginDragging(top, at: scene.objects[1].center)
        scene.drag(top, to: CGPoint(x: 500, y: 70), dt: 0.1)
        scene.step(dt: 1 / 30)
        scene.endDragging(top, idleTime: 0.2)
        XCTAssertEqual(scene.objects.count, 1)
    }
    private func snowman(_ scene: WinterScene) throws {
        _ = scene.create(.large, at: CGPoint(x: 300, y: 28))
        run(scene, seconds: 1)
        for size in [WinterBallSize.medium, .small] {
            let point = CGPoint(x: 300, y: scene.objects[0].frame.maxY + size.radius)
            let id = try XCTUnwrap(scene.create(size, at: point))
            scene.beginDragging(id, at: point)
            scene.endDragging(id)
        }
    }

    func testШарОпираетсяНаГоловуСнеговика() throws {
        let scene = WinterScene(width: 800, height: 600)
        try snowman(scene)
        let top = scene.objects[0].frame.maxY
        _ = scene.create(.small, at: CGPoint(x: 300, y: 300))
        run(scene)
        XCTAssertEqual(scene.objects.count, 2)
        XCTAssertEqual(scene.objects[1].visibleBottom, top, accuracy: 0.6)
        XCTAssertFalse(scene.isMoving)
    }

    func testУглыПрямоугольникаСнеговикаНеСоздаютЛожныйКонтакт() throws {
        let scene = WinterScene(width: 800, height: 600)
        try snowman(scene)
        _ = scene.create(radius: 6, at: CGPoint(x: 322, y: 113))
        scene.step(dt: 1 / 120)
        XCTAssertEqual(scene.objects[1].center.x, 322, accuracy: 0.0001, "Шар рядом с головой не отталкивается")
        XCTAssertLessThan(scene.objects[1].center.y, 113, "Свободный шар падает")
        XCTAssertGreaterThan(scene.objects[1].center.y, 112.9)
    }

    func testУдалениеНижнегоШараБудитВерхнийБезОжиданияТаймера() throws {
        let scene = WinterScene(width: 800, height: 600)
        _ = scene.create(.large, at: CGPoint(x: 300, y: 28))
        _ = scene.create(.small, at: CGPoint(x: 300, y: 300))
        run(scene)
        scene.shoveObjects(in: CGRect(x: 270, y: 0, width: 60, height: 50), by: 1000)
        XCTAssertEqual(scene.objects.count, 1)
        XCTAssertTrue(scene.isMoving)
        run(scene)
        XCTAssertEqual(scene.objects[0].visibleBottom, 0, accuracy: 0.6)
    }

    func testПрипаркованнаяОпораНеДержитШарДругогоПространства() {
        let scene = WinterScene(width: 800, height: 600)
        let surface = WindowSurface(id: 1, frame: CGRect(x: 100, y: 100, width: 500, height: 100),
                                    blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: false)
        scene.updateWindows(WindowUpdate(surfaces: [surface], interval: 0.1, parked: [], elsewhere: [], sliding: false, slideVelocity: 0))
        _ = scene.create(.large, at: CGPoint(x: 300, y: 228))
        _ = scene.create(.small, at: CGPoint(x: 300, y: 500))
        run(scene)
        XCTAssertEqual(scene.objects[1].visibleBottom, scene.objects[0].visibleTop, accuracy: 0.6)
        scene.updateWindows(WindowUpdate(surfaces: [], interval: 0.1, parked: [], elsewhere: [1], sliding: false, slideVelocity: 0))
        XCTAssertTrue(scene.isMoving)
        run(scene)
        XCTAssertTrue(scene.objects[0].parked)
        XCTAssertEqual(scene.objects[1].visibleBottom, 0, accuracy: 0.6)
    }

    func testПолнаяСценаСохраняетКонечныеКоординатыИГраницы() {
        let scene = WinterScene(width: 2000, height: 600)
        for index in 0..<64 {
            _ = scene.create(radius: 6, at: CGPoint(x: 100 + (index % 16) * 30, y: 6 + (index / 16) * 20))
        }
        run(scene, seconds: 2)
        XCTAssertEqual(scene.objects.reduce(0) { $0 + $1.radii.count }, 64,
                       "Сборка сохраняет все шары полной сцены")
        for object in scene.objects {
            XCTAssertTrue(object.center.x.isFinite && object.center.y.isFinite)
            XCTAssertGreaterThanOrEqual(object.frame.minY, -0.01)
        }
    }

    func testБоковоеРазделениеНеОставляетСпящийШарВВоздухе() {
        let scene = WinterScene(width: 800, height: 600)
        _ = scene.create(.large, at: CGPoint(x: 300, y: 28))
        _ = scene.create(.small, at: CGPoint(x: 300, y: 300))
        run(scene)
        _ = scene.create(.small, at: CGPoint(x: 320, y: 70))
        run(scene)
        XCTAssertFalse(scene.isMoving)
        for object in scene.objects where object.visibleBottom > 0.6 {
            let supported = scene.objects.contains { other in
                guard other.id != object.id, other.center.y < object.center.y else { return false }
                return hypot(object.center.x - other.center.x, object.center.y - other.center.y) <
                    object.radii[0] + other.radii[0] + 0.5
            }
            XCTAssertTrue(supported, "Спящий шар должен касаться нижней опоры")
        }
    }

    func testСборкаНаОснованииБудитЛежащийНаНёмОтдельныйШар() throws {
        let scene = WinterScene(width: 800, height: 600)
        _ = scene.create(.large, at: CGPoint(x: 300, y: 28))
        _ = scene.create(.small, at: CGPoint(x: 300, y: 300))
        run(scene)
        let point = CGPoint(x: 300, y: 70)
        let id = try XCTUnwrap(scene.create(.small, at: point))
        scene.beginDragging(id, at: point)
        scene.endDragging(id)
        XCTAssertTrue(scene.isMoving)
        run(scene)
        XCTAssertEqual(scene.objects.count, 1, "После пробуждения и посадки третьего шара собирается снеговик")
        XCTAssertTrue(scene.objects[0].isSnowman)
    }

}
