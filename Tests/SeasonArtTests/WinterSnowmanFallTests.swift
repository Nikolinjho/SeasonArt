import AppKit
import XCTest
@testable import SeasonArt

final class WinterSnowmanFallTests: XCTestCase {
    private func advance(_ scene: WinterScene, seconds: Double = 3, fps: Int = 60) {
        for _ in 0..<Int(seconds * Double(fps)) { scene.step(dt: 1 / Double(fps)) }
    }

    private func makeSnowman(in scene: WinterScene) throws -> UUID {
        let base = try XCTUnwrap(scene.create(.large, at: CGPoint(x: 300, y: 28)))
        let torsoPoint = CGPoint(x: 300, y: 77)
        let torso = try XCTUnwrap(scene.create(.medium, at: torsoPoint))
        scene.beginDragging(torso, at: torsoPoint)
        scene.endDragging(torso)
        let headPoint = CGPoint(x: 300, y: scene.objects[0].frame.maxY + 14)
        let head = try XCTUnwrap(scene.create(.small, at: headPoint))
        scene.beginDragging(head, at: headPoint)
        scene.endDragging(head)
        advance(scene)
        XCTAssertEqual(scene.objects.count, 1)
        XCTAssertTrue(scene.objects[0].isSnowman)
        return base
    }

    private func drop(_ scene: WinterScene, id: UUID, distance: CGFloat) throws {
        let object = try XCTUnwrap(scene.objects.first { $0.id == id })
        scene.beginDragging(id, at: object.center)
        scene.drag(id, to: CGPoint(x: object.center.x, y: object.center.y + distance), dt: 1)
        scene.endDragging(id, idleTime: 0.3)
        advance(scene)
    }

    func testВысотаПаденияУсиливаетПовреждениеВсехЧастейСнеговика() throws {
        var depths: [[CGFloat]] = []
        for distance: CGFloat in [0, 50, 150] {
            let scene = WinterScene(width: 800, height: 600)
            let id = try makeSnowman(in: scene)
            try drop(scene, id: id, distance: distance)
            let snowman = try XCTUnwrap(scene.objects.first { $0.id == id })
            XCTAssertTrue(snowman.isSnowman)
            depths.append((0..<3).map { snowman.damage(for: $0).depth })
        }
        for component in 0..<3 {
            XCTAssertEqual(depths[0][component], 0)
            XCTAssertGreaterThan(depths[1][component], 0)
            XCTAssertGreaterThan(depths[2][component], depths[1][component])
        }
    }

    func testПереносСнеговикаВРукеНеНаноситУрон() throws {
        let scene = WinterScene(width: 800, height: 600)
        let id = try makeSnowman(in: scene)
        let initial = scene.objects[0]
        scene.beginDragging(id, at: initial.center)
        scene.drag(id, to: CGPoint(x: 400, y: 480), dt: 1)
        advance(scene)
        scene.drag(id, to: CGPoint(x: 400, y: 28), dt: 1)
        scene.endDragging(id, idleTime: 0.3)
        advance(scene)
        let object = try XCTUnwrap(scene.objects.first { $0.id == id })
        XCTAssertTrue(object.isSnowman)
        XCTAssertEqual(object.ballDamage, initial.ballDamage)
    }

    func testПадениеВышеТретиЭкранаРазбиваетСнеговикаНаПовреждённыеШары() throws {
        for fps in [30, 60, 120] {
            let scene = WinterScene(width: 800, height: 600)
            let id = try makeSnowman(in: scene)
            let object = try XCTUnwrap(scene.objects.first { $0.id == id })
            scene.beginDragging(id, at: object.center)
            scene.drag(id, to: CGPoint(x: 300, y: object.center.y + 230), dt: 1)
            scene.endDragging(id, idleTime: 0.3)
            advance(scene, fps: fps)
            XCTAssertEqual(scene.objects.count, 3)
            XCTAssertTrue(scene.objects.allSatisfy { $0.radii.count == 1 && $0.damage(for: 0).depth > 0 })
            XCTAssertEqual(scene.objects.map { $0.radii[0] }.sorted(), [14, 21, 28])
            XCTAssertGreaterThan(scene.objects.map(\.center.x).max()! - scene.objects.map(\.center.x).min()!, 40)
        }
    }

    func testБросокВверхУчитываетВершинуАНеТочкуОтпускания() throws {
        let scene = WinterScene(width: 800, height: 600)
        let id = try makeSnowman(in: scene)
        let object = scene.objects[0]
        scene.beginDragging(id, at: object.center)
        scene.drag(id, to: CGPoint(x: 300, y: object.center.y + 30), dt: 0.035)
        scene.endDragging(id)
        advance(scene)
        XCTAssertFalse(scene.objects.contains { $0.isSnowman }, "Бросок с 30 pt поднимается выше 200 pt и разрушает фигуру")
    }

