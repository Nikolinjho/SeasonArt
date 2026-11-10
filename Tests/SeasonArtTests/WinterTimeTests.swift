import XCTest
import AppKit
@testable import SeasonArt

final class WinterTimeTests: XCTestCase {
    func testДлинныйКадрДогоняетРеальноеВремя() {
        let fine = WinterScene(width: 800, height: 600)
        let coarse = WinterScene(width: 800, height: 600)
        for scene in [fine, coarse] { _ = scene.create(radius: 20, at: CGPoint(x: 300, y: 500)) }
        for _ in 0..<12 { fine.step(dt: 1.0 / 60) }
        coarse.step(dt: 0.2)
        XCTAssertEqual(coarse.objects[0].center.y, fine.objects[0].center.y, accuracy: 0.5,
                       "Задержка кадра не должна замедлять падение")
        XCTAssertLessThan(coarse.objects[0].center.y, 480)
    }

    func testДогонкаОграниченаЧетвертьюСекунды() {
        let capped = WinterScene(width: 800, height: 6000)
        let reference = WinterScene(width: 800, height: 6000)
        for scene in [capped, reference] { _ = scene.create(radius: 20, at: CGPoint(x: 300, y: 5900)) }
        capped.step(dt: 5)
        for _ in 0..<15 { reference.step(dt: 1.0 / 60) }
        XCTAssertEqual(capped.objects[0].center.y, reference.objects[0].center.y, accuracy: 0.5,
                       "После сна шар не пролетает экран за один кадр")
    }

    func testНеподвижнаяСценаПочтиНичегоНеСтоит() {
        let scene = WinterScene(width: 1800, height: 1100)
        for i in 0..<64 {
            _ = scene.create(radius: 14 + CGFloat(i % 4) * 6,
                             at: CGPoint(x: 60 + CGFloat(i % 16) * 105, y: 300 + CGFloat(i / 16) * 120))
        }
        for _ in 0..<600 where scene.isMoving { scene.step(dt: 1.0 / 60) }
        XCTAssertFalse(scene.isMoving)
        let start = CACurrentMediaTime()
        for _ in 0..<60 { scene.step(dt: 1.0 / 60) }
        let perStep = (CACurrentMediaTime() - start) / 60 * 1000
        XCTAssertLessThan(perStep, 2, "Спящие шары не должны проходить полный расчёт")
    }
}
