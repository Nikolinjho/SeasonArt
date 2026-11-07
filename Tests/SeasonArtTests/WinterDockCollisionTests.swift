import XCTest
import AppKit
@testable import SeasonArt

final class WinterDockCollisionTests: XCTestCase {
    private func scene(y: CGFloat = 6, visible: Bool = true) -> WinterScene {
        let scene = WinterScene(width: 800, height: 600)
        let dock = WindowSurface(id: 42, frame: CGRect(x: 100, y: y, width: 300, height: 60),
                                 blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: true)
        scene.updateWindows(WindowUpdate(surfaces: visible ? [dock] : [], interval: 0.1, parked: [], elsewhere: [], sliding: false, slideVelocity: 0))
        return scene
    }

    private func assertOutside(_ scene: WinterScene, body: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        for object in scene.objects where !object.parked {
            for frame in object.ballFrames {
                let center = CGPoint(x: object.center.x, y: object.frame.minY + frame.midY)
                let nearest = CGPoint(x: min(max(center.x, body.minX), body.maxX),
                                      y: min(max(center.y, body.minY), body.maxY))
                XCTAssertGreaterThanOrEqual(hypot(center.x - nearest.x, center.y - nearest.y), frame.width / 2 - 0.01, file: file, line: line)
            }
            XCTAssertGreaterThanOrEqual(object.frame.minY, -0.01, file: file, line: line)
        }
    }

    func testОтпущенныйВнутриDockШарВыбираетСвободнуюГраньВышеЗемли() {
        let scene = scene()
        _ = scene.create(.small, at: CGPoint(x: 200, y: 30))
        scene.step(dt: 1 / 60)
        assertOutside(scene, body: CGRect(x: 100, y: 6, width: 300, height: 60))
        XCTAssertEqual(scene.objects[0].center.y, 80, accuracy: 0.01)
        XCTAssertEqual(scene.objects[0].support, 42)
    }

    func testБоковойБросокНеПроходитСквозьТелоDock() throws {
        for fps in [30, 60, 120] {
            let scene = scene()
            let id = try XCTUnwrap(scene.create(.small, at: CGPoint(x: 40, y: 30)))
            scene.beginDragging(id, at: CGPoint(x: 40, y: 30))
            scene.drag(id, to: CGPoint(x: 70, y: 30), dt: 1 / 30)
            scene.endDragging(id)
            for _ in 0..<fps {
                scene.step(dt: 1 / Double(fps))
                assertOutside(scene, body: CGRect(x: 100, y: 6, width: 300, height: 60))
                XCTAssertLessThanOrEqual(scene.objects[0].center.x, 86.01)
            }
        }
    }

    func testУдарСнизуНеПереноситШарНаКрышуDock() throws {
        let scene = scene(y: 100)
        let id = try XCTUnwrap(scene.create(.small, at: CGPoint(x: 200, y: 30)))
        scene.beginDragging(id, at: CGPoint(x: 200, y: 30))
        scene.drag(id, to: CGPoint(x: 200, y: 70), dt: 0.1)
        scene.endDragging(id)
        for _ in 0..<60 {
            scene.step(dt: 1 / 120)
            assertOutside(scene, body: CGRect(x: 100, y: 100, width: 300, height: 60))
            XCTAssertLessThanOrEqual(scene.objects[0].center.y, 86.01)
        }
    }

    func testКрайDockУчитываетКругДажеКогдаЦентрСнаружи() {
        let scene = scene()
        _ = scene.create(.small, at: CGPoint(x: 92, y: 70))
        scene.step(dt: 1 / 60)
        assertOutside(scene, body: CGRect(x: 100, y: 6, width: 300, height: 60))
    }