    func testПорогРазрушенияРавенТретиТекущейВысотыЭкрана() throws {
        for (screenHeight, distance, breaks): (CGFloat, CGFloat, Bool) in [
            (600, 199, false), (600, 200, false), (600, 200.01, true), (600, 202, true),
            (900, 250, false), (900, 302, true),
        ] {
            let scene = WinterScene(width: 800, height: screenHeight)
            let id = try makeSnowman(in: scene)
            try drop(scene, id: id, distance: distance)
            XCTAssertEqual(scene.objects.contains { $0.isSnowman }, !breaks,
                "Экран \(screenHeight) pt, падение \(distance) pt")
        }
    }

    func testНизкаяПромежуточнаяПосадкаЗавершаетВысотуПадения() throws {
        let scene = WinterScene(width: 800, height: 600)
        let id = try makeSnowman(in: scene)
        let object = scene.objects[0]
        scene.beginDragging(id, at: object.center)
        scene.drag(id, to: CGPoint(x: 300, y: 360), dt: 1)
        let shelf = WindowSurface(id: 42, frame: CGRect(x: 100, y: 0, width: 500, height: 220),
            blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: false)
        scene.updateWindows(WindowUpdate(surfaces: [shelf], interval: 1 / 60,
            parked: [], elsewhere: [], sliding: false, slideVelocity: 0))
        scene.endDragging(id, idleTime: 0.3)
        advance(scene)
        XCTAssertTrue(try XCTUnwrap(scene.objects.first { $0.id == id }).isSnowman)
        // Новый перелёт на 150 pt тоже меньше порога, суммарная высота не накапливается.
        try drop(scene, id: id, distance: 150)
        XCTAssertTrue(try XCTUnwrap(scene.objects.first { $0.id == id }).isSnowman)
    }

    func testРазрушениеПриПолномЛимитеНеДобавляетЛишнихОбъектов() throws {
        let scene = WinterScene(width: 800, height: 600)
        let id = try makeSnowman(in: scene)
        for i in 0..<(WinterScene.maximumObjects - 1) {
            _ = scene.create(.small, at: CGPoint(x: 500 + CGFloat(i % 9) * 30, y: 14 + CGFloat(i / 9) * 30))
        }
        try drop(scene, id: id, distance: 230)
        XCTAssertLessThanOrEqual(scene.objects.count, WinterScene.maximumObjects)
        XCTAssertFalse(scene.objects.contains { $0.id == id && $0.isSnowman })
    }

    func testДвижениеОкнаИВозвратИзДругогоSpaceНеСчитаютсяПадением() throws {
        let scene = WinterScene(width: 800, height: 800)
        let id = try makeSnowman(in: scene)
        func update(top: CGFloat, elsewhere: Bool = false) {
            let surface = WindowSurface(id: 42, frame: CGRect(x: 100, y: top - 80, width: 500, height: 80),
                blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: false)
            scene.updateWindows(WindowUpdate(surfaces: elsewhere ? [] : [surface], interval: 1 / 60,
                parked: [], elsewhere: elsewhere ? [42] : [], sliding: false, slideVelocity: 0))
        }
        let initial = scene.objects[0]
        scene.beginDragging(id, at: initial.center)
        scene.drag(id, to: CGPoint(x: 300, y: 428), dt: 1)
        update(top: 400)
        scene.endDragging(id, idleTime: 0.3)
        advance(scene)
        XCTAssertEqual(scene.objects[0].support, 42)
        let damage = scene.objects[0].ballDamage
        update(top: 100)
        advance(scene)
        XCTAssertTrue(scene.objects[0].isSnowman)
        XCTAssertEqual(scene.objects[0].ballDamage, damage)
        update(top: 100, elsewhere: true)
        XCTAssertTrue(scene.objects[0].parked)
        advance(scene, seconds: 10)
        update(top: 400)
        advance(scene)
        XCTAssertFalse(scene.objects[0].parked)
        XCTAssertTrue(scene.objects[0].isSnowman)
        XCTAssertEqual(scene.objects[0].ballDamage, damage)
    }

    func testРастущийСнегПоднимаетСнеговикаБезПовреждений() throws {
        let scene = WinterScene(width: 800, height: 600)
        var depth: CGFloat = 120
        scene.surfaceHeight = { _, _ in depth }
        let id = try XCTUnwrap(scene.create(.large, at: CGPoint(x: 300, y: 148)))
        _ = scene.create(.medium, at: CGPoint(x: 300, y: 210))
        _ = scene.create(.small, at: CGPoint(x: 300, y: 280))
        advance(scene)
        let initial = try XCTUnwrap(scene.objects.first { $0.id == id })
        XCTAssertTrue(initial.isSnowman)
        for step in 0..<300 {
            depth = 120 + CGFloat(step) * 0.15
            scene.step(dt: 1 / 60)
        }
        advance(scene, seconds: 8)
        let snowman = try XCTUnwrap(scene.objects.first { $0.id == id })
        XCTAssertTrue(snowman.isSnowman)
        XCTAssertGreaterThan(snowman.center.y, initial.center.y + 20)
        XCTAssertEqual(snowman.ballDamage, initial.ballDamage)
    }
}
