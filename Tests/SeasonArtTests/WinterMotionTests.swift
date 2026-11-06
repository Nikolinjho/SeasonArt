import XCTest
import AppKit
@testable import SeasonArt

final class WinterMotionTests: XCTestCase {
    private func launch(cadence: Int = 6, y: CGFloat = 14) throws -> (WinterScene, UUID) {
        let scene = WinterScene(width: 2000, height: 1000)
        let id = try XCTUnwrap(scene.create(.small, at: CGPoint(x: 200, y: y)))
        scene.beginDragging(id, at: CGPoint(x: 200, y: y))
        for i in 1...cadence {
            scene.drag(id, to: CGPoint(x: 200 + 30 * CGFloat(i) / CGFloat(cadence), y: y), dt: 0.1 / Double(cadence))
        }
        return (scene, id)
    }

    func testКороткийНулевойСэмплНеГаситБросок() throws {
        for cadence in [3, 6, 12] {
            let (scene, id) = try launch(cadence: cadence)
            scene.drag(id, to: scene.objects[0].center, dt: 0.001)
            scene.endDragging(id)
            XCTAssertEqual(scene.objects[0].velocity.dx, 300, accuracy: 5)
        }
    }

    func testШарКатитсяПоЗемлеИПлавноЗасыпает() throws {
        let (scene, id) = try launch()
        scene.endDragging(id)
        scene.step(dt: 1 / 60)
        XCTAssertGreaterThan(scene.objects[0].velocity.dx, 250)
        let start = scene.objects[0].center.x
        for _ in 0..<60 { scene.step(dt: 1 / 60) }
        XCTAssertGreaterThan(scene.objects[0].center.x, start + 50)
        XCTAssertGreaterThan(scene.objects[0].velocity.dx, 0)
        for _ in 0..<600 { scene.step(dt: 1 / 60) }
        XCTAssertEqual(scene.objects[0].velocity.dx, 0)
        XCTAssertFalse(scene.isMoving)
    }

    func testБыстрыйБросокУСтопкиНеСклеивается() throws {
        let scene = WinterScene(width: 800, height: 600)
        _ = scene.create(.large, at: CGPoint(x: 300, y: 28))
        let id = try XCTUnwrap(scene.create(.small, at: CGPoint(x: 270, y: 70)))
        scene.beginDragging(id, at: CGPoint(x: 270, y: 70))
        scene.drag(id, to: CGPoint(x: 300, y: 70), dt: 0.1)
        scene.endDragging(id)
        XCTAssertEqual(scene.objects.count, 2)
    }

    func testСильныйУдарДаётМаленькийОтскокИНеповторныйПокой() throws {
        let scene = WinterScene(width: 800, height: 600)
        var impacts: [WinterImpact] = []
        scene.didLand = { impacts.append($0) }
        _ = scene.create(.small, at: CGPoint(x: 200, y: 400))
        var bounced = false
        for _ in 0..<180 {
            scene.step(dt: 1 / 120)
            bounced = bounced || scene.objects[0].velocity.dy > 0
        }
        XCTAssertTrue(bounced)
        for _ in 0..<600 { scene.step(dt: 1 / 60) }
        let count = impacts.count
        for _ in 0..<120 { scene.step(dt: 1 / 60) }
        XCTAssertEqual(impacts.count, count)
        XCTAssertFalse(scene.isMoving)
        XCTAssertLessThan(count, 5)
        XCTAssertLessThan(try XCTUnwrap(impacts.first).velocity.dy, -500)
    }
    func testПаузаПередОтпусканиемДаётСпокойнуюУстановку() throws {
        let (scene, id) = try launch()
        scene.endDragging(id, idleTime: 0.2)
        XCTAssertEqual(scene.objects[0].velocity, .zero)
    }

    func testОтменаНеБросаетИНесобирает() throws {
        let scene = WinterScene(width: 800, height: 600)
        _ = scene.create(.large, at: CGPoint(x: 300, y: 28))
        let id = try XCTUnwrap(scene.create(.small, at: CGPoint(x: 270, y: 70)))
        scene.beginDragging(id, at: CGPoint(x: 270, y: 70))
        scene.drag(id, to: CGPoint(x: 300, y: 70), dt: 0.1)
        scene.cancelDragging(id)
        XCTAssertEqual(scene.objects.count, 2)
        XCTAssertFalse(scene.objects[1].isDragged)
        XCTAssertEqual(scene.objects[1].velocity, .zero)
    }

