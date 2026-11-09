import AppKit
import XCTest
@testable import SeasonArt

final class WinterBallDamageTests: XCTestCase {
    private func dropped(from height: CGFloat, fps: Int = 60) -> WinterObject {
        let scene = WinterScene(width: 600, height: 600)
        scene.create(.large, at: CGPoint(x: 200, y: height))
        for _ in 0..<(fps * 4) { scene.step(dt: 1 / Double(fps)) }
        return scene.objects[0]
    }

    func testСильноеПадениеОставляетПостояннуюВмятину() {
        for fps in [30, 60, 120] {
            let ball = dropped(from: 450, fps: fps)
            XCTAssertGreaterThan(ball.damage(for: 0).depth, 0.05)
            XCTAssertEqual(ball.outline(for: 0).map(\.y).min()!, 0, accuracy: 0.01,
                           "Сплющенный низ остаётся на опоре")
            XCTAssertLessThan(ball.outline(for: 0).map(\.y).max()!, 56,
                              "После удара шар перестаёт быть идеальным кругом")
        }
    }

    func testАккуратнаяПостановкаНеПовреждаетШар() {
        XCTAssertEqual(dropped(from: 28).damage(for: 0).depth, 0)
        XCTAssertEqual(dropped(from: 30).damage(for: 0).depth, 0)
        XCTAssertLessThan(dropped(from: 65).damage(for: 0).depth, dropped(from: 450).damage(for: 0).depth)
    }

    func testПадениеНаДругойШарТожеОставляетВмятину() throws {
        let scene = WinterScene(width: 600, height: 600)
        scene.create(.large, at: CGPoint(x: 200, y: 28))
        for _ in 0..<60 { scene.step(dt: 1 / 60) }
        let id = try XCTUnwrap(scene.create(.medium, at: CGPoint(x: 200, y: 450)))
        for _ in 0..<240 { scene.step(dt: 1 / 60) }
        let ball = try XCTUnwrap(scene.objects.first { $0.id == id })
        XCTAssertGreaterThan(ball.damage(for: 0).depth, 0)
    }

    func testВторойШарЛежитНаСмятойВерхушкеБезЗазора() throws {
        let scene = WinterScene(width: 600, height: 600)
        let baseID = try XCTUnwrap(scene.create(.large, at: CGPoint(x: 200, y: 450)))
        for _ in 0..<240 { scene.step(dt: 1 / 60) }
        let topID = try XCTUnwrap(scene.create(.medium, at: CGPoint(x: 200, y: 450)))
        for _ in 0..<240 { scene.step(dt: 1 / 60) }
        let base = try XCTUnwrap(scene.objects.first { $0.id == baseID })
        let top = try XCTUnwrap(scene.objects.first { $0.id == topID })
        let roof = base.frame.minY + base.outline(for: 0).map(\.y).max()!
        let bottom = top.frame.minY + top.outline(for: 0).map(\.y).min()!
        XCTAssertEqual(bottom, roof, accuracy: 0.1, "Смятый силуэт участвует в контакте шаров")
        XCTAssertFalse(scene.isMoving)
    }

    func testПокойНеВызываетПовторногоПоврежденияИОсыпания() {
        let scene = WinterScene(width: 600, height: 600)
        var bursts = 0
        scene.didChip = { _ in bursts += 1 }
        scene.create(.large, at: CGPoint(x: 200, y: 450))
        for _ in 0..<240 { scene.step(dt: 1 / 60) }
        let damage = scene.objects[0].damage(for: 0)
        let initialBursts = bursts
        XCTAssertGreaterThan(initialBursts, 0)
        for _ in 0..<240 { scene.step(dt: 1 / 60) }
        XCTAssertEqual(scene.objects[0].damage(for: 0), damage)
        XCTAssertEqual(bursts, initialBursts)
    }

