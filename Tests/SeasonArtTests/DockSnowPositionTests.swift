import AppKit
import XCTest
@testable import SeasonArt

final class DockSnowPositionTests: XCTestCase {
    private let away = SIMD2<Float>(-1_000, -1_000)
    private let dock = WindowSurface(id: 42, frame: CGRect(x: 100, y: 6, width: 300, height: 60),
        blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: true)

    private func layers(_ simulation: SnowSimulation) -> [SnowLayer] {
        Mirror(reflecting: simulation).children.first { $0.label == "layers" }!.value as! [SnowLayer]
    }

    private func make(_ position: DockSnowPosition) -> SnowSimulation {
        let simulation = SnowSimulation(width: 600, height: 200, snowfall: .off)
        simulation.thaws = false
        simulation.dockSnowPosition = position
        simulation.updateWindows([dock], interval: 1 / 60)
        return simulation
    }

    func testВыборСохраняетсяВПрофилеИСверхуПоУмолчанию() {
        let name = "SeasonArtTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer {
            defaults.removePersistentDomain(forName: name)
            Preferences.configure(defaults: .standard)
        }
        Preferences.configure(defaults: defaults)
        Preferences.registerDefaults()
        XCTAssertEqual(Preferences.dockSnowPosition, .above)
        Preferences.dockSnowPosition = .below
        defaults.synchronize()
        Preferences.configure(defaults: UserDefaults(suiteName: name)!)
        Preferences.registerDefaults()
        XCTAssertEqual(Preferences.dockSnowPosition, .below)
    }

    func testПадающийСнегВыбираетПолкуИлиЗемлю() {
        for position in DockSnowPosition.allCases {
            let simulation = make(position)
            simulation.scatter((0..<100).map { _ in
                ScatterPiece(position: SIMD2(250, 130), velocity: SIMD2(0, -20), color: SIMD3(repeating: 1))
            })
            for _ in 0..<360 { _ = simulation.step(dt: 1 / 60, cursor: away) }
            let layers = layers(simulation)
            let shelf = layers.first { $0.isDock }!
            let ground = layers[0]
            let groundUnderDock = ground.heights.indices.filter {
                ground.centerX($0) > 100 && ground.centerX($0) < 400
            }.reduce(Float(0)) { $0 + ground.heights[$1] }
            if position == .above {
                XCTAssertGreaterThan(shelf.heights.reduce(0, +), 0)
                XCTAssertEqual(groundUnderDock, 0, accuracy: 0.001)
            } else {
                XCTAssertEqual(shelf.heights.reduce(0, +), 0, accuracy: 0.001)
                XCTAssertGreaterThan(groundUnderDock, 0)
            }
        }
    }

    func testПереключениеПереноситМассуБезДублирования() {
        let simulation = make(.above)
        let shelf = layers(simulation).first { $0.isDock }!
        for i in 40..<70 { shelf.set(i, 5) }
        let before = layers(simulation).reduce(Float(0)) { $0 + $1.heights.reduce(0, +) * $1.columnWidth }
        simulation.dockSnowPosition = .below
        XCTAssertEqual(shelf.heights.reduce(0, +), 0)
        XCTAssertEqual(layers(simulation)[0].heights.reduce(0, +) * simulation.columnWidth, before, accuracy: 0.01)
        simulation.dockSnowPosition = .above
        _ = simulation.step(dt: 1 / 60, cursor: away)
        XCTAssertEqual(layers(simulation).reduce(Float(0)) { $0 + $1.heights.reduce(0, +) * $1.columnWidth }, before, accuracy: 0.01)
    }

    func testСнегПодDockПродолжаетОседатьНаОкнах() {
        let simulation = make(.below)
        let window = WindowSurface(id: 7, frame: CGRect(x: 160, y: 80, width: 200, height: 20),
            blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: false)
        simulation.updateWindows([window, dock], interval: 1 / 60)
        simulation.scatter((0..<100).map { _ in
            ScatterPiece(position: SIMD2(250, 150), velocity: SIMD2(0, -20), color: SIMD3(repeating: 1))
        })
        for _ in 0..<180 { _ = simulation.step(dt: 1 / 60, cursor: away) }
        XCTAssertGreaterThan(layers(simulation).first { !$0.isDock && $0.origin.y > 0 }!.heights.reduce(0, +), 0)
    }

    func testПереносСнегаУКраяЭкранаНеТеряетМассу() {
        let simulation = make(.above)
        let edgeDock = WindowSurface(id: 42, frame: CGRect(x: 0, y: 6, width: 300, height: 60),
            blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: true)
        simulation.updateWindows([edgeDock], interval: 1 / 60)
        let shelf = layers(simulation).first { $0.isDock }!
        shelf.set(0, 10)
        let before = shelf.heights.reduce(0, +) * shelf.columnWidth
        simulation.dockSnowPosition = .below
        XCTAssertEqual(layers(simulation)[0].heights.reduce(0, +) * simulation.columnWidth, before, accuracy: 0.001)
    }

    func testСменаРежимаОбновляетРасположениеОверлея() throws {
        _ = NSApplication.shared
        let name = "SeasonArtTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer {
            defaults.removePersistentDomain(forName: name)
            Preferences.configure(defaults: .standard)
        }
        Preferences.configure(defaults: defaults)
        Preferences.registerDefaults()
        Preferences.dockSnowPosition = .below
        let snow = try XCTUnwrap(ScreenSnow(screen: XCTUnwrap(NSScreen.main),
            device: XCTUnwrap(MTLCreateSystemDefaultDevice()), snowOnWindows: { true }))
        defer { snow.close() }
        XCTAssertTrue(snow.window.belowDock)
        snow.simulation.switchMode(to: .autumn, direction: 1, calm: true)
        for _ in 0..<600 { _ = snow.simulation.step(dt: 1 / 60, cursor: away) }
        XCTAssertEqual(snow.simulation.mode, .autumn)
        XCTAssertFalse(snow.window.belowDock)
        snow.simulation.switchMode(to: .snow, direction: 1, calm: true)
        for _ in 0..<600 { _ = snow.simulation.step(dt: 1 / 60, cursor: away) }
        XCTAssertTrue(snow.window.belowDock)
        XCTAssertLessThan(snow.window.level.rawValue, Int(CGWindowLevelForKey(.dockWindow)))
    }

    func testКонтурИконкиИспользуетВысотуDockТекущегоКадра() throws {
        let simulation = make(.above)
        let shelf = try XCTUnwrap(layers(simulation).first { $0.isDock })
        for i in shelf.heights.indices { shelf.set(i, 8) }
        shelf.refreshTop()
        simulation.dockMagnification = DockMagnificationSettings(enabled: true, normalSize: 48, largeSize: 96)
        simulation.dockIconFrames = [DockSnowIcon(frame: CGRect(x: 210, y: 10, width: 80, height: 80), roof: [1, 1])]
        // AX читается до нового снимка окон и ещё помнит положение полки в прошлом кадре.
        simulation.dockPresentationFrame = CGRect(x: 100, y: -34, width: 300, height: 60)
        simulation.updateDockSnowSurface(dt: 1 / 60, cursor: SIMD2(250, 50))
        let contact = try XCTUnwrap(simulation.winterDockContact(on: 42, at: 250, radius: 0))
        XCTAssertGreaterThan(contact.top, 94)
        XCTAssertLessThan(contact.top, 101, "Верх иконки и глубина снега не получают лишний скачок от старой рамки")
    }

    func testИзменениеШириныПолкиDockСохраняетМассуБезСтряхивания() throws {
        let simulation = make(.above)
        let shelf = try XCTUnwrap(layers(simulation).first { $0.isDock })
        for i in shelf.heights.indices { shelf.set(i, 8) }
        let mass = shelf.heights.reduce(0, +) * shelf.columnWidth
        for width: CGFloat in [320, 280, 300] {
            let shifted = WindowSurface(id: 42, frame: CGRect(x: 250 - width / 2, y: 6, width: width, height: 60),
                blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: true)
            simulation.updateWindows([shifted], interval: 1 / 60)
            XCTAssertEqual(shelf.heights.reduce(0, +) * shelf.columnWidth, mass, accuracy: 0.01)
            XCTAssertEqual(simulation.spriteCount, 0)
        }
    }
}
