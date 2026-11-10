import AppKit
import XCTest
@testable import SeasonArt

final class WinterImpactTests: XCTestCase {
    private func fixture(support: CGWindowID? = nil, dock: Bool = false) throws -> (SnowSimulation, SnowLayer) {
        let simulation = SnowSimulation(width: 600, height: 500, snowfall: .off)
        if let support {
            simulation.updateWindows([WindowSurface(id: support,
                frame: CGRect(x: 80, y: 0, width: 400, height: 100), blockers: [], cover: [],
                cornerRadius: 0, cornerExponent: 2.5, isDock: dock)], interval: 1 / 60)
        }
        let fields = Mirror(reflecting: simulation).children
        let layer: SnowLayer
        if let support {
            let ledges = try XCTUnwrap(fields.first { $0.label == "ledges" }?.value as? [CGWindowID: SnowLayer])
            layer = try XCTUnwrap(ledges[support])
        } else {
            layer = try XCTUnwrap(fields.first { $0.label == "ground" }?.value as? SnowLayer)
        }
        layer.replace(heights: layer.heights.map { _ in 30 })
        layer.refreshTop()
        return (simulation, layer)
    }

    private func impact(_ simulation: SnowSimulation, support: CGWindowID? = nil,
                        x: CGFloat = 240, radius: CGFloat = 14, mass: CGFloat = 1,
                        speed: CGFloat = 400) {
        simulation.displaceSnow(for: WinterImpact(support: support, x: x, radius: radius, mass: mass,
                                                 velocity: CGVector(dx: 50, dy: -speed)))
    }

    private func particles(_ simulation: SnowSimulation) -> [(area: Float, velocity: SIMD2<Float>)] {
        let grains = Mirror(reflecting: simulation).children.first { $0.label == "grains" }!.value
        return Mirror(reflecting: grains).children.map { child in
            let fields = Mirror(reflecting: child.value).children
            return (fields.first { $0.label == "area" }!.value as! Float,
                    fields.first { $0.label == "velocity" }!.value as! SIMD2<Float>)
        }
    }

    private func area(_ layer: SnowLayer) -> Float { layer.heights.reduce(0, +) * layer.columnWidth }

    func testУдарЛокаленСохраняетМассуИВыталкиваетСнегВОбеСтороны() throws {
        for (support, dock) in [(Optional<CGWindowID>.none, false), (42, true), (43, false)] {
            let (simulation, layer) = try fixture(support: support, dock: dock)
            let before = layer.heights
            let initial = area(layer) + particles(simulation).reduce(0) { $0 + $1.area }
            impact(simulation, support: support)
            let center = try XCTUnwrap(layer.index(at: 240))
            XCTAssertLessThan(layer.heights[center], before[center])
            XCTAssertGreaterThan(layer.heights[center - 9], before[center - 9])
            XCTAssertGreaterThan(layer.heights[center + 9], before[center + 9])
            for i in layer.heights.indices where abs(layer.centerX(i) - 240) > 23 {
                XCTAssertEqual(layer.heights[i], before[i], "Удалённые колонки сохраняются")
            }
            let grains = particles(simulation)
            XCTAssertTrue(grains.contains { $0.velocity.x < 0 && $0.velocity.y > 0 })
            XCTAssertTrue(grains.contains { $0.velocity.x > 0 && $0.velocity.y > 0 })
            XCTAssertEqual(area(layer) + grains.reduce(0) { $0 + $1.area }, initial, accuracy: 0.05)
        }
    }

    func testБольшаяСкоростьИРазмерУсиливаютУдар() throws {
        var removals: [Float] = []
        var velocities: [Float] = []
        for (radius, mass, speed): (CGFloat, CGFloat, CGFloat) in [(14, 1, 200), (14, 1, 600), (28, 8, 600)] {
            let (simulation, layer) = try fixture()
            let before = layer.heights
            impact(simulation, radius: radius, mass: mass, speed: speed)
            removals.append(zip(before, layer.heights).reduce(0) { $0 + max(0, $1.0 - $1.1) })
            velocities.append(particles(simulation).map { $0.velocity.y }.max() ?? 0)
        }
        XCTAssertLessThan(removals[0], removals[1])
        XCTAssertLessThan(removals[1], removals[2])
        XCTAssertLessThan(velocities[0], velocities[1])
        XCTAssertLessThan(velocities[1], velocities[2])
    }