    func testКачениеОдинаковоПриРазнойЧастотеИВращаетТекстуру() throws {
        var positions: [CGFloat] = []
        for fps in [30, 60, 120] {
            let (scene, id) = try launch()
            scene.endDragging(id)
            scene.step(dt: 1 / 120)
            let start = scene.objects[0].center.x
            for _ in 0..<fps { scene.step(dt: 1 / Double(fps)) }
            positions.append(scene.objects[0].center.x)
            XCTAssertEqual(scene.objects[0].rotation, -(scene.objects[0].center.x - start) / 14, accuracy: 0.001)
        }
        XCTAssertLessThan(try XCTUnwrap(positions.max()) - XCTUnwrap(positions.min()), 0.01)
    }

    func testКатящийсяШарПадаетСКраяОкна() throws {
        let scene = WinterScene(width: 1000, height: 600)
        let surface = WindowSurface(id: 1, frame: CGRect(x: 100, y: 100, width: 200, height: 100),
                                    blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: true)
        scene.updateWindows(WindowUpdate(surfaces: [surface], interval: 0.1, parked: [], elsewhere: [], sliding: false, slideVelocity: 0))
        let id = try XCTUnwrap(scene.create(.small, at: CGPoint(x: 240, y: 214)))
        scene.beginDragging(id, at: CGPoint(x: 240, y: 214))
        scene.drag(id, to: CGPoint(x: 270, y: 214), dt: 0.1)
        scene.endDragging(id)
        for _ in 0..<90 { scene.step(dt: 1 / 60) }
        XCTAssertGreaterThan(scene.objects[0].center.x, 300)
        XCTAssertLessThan(scene.objects[0].center.y, 200)
        XCTAssertNil(scene.objects[0].support)
    }

    func testНекорректныеСобытияНеОтравляютСкорость() throws {
        let (scene, id) = try launch(y: 300)
        let before = scene.objects[0].center
        scene.drag(id, to: CGPoint(x: CGFloat.nan, y: 300), dt: 0.01)
        XCTAssertEqual(scene.objects[0].center, before)
        scene.drag(id, to: CGPoint(x: 1800, y: 300), dt: 0.001)
        scene.endDragging(id)
        XCTAssertEqual(scene.objects[0].velocity, .zero)
        let (other, otherID) = try launch(y: 300)
        other.drag(otherID, to: CGPoint(x: 240, y: 300), dt: .nan)
        other.endDragging(otherID)
        XCTAssertEqual(other.objects[0].velocity, .zero)
    }

    func testПаузаРазрешаетСтопкуПослеПереноса() throws {
        let scene = WinterScene(width: 800, height: 600)
        _ = scene.create(.large, at: CGPoint(x: 300, y: 28))
        let id = try XCTUnwrap(scene.create(.small, at: CGPoint(x: 270, y: 70)))
        scene.beginDragging(id, at: CGPoint(x: 270, y: 70))
        scene.drag(id, to: CGPoint(x: 300, y: 70), dt: 0.1)
        scene.endDragging(id, idleTime: 0.2)
        XCTAssertEqual(scene.objects.count, 1)
        XCTAssertEqual(scene.objects[0].radii, [28, 14])
    }

    func testДвижениеИПаркингОкнаСохраняютКачение() throws {
        let scene = WinterScene(width: 2000, height: 1000)
        func update(x: CGFloat, parked: Bool = false) {
            let surface = WindowSurface(id: 1, frame: CGRect(x: x, y: 100, width: 1200, height: 100),
                                        blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: false)
            scene.updateWindows(WindowUpdate(surfaces: parked ? [] : [surface], interval: 0.1,
                                               parked: parked ? [1] : [], elsewhere: [], sliding: false, slideVelocity: 0))
        }
        update(x: 100)
        let id = try XCTUnwrap(scene.create(.small, at: CGPoint(x: 240, y: 214)))
        scene.beginDragging(id, at: CGPoint(x: 240, y: 214))
        scene.drag(id, to: CGPoint(x: 270, y: 214), dt: 0.1)
        scene.endDragging(id)
        scene.step(dt: 1 / 60)
        let before = scene.objects[0]
        update(x: 150)
        XCTAssertEqual(scene.objects[0].center.x, before.center.x + 50, accuracy: 0.001)
        XCTAssertEqual(scene.objects[0].velocity.dx, before.velocity.dx)
        XCTAssertEqual(scene.objects[0].rotation, before.rotation)
        update(x: 150, parked: true)
        let parked = scene.objects[0]
        for _ in 0..<120 { scene.step(dt: 1 / 60) }
        XCTAssertEqual(scene.objects[0].center, parked.center)
        XCTAssertEqual(scene.objects[0].velocity, parked.velocity)
        update(x: 150)
        scene.step(dt: 1 / 60)
        XCTAssertGreaterThan(scene.objects[0].center.x, parked.center.x)
    }

