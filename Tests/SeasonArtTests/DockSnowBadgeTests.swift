import AppKit
import XCTest
@testable import SeasonArt

final class DockSnowBadgeTests: XCTestCase {
    func testБейджСовпадаетСИзмереннымКружкомПриОбычномРазмере() throws {
        // Нативный снимок: значок 47 pt, красный кружок [564, 1058, 18, 18] на экране высотой 1117 pt.
        let icon = CGRect(x: 535.475, y: 16, width: 47, height: 47)
        for label in ["2", "19"] {
            let badge = try XCTUnwrap(DockSnowBadge(label: label, iconFrame: icon))
            XCTAssertEqual(badge.frame.width, 18, accuracy: 1.5)
            XCTAssertEqual(badge.frame.height, 18, accuracy: 1.5)
            XCTAssertEqual(badge.frame.minX, 564, accuracy: 1.5)
            XCTAssertEqual(badge.frame.maxY, 59, accuracy: 1.5)
        }
    }

    func testОтсутствующийСчётчикНеСоздаётПризрачныйБейдж() {
        let frame = CGRect(x: 0, y: 0, width: 47, height: 47)
        for label: String? in [nil, "", "  ", "\n"] {
            XCTAssertNil(DockSnowBadge(label: label, iconFrame: frame))
        }
    }

    func testДлинныйСчётчикРасширяетсяВКапсулуИМасштабируетсяСИконкой() throws {
        let normal = try XCTUnwrap(DockSnowBadge(label: "999+", iconFrame: CGRect(x: 0, y: 0, width: 47, height: 47)))
        let raised = try XCTUnwrap(DockSnowBadge(label: "999+", iconFrame: CGRect(x: 0, y: 0, width: 76, height: 76)))
        XCTAssertGreaterThan(normal.frame.width, normal.frame.height)
        XCTAssertEqual(raised.frame.width / normal.frame.width, 76 / 47, accuracy: 0.03)
        XCTAssertEqual(raised.frame.height / normal.frame.height, 76 / 47, accuracy: 0.001)
        let center = try XCTUnwrap(raised.top(at: Float(raised.frame.midX)))
        let edge = try XCTUnwrap(raised.top(at: Float(raised.frame.minX)))
        XCTAssertGreaterThan(center - edge, Float(raised.frame.height * 0.4))
    }

    func testОбщийКонтурУчитываетБейджИУбираетЕгоПослеИсчезновения() throws {
        let frame = CGRect(x: 200, y: 10, width: 76, height: 76)
        let badge = try XCTUnwrap(DockSnowBadge(label: "19", iconFrame: frame))
        let x = Float(badge.frame.midX)
        let bare = DockSnowIcon(frame: frame, roof: [0.2, 0.2])
        let badged = DockSnowIcon(frame: frame, roof: [0.2, 0.2], badge: badge)
        XCTAssertEqual(try XCTUnwrap(badged.top(at: x)), Float(badge.frame.maxY), accuracy: 0.01)
        XCTAssertGreaterThan(try XCTUnwrap(badged.top(at: x)), try XCTUnwrap(bare.top(at: x)) + 30)
        let shelf = CGRect(x: 100, y: 6, width: 400, height: 60)
        var surface = DockSnowSurface()
        let settings = DockMagnificationSettings(enabled: true, normalSize: 47, largeSize: 76)
        surface.step(dt: 1 / 60, frame: shelf, columns: 200, columnWidth: 2,
                     cursor: SIMD2(250, 50), settings: settings, icons: [badged])
        XCTAssertGreaterThan(surface.maximum, 5)
        surface.step(dt: 1 / 60, frame: shelf, columns: 200, columnWidth: 2,
                     cursor: SIMD2(250, 50), settings: settings, icons: [bare])
        XCTAssertEqual(surface.maximum, 0)
    }

    func testСнегЛежитНаБейджеБезИзмененияМассыИСОбщейОпоройДляСнежка() throws {
        let simulation = SnowSimulation(width: 600, height: 300, snowfall: .off)
        simulation.thaws = false
        simulation.cursorInteracts = false
        let frame = CGRect(x: 200, y: 10, width: 76, height: 76)
        let badge = try XCTUnwrap(DockSnowBadge(label: "19", iconFrame: frame))
        simulation.dockMagnification = DockMagnificationSettings(enabled: true, normalSize: 47, largeSize: 76)
        simulation.dockIconFrames = [DockSnowIcon(frame: frame, roof: [0.2, 0.2], badge: badge)]
        simulation.updateWindows([WindowSurface(id: 42, frame: CGRect(x: 100, y: 6, width: 400, height: 60),
            blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: true)], interval: 1 / 60)
        let layers = Mirror(reflecting: simulation).children.first { $0.label == "layers" }!.value as! [SnowLayer]
        let shelf = try XCTUnwrap(layers.first { $0.isDock })
        for i in 20..<(shelf.count - 20) { shelf.set(i, 7) }
        shelf.refreshTop()
        let mass = shelf.heights.reduce(0, +)
        simulation.updateDockSnowSurface(dt: 1 / 60, cursor: SIMD2(250, 50))
        let contact = try XCTUnwrap(simulation.winterDockContact(on: 42, at: badge.frame.midX, radius: 0))
        XCTAssertGreaterThan(contact.top, badge.frame.maxY + 4)
        XCTAssertEqual(shelf.heights.reduce(0, +), mass)
    }
}