    func testСнеговикПроминаетБольшеСнегаЧемБольшойШарПриРавнойСкорости() throws {
        var volumes: [Float] = []
        for mass: CGFloat in [8, 8 + 3.375 + 1] {
            let (simulation, layer) = try fixture()
            layer.replace(heights: layer.heights.map { _ in 100 })
            let before = layer.heights
            impact(simulation, radius: 28, mass: mass, speed: 600)
            volumes.append(zip(before, layer.heights).reduce(0) {
                $0 + max(0, $1.0 - $1.1) * layer.columnWidth
            })
        }
        XCTAssertGreaterThan(volumes[1], volumes[0], "Состав снеговика усиливает проминание при том же радиусе основания")
    }

    func testНеверныеКоординатыПустотаИСнятаяОпораНеМеняютСнег() throws {
        let (simulation, layer) = try fixture(support: 42, dock: true)
        let before = layer.heights
        for value: CGFloat in [.nan, .infinity, -.infinity, 1e100, -1e100] {
            impact(simulation, support: 42, x: value)
            impact(simulation, support: 42, radius: value)
            impact(simulation, support: 42, mass: value)
            impact(simulation, support: 42, speed: value)
        }
        impact(simulation, support: 99)
        impact(simulation, support: 42, speed: 0)
        XCTAssertEqual(layer.heights, before)
        simulation.mode = .autumn
        impact(simulation, support: 42)
        XCTAssertEqual(layer.heights, before)
        simulation.mode = .snow
        layer.replace(heights: before.map { _ in 0 })
        impact(simulation, support: 42)
        XCTAssertEqual(area(layer), 0)
        XCTAssertTrue(particles(simulation).isEmpty)
        simulation.updateWindows([], interval: 1 / 60)
        impact(simulation, support: 42)
        XCTAssertEqual(area(layer), 0)
    }

    func testПерекрытыеКолонкиНеУчаствуютВПереносе() throws {
        let (simulation, layer) = try fixture(support: 42, dock: true)
        layer.occluders = [SIMD4(240, 0, 300, 500)]
        let before = layer.heights
        impact(simulation, support: 42)
        XCTAssertEqual(layer.heights, before, "Скрытый центр не получает удар")
        impact(simulation, support: 42, x: 232)
        for i in layer.heights.indices where layer.centerX(i) >= 240 {
            XCTAssertEqual(layer.heights[i], before[i], "Перенос останавливается перед перекрытием")
        }
    }

    func testУдарПоDockНеТрогаетСнегЗемлиИСкрытаяЗемляНеПроминается() throws {
        let (simulation, layer) = try fixture(support: 42, dock: true)
        let ground = try XCTUnwrap(Mirror(reflecting: simulation).children.first { $0.label == "ground" }?.value as? SnowLayer)
        ground.replace(heights: ground.heights.map { _ in 20 })
        ground.refreshTop()
        let before = ground.heights
        impact(simulation, support: 42)
        XCTAssertEqual(ground.heights, before)
        let dockBefore = layer.heights
        impact(simulation)
        XCTAssertEqual(ground.heights, before, "Земля под телом Dock скрыта")
        XCTAssertEqual(layer.heights, dockBefore, "Удар по земле не выбирает другой слой")
    }

    func testКраяИЗаполненныйБюджетНеПереносятСнегНаДругуюОпору() throws {
        for x: CGFloat in [81, 479] {
            let (simulation, layer) = try fixture(support: 42, dock: true)
            // Каждый удар выпускает восемь частиц, слой восстанавливается без шага времени.
            for _ in 0..<1500 {
                impact(simulation, support: 42)
                layer.replace(heights: layer.heights.map { _ in 30 })
            }
            let count = particles(simulation).count
            XCTAssertEqual(count, 12_000)
            let ground = Mirror(reflecting: simulation).children.first { $0.label == "ground" }!.value as! SnowLayer
            let groundBefore = ground.heights
            let total = area(layer)
            impact(simulation, support: 42, x: x)
            XCTAssertEqual(area(layer), total, accuracy: 0.05)
            XCTAssertEqual(particles(simulation).count, count)
            XCTAssertEqual(ground.heights, groundBefore)
            XCTAssertTrue(layer.heights.allSatisfy { $0.isFinite && $0 >= 0 })
            layer.occluders = [SIMD4(0, 0, 240, 500), SIMD4(242, 0, 600, 500)]
            let isolated = layer.heights
            impact(simulation, support: 42, x: 241)
            XCTAssertEqual(layer.heights, isolated, "Без бокового места и бюджета снег остаётся на месте")
        }
    }