    func testРисунокМеняетсяПриПоврежденииНеподвижногоШара() throws {
        _ = NSApplication.shared
        let ball = dropped(from: 450)
        var intact = ball
        intact.ballDamage = []
        let window = WinterObjectWindow(object: intact, screenFrame: .zero)
        defer { window.close() }
        let view = try XCTUnwrap(window.contentView as? WinterObjectView)
        view.needsDisplay = false
        view.display(object: ball)
        XCTAssertTrue(view.needsDisplay)
    }

    func testНастоящийРендерПоказываетСмятиеИСколы() throws {
        let ball = dropped(from: 450)
        var intact = ball
        intact.ballDamage = []
        func render(_ object: WinterObject) throws -> NSBitmapImageRep {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 168, pixelsHigh: 168,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
            NSGraphicsContext.current?.cgContext.scaleBy(x: 3, y: 3)
            let view = WinterObjectView(object: object)
            view.draw(view.bounds)
            NSGraphicsContext.current?.flushGraphics()
            return bitmap
        }
        let before = try render(intact)
        let after = try render(ball)
        var missing = 0
        for y in 0..<168 {
            for x in 0..<168 {
                let a = before.colorAt(x: x, y: y)!.alphaComponent
                let b = after.colorAt(x: x, y: y)!.alphaComponent
                if a > 0.9 && b < 0.1 { missing += 1 }
            }
        }
        XCTAssertGreaterThan(missing, 200, "Повреждение меняет видимый силуэт, а не только состояние модели")
        if let directory = ProcessInfo.processInfo.environment["SEASONART_DAMAGE_PREVIEW"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try before.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory + "/intact.png"))
            try after.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory + "/damaged.png"))
        }
    }

    func testПовторныеУдарыОграниченыИНеДаютБесконечногоОсыпания() {
        var damage = WinterBallDamage()
        for _ in 0..<100 { _ = damage.hit(speed: 900, angle: -.pi / 2) }
        XCTAssertLessThanOrEqual(damage.depth, 0.32)
        XCTAssertEqual(damage.hit(speed: 900, angle: -.pi / 2), 0)
        let points = damage.contour(in: CGRect(x: 0, y: 0, width: 56, height: 56), rotation: .pi)
        XCTAssertTrue(points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.y >= 0 })
    }

    func testВмятинаСохраняетНаправлениеПослеСборки() throws {
        let scene = WinterScene(width: 800, height: 600)
        let base = try XCTUnwrap(scene.create(.large, at: CGPoint(x: 200, y: 28)))
        let upper = try XCTUnwrap(scene.create(.medium, at: CGPoint(x: 500, y: 450)))
        for _ in 0..<240 { scene.step(dt: 1 / 60) }
        let fallen = try XCTUnwrap(scene.objects.first { $0.id == upper })
        XCTAssertGreaterThan(fallen.damage(for: 0).depth, 0)
        // Качение меняет угол шара перед сборкой.
        scene.beginDragging(upper, at: fallen.center)
        scene.drag(upper, to: CGPoint(x: 450, y: 21), dt: 0.1)
        scene.endDragging(upper)
        for _ in 0..<60 { scene.step(dt: 1 / 60) }
        let rolled = try XCTUnwrap(scene.objects.first { $0.id == upper })
        XCTAssertNotEqual(rolled.rotation, 0)
        let before = rolled.outline(for: 0)
        scene.beginDragging(upper, at: rolled.center)
        scene.drag(upper, to: CGPoint(x: 200, y: 77), dt: 0.1)
        scene.endDragging(upper, idleTime: 0.2)
        let stack = try XCTUnwrap(scene.objects.first { $0.id == base })
        XCTAssertEqual(stack.radii.count, 2)
        XCTAssertEqual(stack.damage(for: 1).depth, rolled.damage(for: 0).depth)
        let after = stack.outline(for: 1)
        for index in before.indices {
            XCTAssertEqual(before[index].x - rolled.ballFrames[0].midX,
                           after[index].x - stack.ballFrames[1].midX, accuracy: 0.001)
            XCTAssertEqual(before[index].y - rolled.ballFrames[0].minY,
                           after[index].y - stack.ballFrames[1].minY, accuracy: 0.001)
        }
    }
}