    func testНевидимыйDockНеМешаетПадению() {
        let scene = scene(visible: false)
        _ = scene.create(.small, at: CGPoint(x: 200, y: 30))
        for _ in 0..<120 { scene.step(dt: 1 / 60) }
        XCTAssertEqual(scene.objects[0].center.y, 14, accuracy: 0.01)
        XCTAssertNil(scene.objects[0].support)
    }
    func testПоявлениеDockБудитЛежащийНаЗемлеШар() {
        let scene = scene(visible: false)
        _ = scene.create(.small, at: CGPoint(x: 200, y: 14))
        for _ in 0..<120 { scene.step(dt: 1 / 60) }
        XCTAssertFalse(scene.isMoving)
        let dock = WindowSurface(id: 42, frame: CGRect(x: 100, y: 6, width: 300, height: 60),
                                 blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: true)
        scene.updateWindows(WindowUpdate(surfaces: [dock], interval: 0.1, parked: [], elsewhere: [], sliding: false, slideVelocity: 0))
        XCTAssertTrue(scene.isMoving)
        scene.step(dt: 1 / 60)
        assertOutside(scene, body: dock.frame)
    }

    func testDockНеОтбираетУправлениеУУдерживаемогоШара() throws {
        let scene = scene()
        let point = CGPoint(x: 200, y: 30)
        let id = try XCTUnwrap(scene.create(.small, at: point))
        scene.beginDragging(id, at: point)
        for _ in 0..<60 { scene.step(dt: 1 / 60) }
        XCTAssertEqual(scene.objects[0].center, point)
        scene.endDragging(id)
        scene.step(dt: 1 / 60)
        assertOutside(scene, body: CGRect(x: 100, y: 6, width: 300, height: 60))
    }

    func testНизкийСлойНеВозвращаетШарВТелоDockИНеПовторяетУдар() {
        for cornerRadius: CGFloat in [0, 20] {
            let scene = WinterScene(width: 800, height: 600)
            let dock = WindowSurface(id: 42, frame: CGRect(x: 100, y: 6, width: 300, height: 60),
                                     blockers: [], cover: [], cornerRadius: cornerRadius, cornerExponent: 2, isDock: true)
            scene.surfaceHeight = { id, _ in id == 42 ? 58 : 0 }
            scene.updateWindows(WindowUpdate(surfaces: [dock], interval: 0.1, parked: [], elsewhere: [], sliding: false, slideVelocity: 0))
            var impacts = 0
            scene.didLand = { _ in impacts += 1 }
            _ = scene.create(radius: 6, at: CGPoint(x: 104, y: 300))
            for _ in 0..<300 { scene.step(dt: 1 / 60) }
            XCTAssertEqual(scene.objects[0].center.y, cornerRadius == 0 ? 72 : 64, accuracy: 0.01)
            XCTAssertFalse(scene.isMoving)
            scene.updateWindows(WindowUpdate(surfaces: [dock], interval: 0.1, parked: [], elsewhere: [], sliding: false, slideVelocity: 0))
            XCTAssertFalse(scene.isMoving)
            let before = impacts
            for _ in 0..<60 { scene.step(dt: 1 / 60) }
            XCTAssertEqual(impacts, before)
            XCTAssertLessThan(impacts, 5)
        }
    }

    func testДеформацияСнегаПослеУдараСохраняетОкруглуюФизическуюОпору() {
        let scene = WinterScene(width: 800, height: 600)
        let dock = WindowSurface(id: 42, frame: CGRect(x: 100, y: 6, width: 300, height: 60),
                                 blockers: [], cover: [], cornerRadius: 20, cornerExponent: 2, isDock: true)
        var snowHeight: CGFloat = 80
        var impacts = 0
        scene.surfaceHeight = { id, _ in id == 42 ? snowHeight : 0 }
        scene.didLand = { _ in snowHeight = 58; impacts += 1 }
        scene.updateWindows(WindowUpdate(surfaces: [dock], interval: 0.1, parked: [], elsewhere: [], sliding: false, slideVelocity: 0))
        _ = scene.create(radius: 6, at: CGPoint(x: 104, y: 90))
        for _ in 0..<300 { scene.step(dt: 1 / 60) }
        XCTAssertEqual(scene.objects[0].center.y, 64, accuracy: 0.01)
        XCTAssertEqual(impacts, 1)
        XCTAssertFalse(scene.isMoving)
    }

}