    func testПропавшаяОпораНеИзменяетСохранённыйСлой() throws {
        let (simulation, layer) = try fixture(support: 42, dock: true)
        simulation.updateWindows([], interval: 1 / 60)
        let before = layer.heights
        let grains = particles(simulation).reduce(0) { $0 + $1.area }
        impact(simulation, support: 42)
        XCTAssertEqual(layer.heights, before)
        XCTAssertEqual(particles(simulation).reduce(0) { $0 + $1.area }, grains)
    }

    func testПрипаркованныйШарНеПовторяетУдар() {
        let scene = WinterScene(width: 600, height: 500)
        let surface = WindowSurface(id: 42, frame: CGRect(x: 80, y: 0, width: 400, height: 100),
                                    blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: true)
        scene.updateWindows(WindowUpdate(surfaces: [surface], interval: 0.1, parked: [], elsewhere: [], sliding: false, slideVelocity: 0))
        var events: [WinterImpact] = []
        scene.didLand = { events.append($0) }
        _ = scene.create(.small, at: CGPoint(x: 240, y: 300))
        for _ in 0..<180 { scene.step(dt: 1 / 60) }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].support, 42)
        scene.updateWindows(WindowUpdate(surfaces: [], interval: 0.1, parked: [42], elsewhere: [], sliding: false, slideVelocity: 0))
        for _ in 0..<180 { scene.step(dt: 1 / 60) }
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(scene.objects[0].parked)
    }

    func testСобытиеСодержитСкоростьДоОстановкиИМассуСнеговика() throws {
        let scene = WinterScene(width: 600, height: 500)
        var events: [WinterImpact] = []
        var height: CGFloat = 30
        scene.surfaceHeight = { _, _ in height }
        scene.didLand = { events.append($0); height = 20 }
        let base = try XCTUnwrap(scene.create(.large, at: CGPoint(x: 240, y: 58)))
        for _ in 0..<120 { scene.step(dt: 1 / 60) }
        XCTAssertEqual(events.count, 1)
        XCTAssertLessThan(events[0].velocity.dy, 0)
        XCTAssertEqual(scene.objects[0].visibleBottom, winterRestingBottom(snow: 20, radius: 28), accuracy: 0.6,
                       "Примятый снег опускает шар")
        for size in [WinterBallSize.medium, .small] {
            let y = try XCTUnwrap(scene.objects.first).frame.maxY + size.radius
            let id = try XCTUnwrap(scene.create(size, at: CGPoint(x: 400, y: 400)))
            scene.beginDragging(id, at: CGPoint(x: 400, y: 400))
            scene.drag(id, to: CGPoint(x: 240, y: y), dt: 1)
            scene.endDragging(id, idleTime: 0.2)
        }
        XCTAssertTrue(scene.objects[0].isSnowman)
        scene.beginDragging(base, at: scene.objects[0].center)
        scene.drag(base, to: CGPoint(x: 240, y: 350), dt: 1)
        for _ in 0..<30 { scene.step(dt: 1 / 60) }
        XCTAssertEqual(events.count, 1, "Удерживаемый снеговик не ударяет снег")
        scene.endDragging(base)
        for _ in 0..<180 { scene.step(dt: 1 / 60) }
        XCTAssertEqual(events.count, 2)
        XCTAssertGreaterThan(events[1].mass, events[0].mass)
        XCTAssertEqual(events[1].radius, 28)
    }
    func testУдарПродолжаетРастиДоМассыТрёхМаксимальныхШаров() throws {
        var volumes: [Float] = []
        let ballMass = pow(CGFloat(36) / 14, 3)
        for mass in [ballMass, ballMass * 2, ballMass * 3] {
            let (simulation, layer) = try fixture()
            layer.replace(heights: layer.heights.map { _ in 100 })
            let before = layer.heights
            impact(simulation, radius: 36, mass: mass, speed: 600)
            volumes.append(zip(before, layer.heights).reduce(0) { $0 + max(0, $1.0 - $1.1) })
            XCTAssertEqual(area(layer) + particles(simulation).reduce(0) { $0 + $1.area },
                           before.reduce(0, +) * layer.columnWidth, accuracy: 0.1)
        }
        XCTAssertLessThan(volumes[0], volumes[1])
        XCTAssertLessThan(volumes[1], volumes[2], "Новая верхняя масса не упирается в старый предел силы")
    }

}
