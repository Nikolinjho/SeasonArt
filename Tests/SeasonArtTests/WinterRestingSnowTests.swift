import AppKit
import XCTest
@testable import SeasonArt

final class WinterRestingSnowTests: XCTestCase {
    private func update(_ surface: WindowSurface) -> WindowUpdate {
        WindowUpdate(surfaces: [surface], interval: 0.1, parked: [], elsewhere: [], sliding: false, slideVelocity: 0)
    }

    func testЛежащийСнеговикПлавноПоднимаетсяНадСвежимСнегом() throws {
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
                XCTAssertEqual(snowman.visibleBottom, winterRestingBottom(snow: 120, radius: 28), accuracy: 0.6,
                               "Снеговик утоплен в снег на 15% радиуса основания")
                for delta: CGFloat in [0.2, 1.2, 0.4, 2, 0.6] {
                    snowTop = 120 + delta
                    for _ in 0..<fps { scene.step(dt: 1 / Double(fps)) }
                    XCTAssertEqual(scene.objects[0].center.y, snowman.center.y, accuracy: 0.001,
                                   "Рост снега в мёртвой зоне 2 pt не качает фигуру")
                    XCTAssertFalse(scene.isMoving)
                }
                snowTop = 140
                var previous = scene.objects[0].center.y
                var fastest: CGFloat = 0
                for _ in 0..<(fps * 5) {
                    scene.step(dt: 1 / Double(fps))
                    fastest = max(fastest, (scene.objects[0].center.y - previous) * CGFloat(fps))
                    previous = scene.objects[0].center.y
                }
                XCTAssertLessThanOrEqual(fastest, 8.5, "Фигура поднимается плавно, не быстрее 8 pt/с")
                XCTAssertEqual(scene.objects[0].visibleBottom, winterRestingBottom(snow: 140, radius: 28), accuracy: 0.6,
                               "После подъёма фигура снова утоплена на 15% радиуса")
                XCTAssertFalse(scene.isMoving)
                snowTop = 110
                for _ in 0..<fps { scene.step(dt: 1 / Double(fps)) }
                XCTAssertEqual(scene.objects[0].visibleBottom,
                               winterRestingBottom(snow: 110, bed: support == 0 ? 0 : 100, radius: 28), accuracy: 0.6,
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
        snowTop += 1
        scene.step(dt: 1 / 60)
        snowTop += 30
        let moved = WindowSurface(id: 42, frame: surface.frame.offsetBy(dx: 20, dy: 30),
                                  blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: false)
        scene.updateWindows(update(moved))
        XCTAssertEqual(scene.objects[0].center.x, before.x + 20, accuracy: 0.001)
        XCTAssertEqual(scene.objects[0].center.y, before.y + 30, accuracy: 0.001,
                       "Перемещение настоящей опоры сохраняется без скачка от свежих хлопьев")
    }

    func testСтопкаПоднимаетсяНадСнегомЦеликом() throws {
        let scene = WinterScene(width: 800, height: 600)
        var snowTop: CGFloat = 120
        scene.surfaceHeight = { _, _ in snowTop }
        let base = try XCTUnwrap(scene.create(.large, at: CGPoint(x: 300, y: 144)))
        for _ in 0..<60 { scene.step(dt: 1 / 60) }
        let top = try XCTUnwrap(scene.create(.small, at: CGPoint(x: 300, y: 185)))
        for _ in 0..<180 { scene.step(dt: 1 / 60) }
        XCTAssertEqual(scene.objects.count, 2, "Пара остаётся двумя шарами до третьего")
        let lower = try XCTUnwrap(scene.objects.first { $0.id == base })
        snowTop = 140
        for _ in 0..<(60 * 5) { scene.step(dt: 1 / 60) }
        let raised = try XCTUnwrap(scene.objects.first { $0.id == base })
        let upper = try XCTUnwrap(scene.objects.first { $0.id == top })
        XCTAssertEqual(raised.center.y - lower.center.y, 20, accuracy: 0.6, "Основание поднялось вместе со снегом")
        XCTAssertEqual(upper.visibleBottom, raised.visibleTop, accuracy: 0.6, "Верхний шар поднялся вместе с основанием")
        XCTAssertEqual(upper.center.x, raised.center.x, accuracy: 1)
        XCTAssertFalse(scene.isMoving)
    }
}
