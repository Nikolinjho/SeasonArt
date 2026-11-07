import AppKit
import XCTest
@testable import SeasonArt

final class WinterRestingSnowTests: XCTestCase {
    private func update(_ surface: WindowSurface) -> WindowUpdate {
        WindowUpdate(surfaces: [surface], interval: 0.1, parked: [], elsewhere: [], sliding: false, slideVelocity: 0)
    }

    func testСвежийСнегНеПоднимаетСтоящегоСнеговика() throws {
        for fps in [30, 60, 120] {
            for support in [0, 1, 2] {
                let scene = WinterScene(width: 800, height: 600)
                var snowTop: CGFloat = 120
                scene.surfaceHeight = { _, _ in snowTop }
                if support != 0 {
                    let surface = WindowSurface(id: 42, frame: CGRect(x: 100, y: 40, width: 500, height: 60),
                                                blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5,
                                                isDock: support == 2)
                    scene.updateWindows(update(surface))
                }
                for (radius, y): (CGFloat, CGFloat) in [(28, 148), (21, 210), (14, 280)] {
                    _ = scene.create(radius: radius, at: CGPoint(x: 300, y: y))
                }
                for _ in 0..<(fps * 3) { scene.step(dt: 1 / Double(fps)) }
                let snowman = try XCTUnwrap(scene.objects.first)
                XCTAssertEqual(scene.objects.count, 1)
                XCTAssertTrue(snowman.isSnowman)
                for delta: CGFloat in [0.2, 1.2, 0.4, 2, 0.6, 4] {
                    snowTop = 120 + delta
                    for _ in 0..<fps { scene.step(dt: 1 / Double(fps)) }
                    XCTAssertEqual(scene.objects[0].center.y, snowman.center.y, accuracy: 0.001,
                                   "Новый снег накапливается вокруг основания и не качает готовую фигуру")
                    XCTAssertFalse(scene.isMoving)
                }
                snowTop = 110
                for _ in 0..<fps { scene.step(dt: 1 / Double(fps)) }
                XCTAssertEqual(scene.objects[0].frame.minY, snowTop, accuracy: 0.001,
                               "При таянии фигура опускается на оставшийся снег")
            }
        }
    }

    func testСнеговикСледуетЗаОкномПослеНакопленияНовогоСнега() throws {
        let scene = WinterScene(width: 800, height: 600)
        var snowTop: CGFloat = 120
        scene.surfaceHeight = { _, _ in snowTop }
        let surface = WindowSurface(id: 42, frame: CGRect(x: 100, y: 40, width: 500, height: 60),
                                    blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: false)
        scene.updateWindows(update(surface))
        _ = scene.create(.large, at: CGPoint(x: 300, y: 148))
        for _ in 0..<180 { scene.step(dt: 1 / 60) }
        let before = try XCTUnwrap(scene.objects.first).center
        snowTop += 4
        scene.step(dt: 1 / 60)
        snowTop += 30
        let moved = WindowSurface(id: 42, frame: surface.frame.offsetBy(dx: 20, dy: 30),
                                  blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: false)
        scene.updateWindows(update(moved))
        XCTAssertEqual(scene.objects[0].center.x, before.x + 20, accuracy: 0.001)
        XCTAssertEqual(scene.objects[0].center.y, before.y + 30, accuracy: 0.001,
                       "Перемещение настоящей опоры сохраняется без подъёма от свежих хлопьев")
    }

    func testПадающийШарНеПоднимаетЗасыпанноеСнегомОснование() throws {
        let scene = WinterScene(width: 800, height: 600)
        var snowTop: CGFloat = 120
        scene.surfaceHeight = { _, _ in snowTop }
        let base = try XCTUnwrap(scene.create(.large, at: CGPoint(x: 300, y: 148)))
        for _ in 0..<180 { scene.step(dt: 1 / 60) }
        let before = try XCTUnwrap(scene.objects.first).center
        snowTop += 4
        _ = scene.create(.small, at: CGPoint(x: 300, y: 350))
        for _ in 0..<180 { scene.step(dt: 1 / 60) }
        XCTAssertEqual(try XCTUnwrap(scene.objects.first { $0.id == base }).center, before,
                       "Контакт с другим шаром не отменяет неподвижность основания под свежим снегом")
    }
}
