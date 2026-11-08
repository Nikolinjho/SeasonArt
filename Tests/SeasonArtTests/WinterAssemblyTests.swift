import AppKit
import XCTest
@testable import SeasonArt

final class WinterAssemblyTests: XCTestCase {
    func testУлыбкаСнеговикаМасштабируетсяИОстаётсяНаГолове() throws {
        for radii: [CGFloat] in [[28, 21, 14], [6, 6, 6], [36, 6, 36], [6, 36, 6]] {
            let object = WinterObject(id: UUID(), radii: radii, center: .zero, velocity: .zero,
                                      support: nil, parked: false, isDragged: false)
            let decoration = try XCTUnwrap(object.decoration)
            let head = try XCTUnwrap(object.ballFrames.last)
            XCTAssertEqual(decoration.mouth.count, 5)
            for dot in decoration.mouth {
                XCTAssertTrue(head.contains(dot))
                XCTAssertLessThan(dot.maxY, head.midY)
                XCTAssertGreaterThan(dot.minY, decoration.scarf[0].maxY)
            }
            XCTAssertLessThan(decoration.mouth[2].midY, decoration.mouth[0].midY)
            XCTAssertEqual(decoration.mouth[0].midX + decoration.mouth[4].midX, head.midX * 2, accuracy: 0.001)
        }
    }

    private func advance(_ scene: WinterScene, seconds: Double = 3, fps: Int = 60) {
        for _ in 0..<Int(seconds * Double(fps)) { scene.step(dt: 1 / Double(fps)) }
    }

    func testТриОтдельныхШараСобираютсяПослеПосадкиДругНаДруга() throws {
        for fps in [30, 60, 120] {
            let scene = WinterScene(width: 800, height: 600)
            let base = try XCTUnwrap(scene.create(radius: 28, at: CGPoint(x: 300, y: 28)))
            _ = scene.create(radius: 21, at: CGPoint(x: 300, y: 90))
            _ = scene.create(radius: 14, at: CGPoint(x: 300, y: 160))
            advance(scene, fps: fps)
            XCTAssertEqual(scene.objects.count, 1, "Сборка срабатывает после посадки, а не только при отпускании мыши")
            let snowman = try XCTUnwrap(scene.objects.first)
            XCTAssertEqual(snowman.id, base)
            XCTAssertEqual(snowman.radii, [28, 21, 14])
            XCTAssertNotNil(snowman.decoration)
            XCTAssertFalse(snowman.arms.isEmpty)
            XCTAssertEqual(snowman.frame.height, 105, accuracy: 0.01)
            XCTAssertFalse(scene.isMoving)
        }
    }

    func testГоловаОпущеннаяНаПаруСобираетСнеговикаПослеОтпускания() throws {
        let scene = WinterScene(width: 800, height: 600)
        _ = scene.create(.large, at: CGPoint(x: 300, y: 28))
        let torso = try XCTUnwrap(scene.create(.medium, at: CGPoint(x: 300, y: 77)))
        scene.beginDragging(torso, at: CGPoint(x: 300, y: 77))
        scene.endDragging(torso)
        let top = scene.objects[0].frame.maxY
        let start = CGPoint(x: 300, y: top + 40)
        let head = try XCTUnwrap(scene.create(.small, at: start))
        scene.beginDragging(head, at: start)
        scene.drag(head, to: CGPoint(x: 300, y: top + 24), dt: 0.1)
        scene.endDragging(head)
        XCTAssertEqual(scene.objects.count, 2, "Отпускание ещё не требует точного контакта")
        advance(scene)
        XCTAssertEqual(scene.objects.count, 1)
        XCTAssertTrue(scene.objects[0].isSnowman)
    }

    func testГлубокоУстановленныйШарПринимаетсяВСтык() throws {
        let scene = WinterScene(width: 800, height: 600)
        _ = scene.create(.large, at: CGPoint(x: 300, y: 28))
        let point = CGPoint(x: 300, y: 56 + 14 - 14 * 0.8)
        let id = try XCTUnwrap(scene.create(.small, at: point))
        scene.beginDragging(id, at: point)
        scene.endDragging(id)
        XCTAssertEqual(scene.objects.count, 1)
    }

    func testКороткоеКасаниеИУдерживаемаяГоловаНеЗавершаютСборку() throws {
        let scene = WinterScene(width: 800, height: 600)
        _ = scene.create(.large, at: CGPoint(x: 300, y: 28))
        _ = scene.create(.medium, at: CGPoint(x: 300, y: 77))
        let head = try XCTUnwrap(scene.create(.small, at: CGPoint(x: 300, y: 112)))
        advance(scene, seconds: 0.1)
        XCTAssertEqual(scene.objects.count, 3)
        XCTAssertTrue(scene.isMoving, "Проверка устойчивой стопки сохраняет частый таймер")
        scene.beginDragging(head, at: scene.objects.first { $0.id == head }!.center)
        advance(scene)
        XCTAssertEqual(scene.objects.count, 3, "Сборка ждёт отпускания удерживаемого шара")
    }

    func testЧетвёртыйШарОстаётсяОтдельнымПослеСборкиНижнихТрёх() {
        let scene = WinterScene(width: 800, height: 600)
        for (radius, y): (CGFloat, CGFloat) in [(28, 28), (21, 77), (14, 112), (6, 132)] {
            _ = scene.create(radius: radius, at: CGPoint(x: 300, y: y))
        }
        advance(scene)
        XCTAssertEqual(scene.objects.count, 2)
        XCTAssertEqual(scene.objects.map(\.radii.count).sorted(), [1, 3])
        XCTAssertFalse(scene.isMoving)
    }

    func testШарфНеЗакрываетВерхнююПуговицуПослеУглубленияСтыка() throws {
        for radii: [CGFloat] in [[28, 21, 14], [6, 6, 6], [36, 6, 18]] {
            let object = WinterObject(id: UUID(), radii: radii, center: .zero, velocity: .zero,
                                      support: nil, parked: false, isDragged: false)
            let decoration = try XCTUnwrap(object.decoration)
            XCTAssertLessThan(decoration.buttons[0].maxY, decoration.scarf[0].minY)
        }
    }
}