    func testНерегулярнаяЧастотаСохраняетСкоростьАВыбросНеБросает() throws {
        let scene = WinterScene(width: 2000, height: 1000)
        let id = try XCTUnwrap(scene.create(.small, at: CGPoint(x: 200, y: 300)))
        scene.beginDragging(id, at: CGPoint(x: 200, y: 300))
        var time: Double = 0
        for dt in [0.005, 0.04, 0.015, 0.03, 0.01] {
            time += dt
            scene.drag(id, to: CGPoint(x: 200 + 300 * time, y: 300), dt: dt)
        }
        scene.endDragging(id)
        XCTAssertEqual(scene.objects[0].velocity.dx, 300, accuracy: 0.001)
        scene.beginDragging(id, at: scene.objects[0].center)
        scene.drag(id, to: CGPoint(x: 300, y: 300), dt: 0.001)
        scene.endDragging(id)
        XCTAssertEqual(scene.objects[0].velocity, .zero)
    }

    func testДопустимыйБыстрыйЖестОграничиваетПолнуюСкорость() throws {
        let scene = WinterScene(width: 2000, height: 1000)
        let id = try XCTUnwrap(scene.create(.small, at: CGPoint(x: 200, y: 300)))
        scene.beginDragging(id, at: CGPoint(x: 200, y: 300))
        scene.drag(id, to: CGPoint(x: 320, y: 460), dt: 0.1)
        scene.endDragging(id)
        XCTAssertEqual(hypot(scene.objects[0].velocity.dx, scene.objects[0].velocity.dy), 900, accuracy: 0.001)
        XCTAssertGreaterThan(scene.objects[0].velocity.dx, 0)
        XCTAssertGreaterThan(scene.objects[0].velocity.dy, 0)
    }

    func testПоследовательныйОченьБыстрыйЖестСохраняетБросок() throws {
        let scene = WinterScene(width: 2000, height: 1000)
        let id = try XCTUnwrap(scene.create(.small, at: CGPoint(x: 200, y: 300)))
        scene.beginDragging(id, at: CGPoint(x: 200, y: 300))
        for x in [250, 300, 350, 400] {
            scene.drag(id, to: CGPoint(x: x, y: 300), dt: 1 / 120)
        }
        scene.endDragging(id)
        XCTAssertEqual(scene.objects[0].velocity.dx, 900, accuracy: 0.001)
    }

    func testОченьБыстрыйЖестОколоСтопкиНеСклеивается() throws {
        for samples in [1, 4] {
            let scene = WinterScene(width: 2000, height: 1000)
            _ = scene.create(.large, at: CGPoint(x: 500, y: 28))
            let start = CGPoint(x: 500 - samples * 50, y: 70)
            let id = try XCTUnwrap(scene.create(.small, at: start))
            scene.beginDragging(id, at: start)
            for i in 1...samples {
                scene.drag(id, to: CGPoint(x: start.x + CGFloat(i * 50), y: 70), dt: 1 / 120)
            }
            scene.endDragging(id)
            XCTAssertEqual(scene.objects.count, 2)
        }
    }

    func testПослеОтскокаСDockУдарПоЗемлеСохраняется() throws {
        let scene = WinterScene(width: 2000, height: 1000)
        let surface = WindowSurface(id: 1, frame: CGRect(x: 100, y: 200, width: 200, height: 100),
                                    blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: true)
        scene.updateWindows(WindowUpdate(surfaces: [surface], interval: 0.1, parked: [], elsewhere: [], sliding: false, slideVelocity: 0))
        var impacts: [WinterImpact] = []
        scene.didLand = { impacts.append($0) }
        let start = CGPoint(x: 100, y: 394)
        let id = try XCTUnwrap(scene.create(.small, at: start))
        scene.beginDragging(id, at: start)
        scene.drag(id, to: CGPoint(x: 180, y: 314), dt: 0.1)
        scene.endDragging(id)
        for _ in 0..<600 { scene.step(dt: 1 / 120) }
        XCTAssertEqual(impacts.count, 2)
        XCTAssertEqual(impacts.first?.support, 1)
        XCTAssertNil(impacts.last?.support)
        XCTAssertLessThan(try XCTUnwrap(impacts.last).velocity.dy, -500)
        XCTAssertFalse(scene.isMoving)
    }

}
