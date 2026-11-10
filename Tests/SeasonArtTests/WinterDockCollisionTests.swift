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

    /// Видимый силуэт шаров снаружи корпуса и не ниже земли. Допуск покрывает многоугольник смятого шара.
    private func assertOutside(_ scene: WinterScene, body: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        for object in scene.objects where !object.parked {
            for index in object.ballFrames.indices {
                for point in object.outline(for: index) {
                    let x = object.frame.minX + point.x
                    let y = object.frame.minY + point.y
                    let depth = min(x - body.minX, body.maxX - x, y - body.minY, body.maxY - y)
                    XCTAssertLessThanOrEqual(depth, 0.6, file: file, line: line)
                }
            }
            XCTAssertGreaterThanOrEqual(object.visibleBottom, -0.6, file: file, line: line)
        }
    }

    func testУвеличенныйDockОтталкиваетЛежащийРядомШар() throws {
        let scene = scene()
        var presented = CGRect(x: 100, y: 6, width: 300, height: 60)
        scene.dockBody = { _ in presented }
        let id = try XCTUnwrap(scene.create(.small, at: CGPoint(x: 420, y: 14)))
        for _ in 0..<60 { scene.step(dt: 1 / 60) }
        XCTAssertFalse(scene.isMoving)
        // Наведение расширяет Dock за несколько кадров.
        for step in 1...8 {
            presented = CGRect(x: 100 - CGFloat(step) * 5, y: 6, width: 300 + CGFloat(step) * 10, height: 60)
            scene.synchronizeDockSupports()
            scene.step(dt: 1 / 60)
        }
        for _ in 0..<60 { scene.step(dt: 1 / 60) }
        let ball = try XCTUnwrap(scene.objects.first { $0.id == id })
        XCTAssertGreaterThanOrEqual(ball.frame.minX, presented.maxX - 0.5, "Грань увеличенного Dock сдвигает шар")
        assertOutside(scene, body: presented)
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
        XCTAssertEqual(scene.objects[0].visibleBottom, 0, accuracy: 0.6)
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
        let point = CGPoint(x: 200, y: 120)
        let id = try XCTUnwrap(scene.create(.small, at: point))
        scene.beginDragging(id, at: point)
        for _ in 0..<60 { scene.step(dt: 1 / 60) }
        XCTAssertEqual(scene.objects[0].center, point, "Dock не захватывает шар в руке")
        scene.drag(id, to: CGPoint(x: 350, y: 120), dt: 1 / 60)
        XCTAssertEqual(scene.objects[0].center, CGPoint(x: 350, y: 120), "Над Dock шар идёт за курсором")
        scene.drag(id, to: CGPoint(x: 350, y: 30), dt: 1 / 60)
        scene.step(dt: 1 / 60)
        XCTAssertGreaterThanOrEqual(scene.objects[0].center.y, 80 - 0.6, "Твёрдый корпус Dock не пускает шар в руке внутрь")
        scene.endDragging(id, idleTime: 0.2)
        for _ in 0..<60 { scene.step(dt: 1 / 60) }
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
            // На скруглённом углу шар скатывается по физике, а не стоит на склоне.
            assertOutside(scene, body: dock.frame)
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
        _ = scene.create(radius: 6, at: CGPoint(x: 200, y: 90))
        for _ in 0..<300 { scene.step(dt: 1 / 60) }
        XCTAssertEqual(scene.objects[0].visibleBottom, 66, accuracy: 0.6, "Снег ниже крыши: шар лежит на корпусе")
        XCTAssertEqual(impacts, 1)
        XCTAssertFalse(scene.isMoving)
    }

    func testВесьКругЛежитНадОкруглымТеломDock() {
        for exponent: CGFloat in [2, 2.5] {
            for radius: CGFloat in [6, 36] {
                for x: CGFloat in [104, 396] {
                    let scene = WinterScene(width: 800, height: 600)
                    let dock = WindowSurface(id: 42, frame: CGRect(x: 100, y: 6, width: 300, height: 60),
                                             blockers: [], cover: [], cornerRadius: 20, cornerExponent: exponent, isDock: true)
                    scene.surfaceHeight = { id, _ in id == 42 ? 46 : 0 }
                    scene.updateWindows(WindowUpdate(surfaces: [dock], interval: 0.1, parked: [], elsewhere: [], sliding: false, slideVelocity: 0))
                    _ = scene.create(radius: radius, at: CGPoint(x: x, y: 300))
                    for _ in 0..<300 { scene.step(dt: 1 / 60) }
                    let object = scene.objects[0]
                    for sample in 0...200 {
                        let sampleX = object.center.x - radius + 2 * radius * CGFloat(sample) / 200
                        guard sampleX >= 100, sampleX <= 400 else { continue }
                        let d = min(sampleX - 100, 400 - sampleX)
                        let u = max(0, 1 - d / 20)
                        let roof = 46 + 20 * pow(max(0, 1 - pow(u, exponent)), 1 / exponent)
                        let ballBottom = object.center.y - sqrt(max(0, radius * radius - pow(sampleX - object.center.x, 2)))
                        XCTAssertGreaterThanOrEqual(ballBottom, roof - 0.01)
                    }
                    XCTAssertFalse(scene.isMoving)
                }
            }
        }
    }

}
