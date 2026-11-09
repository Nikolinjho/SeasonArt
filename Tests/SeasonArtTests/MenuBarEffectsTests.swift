import AppKit
import Metal
import XCTest
@testable import SeasonArt

final class MenuBarEffectsTests: XCTestCase {
    func testВсеРежимыПропускаютОкнаУСтрокиМенюПоОбщейНастройке() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let suite = "SeasonArtTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        Preferences.configure(defaults: defaults)
        Preferences.registerDefaults()
        Preferences.snowfall = .off
        Preferences.blizzard = true
        defer {
            Preferences.configure(defaults: .standard)
            defaults.removePersistentDomain(forName: suite)
        }
        let snow = try XCTUnwrap(ScreenSnow(screen: screen, device: device, snowOnWindows: { true }))
        defer { snow.close() }
        XCTAssertTrue(snow.simulation.blizzard, "Новый экран получает сохранённую настройку метели")
        let boundary = screen.frame.height - (screen.frame.maxY - screen.visibleFrame.maxY) - 38
        func surface(_ id: CGWindowID, top: CGFloat, dock: Bool = false) -> WindowSurface {
            WindowSurface(id: id, frame: CGRect(x: 0, y: top - 100, width: 600, height: 100),
                blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2, isDock: dock)
        }
        let original = WindowUpdate(surfaces: [surface(1, top: boundary + 20), surface(2, top: boundary),
            surface(3, top: boundary - 1), surface(4, top: 60, dock: true)],
            interval: 0.1, parked: [8], elsewhere: [9], sliding: false, slideVelocity: 120)
        for mode in Mode.allCases {
            snow.mode = mode
            Preferences.skipSnowNearMenuBar = true
            let filtered = snow.particleWindowUpdate(original)
            XCTAssertEqual(filtered.surfaces.map(\.id), [3, 4], mode.title)
            XCTAssertEqual(filtered.parked, original.parked)
            XCTAssertEqual(filtered.elsewhere, original.elsewhere)
            Preferences.skipSnowNearMenuBar = false
            XCTAssertEqual(snow.particleWindowUpdate(original).surfaces, original.surfaces, mode.title)
        }
        XCTAssertEqual(original.surfaces.map(\.id), [1, 2, 3, 4], "Зимние игрушки получают исходные опоры")
    }
}
