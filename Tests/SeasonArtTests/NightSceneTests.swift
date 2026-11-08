import CoreGraphics
import simd
import XCTest
@testable import SeasonArt

final class NightSceneTests: XCTestCase {
    private let away = SIMD2<Float>(-10_000, -10_000)

    private func advance(_ scene: NightScene, seconds: Int, fps: Int = 60,
                         cursor: SIMD2<Float>? = nil, intensity: Float = 1,
                         supports: [NightSupport] = []) {
        for _ in 0..<(seconds * fps) {
            scene.step(dt: 1 / Float(fps), intensity: intensity, cursor: cursor ?? away, supports: supports)
        }
    }

    func testНеподвижныйУказательСобираетОгонькиАВнешнийНеПритягивает() {
        let attracted = NightScene(width: 800, height: 600, seed: 42)
        let free = NightScene(width: 800, height: 600, seed: 42)
        attracted.mode = .fireflies
        free.mode = .fireflies
        let cursor = SIMD2<Float>(400, 300)
        advance(attracted, seconds: 10, cursor: cursor)
        advance(free, seconds: 10)
        func distance(_ scene: NightScene) -> Float {
            scene.sprites.reduce(0) { $0 + simd_distance($1.position, cursor) } / Float(scene.sprites.count)
        }
        XCTAssertFalse(attracted.sprites.isEmpty)
        XCTAssertLessThan(distance(attracted), distance(free) * 0.8)
        XCTAssertTrue(attracted.sprites.allSatisfy { $0.glow > 0 && $0.trail == 0 })
    }

    func testДвижущийсяУказательНеВключаетПритяжение() {
        let moving = NightScene(width: 800, height: 600, seed: 11)
        let free = NightScene(width: 800, height: 600, seed: 11)
        moving.mode = .fireflies
        free.mode = .fireflies
        for i in 0..<600 {
            moving.step(dt: 1 / 60, intensity: 1, cursor: SIMD2(Float(i % 2) * 400 + 200, 300), supports: [])
            free.step(dt: 1 / 60, intensity: 1, cursor: away, supports: [])
        }
        XCTAssertEqual(moving.sprites.map(\.position), free.sprites.map(\.position))
    }

    func testТраекторииОдинаковыПриРазнойЧастотеКадров() {
        for mode: Mode in [.fireflies, .starfall] {
            var frames: [[Sprite]] = []
            for fps in [30, 60, 120] {
                let scene = NightScene(width: 800, height: 600, seed: 99)
                scene.mode = mode
                advance(scene, seconds: 5, fps: fps)
                frames.append(scene.sprites)
            }
            XCTAssertFalse(frames[0].isEmpty)
            for result in frames.dropFirst() {
                XCTAssertEqual(result.count, frames[0].count)
                for (a, b) in zip(frames[0], result) {
                    XCTAssertLessThan(simd_distance(a.position, b.position), 0.01)
                }
            }
        }
    }

    func testМетеорРазбиваетсяНаДоступнойОпореИНепроходитСквозьНеё() {
        let scene = NightScene(width: 800, height: 600, seed: 6)
        scene.mode = .starfall
        let shelf = NightSupport(left: 0, right: 800, y: 300)
        var sparksAboveGround = false
        for _ in 0..<300 {
            scene.step(dt: 1 / 30, intensity: 1, cursor: away, supports: [shelf])
            sparksAboveGround = sparksAboveGround || scene.sprites.contains { $0.trail == 0 && $0.position.y > 250 }
            XCTAssertFalse(scene.sprites.contains { $0.trail > 0 && $0.position.y < 300 && $0.position.x >= 0 && $0.position.x < 800 })
        }
        XCTAssertTrue(sparksAboveGround)
    }

    func testВыключениеИСменаРежимаНеОставляютОгоньковИСледов() {
        let scene = NightScene(width: 800, height: 600, seed: 9)
        for mode: Mode in [.fireflies, .starfall] {
            scene.mode = mode
            advance(scene, seconds: 2)
            XCTAssertFalse(scene.sprites.isEmpty)
            scene.step(dt: 1 / 60, intensity: 0, cursor: away, supports: [])
            XCTAssertTrue(scene.sprites.isEmpty)
        }
        scene.mode = .snow
        advance(scene, seconds: 1)
        XCTAssertTrue(scene.sprites.isEmpty)
    }

    func testИнтенсивностьОграничиваетКоличествоАНекорректноеВремяНеМеняетКадр() {
        let scene = NightScene(width: 800, height: 600, seed: 7)
        scene.mode = .fireflies
        advance(scene, seconds: 1, intensity: 0.4)
        let light = scene.sprites.count
        advance(scene, seconds: 1, intensity: 2)
        XCTAssertGreaterThan(scene.sprites.count, light)
        advance(scene, seconds: 1, intensity: 1_000)
        XCTAssertLessThanOrEqual(scene.sprites.count, 160)
        let positions = scene.sprites.map(\.position)
        for dt: Float in [.nan, .infinity, -1, 0] {
            scene.step(dt: dt, intensity: 1, cursor: away, supports: [])
            XCTAssertEqual(scene.sprites.map(\.position), positions)
        }
        scene.resize(width: 100, height: 80)
        advance(scene, seconds: 1)
        XCTAssertTrue(scene.sprites.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite })
    }
}
