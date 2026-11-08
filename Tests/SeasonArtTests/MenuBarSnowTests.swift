import AppKit
import XCTest
@testable import SeasonArt

final class MenuBarSnowTests: XCTestCase {
    private func surface(_ id: CGWindowID, top: CGFloat, dock: Bool = false) -> WindowSurface {
        WindowSurface(id: id, frame: CGRect(x: 0, y: top - 100, width: 600, height: 100),
                      blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2, isDock: dock)
    }

    private func update(_ surfaces: [WindowSurface]) -> WindowUpdate {
        WindowUpdate(surfaces: surfaces, interval: 0.1, parked: [8], elsewhere: [9], sliding: false, slideVelocity: 120)
    }

    func testЗонаОтсчитываетсяОтНижнегоКраяСтрокиМенюИСохраняетDock() {
        let original = update([surface(1, top: 370), surface(2, top: 332), surface(3, top: 331), surface(4, top: 60, dock: true), surface(5, top: 340)])
        let filtered = original.excludingSurfacesNearMenuBar(screenHeight: 400, menuBarHeight: 30)
        XCTAssertEqual(filtered.surfaces.map(\.id), [3, 4], "Граница 38 пунктов включена в зону без сугробов")
        XCTAssertEqual(original.surfaces.count, 5, "Исходные опоры зимних игрушек сохраняются")
        XCTAssertEqual(filtered.interval, original.interval)
        XCTAssertEqual(filtered.parked, original.parked)
        XCTAssertEqual(filtered.elsewhere, original.elsewhere)
        XCTAssertEqual(filtered.slideVelocity, original.slideVelocity)
    }

    func testСнегПролетаетВерхнееОкноИДолетаетДоНижнего() {
        for skipTop in [false, true] {
            let simulation = SnowSimulation(width: 600, height: 400, snowfall: .off)
            simulation.thaws = false
            let original = update([surface(1, top: 370), surface(2, top: 200)])
            let snow = skipTop ? original.excludingSurfacesNearMenuBar(screenHeight: 400, menuBarHeight: 30) : original
            simulation.updateWindows(snow.surfaces, interval: 0.1)
            simulation.scatter((0..<500).map { i in
                ScatterPiece(position: SIMD2(150 + Float(i % 200), 390), velocity: SIMD2(0, -100), color: SIMD3(repeating: 1))
            })
            for _ in 0..<240 { _ = simulation.step(dt: 1 / 60, cursor: SIMD2(-1_000, -1_000)) }
            XCTAssertEqual(simulation.sculptingSource(at: CGPoint(x: 250, y: 371)) != nil, !skipTop)
            XCTAssertEqual(simulation.sculptingSource(at: CGPoint(x: 250, y: 201)) != nil, skipTop,
                           "При включённом пропуске снег достигает нижнего окна")
        }
    }
}
