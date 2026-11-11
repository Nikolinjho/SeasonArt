import XCTest
@testable import SeasonArt

final class DockCornerMaskTests: XCTestCase {
    private let body = CGRect(x: 100, y: 6, width: 300, height: 60)
    private let away = SIMD2<Float>(-1_000, -1_000)

    private func scene(height: Float) throws -> (SnowSimulation, SnowLayer) {
        let value = SnowSimulation(width: 600, height: 200, snowfall: .off)
        value.thaws = false
        value.cursorInteracts = false
        value.dockMagnification = DockMagnificationSettings(enabled: true, normalSize: 48, largeSize: 100)
        value.dockPresentationFrame = body
        value.updateWindows([WindowSurface(id: 42, frame: body, blockers: [], cover: [],
            cornerRadius: 20, cornerExponent: 2, isDock: true)], interval: 1 / 60)
        let ground = try XCTUnwrap(Mirror(reflecting: value).children.first { $0.label == "ground" }?.value as? SnowLayer)
        for i in ground.heights.indices { ground.set(i, height) }
        ground.refreshTop()
        return (value, ground)
    }

    func testМаскаПовторяетСкруглениеНижнихУглов() throws {
        let (value, _) = try scene(height: 10)
        var buffer = [Float](repeating: 0, count: 100_000)
        let layers = value.writeLayers(into: &buffer, capacity: buffer.count)
        let ground = try XCTUnwrap(layers.first { !$0.isDock })
        func hidden(_ x: Float, _ y: Float) -> Bool {
            ground.occluders.contains { x >= $0.x && x <= $0.z && y >= $0.y && y <= $0.w }
        }
        XCTAssertFalse(hidden(101, 8), "Под изгибом нижнего угла стекла нет: снег виден")
        XCTAssertTrue(hidden(250, 8), "Под дном корпуса снег скрыт")
        XCTAssertTrue(hidden(101, 50), "Бок корпуса скрывает снег")
    }
}
