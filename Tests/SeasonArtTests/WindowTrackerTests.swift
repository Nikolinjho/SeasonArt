import AppKit
import XCTest
@testable import SeasonArt

final class WindowTrackerTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let frontID: CGWindowID = 0x7000_0001

    private func entry(_ id: CGWindowID, _ frame: CGRect) -> NSDictionary {
        [kCGWindowNumber: NSNumber(value: id),
         kCGWindowOwnerPID: NSNumber(value: Int32(99999)),
         kCGWindowLayer: NSNumber(value: 0),
         kCGWindowAlpha: NSNumber(value: 1.0),
         kCGWindowOwnerName: "SeasonArt test window",
         kCGWindowBounds: frame.dictionaryRepresentation,
         kCGWindowIsOnscreen: kCFBooleanTrue!] as NSDictionary
    }

    private func surfaces(_ entries: [NSDictionary]) -> [WindowSurface] {
        let tracker = WindowTracker(windowListProvider: { entries as CFArray })
        tracker.screen = screen
        tracker.primaryHeight = screen.height
        tracker.menuBarHeight = 33
        return tracker.poll(now: 100, eager: true)?.surfaces ?? []
    }

    func testMaximizedWindowBelowMenuBarCollectsSnow() throws {
        let bounds = CGRect(x: 1, y: 33, width: 1724, height: 1000)
        let surface = try XCTUnwrap(surfaces([entry(frontID, bounds)]).first,
                                   "Развёрнутое окно должно принимать частицы на верхней границе")
        XCTAssertEqual(surface.id, frontID)
        XCTAssertEqual(surface.frame.maxY, 1084, "Опора совпадает с настоящим верхним краем под строкой меню")
        XCTAssertTrue(surface.blockers.isEmpty, "Переднее окно не должно перекрывать само себя")
    }

    func testWindowFlushWithMenuBarDoesNotNeedExtraSixPointGap() {
        let bounds = CGRect(x: 200, y: 33, width: 600, height: 400)
        XCTAssertEqual(surfaces([entry(frontID, bounds)]).map(\.id), [frontID],
                       "Окно непосредственно под строкой меню остаётся доступным для снега и лепестков")
    }

    func testFullscreenWindowWithNoVisibleTopEdgeDoesNotCreatePile() {
        XCTAssertTrue(surfaces([entry(frontID, screen)]).isEmpty,
                      "Полноэкранное окно без видимой верхней границы не создаёт невидимый сугроб")
    }

    func testMaximizedFrontWindowStillOccludesWindowsBehindIt() throws {
        let backID = frontID + 1
        let result = surfaces([
            entry(frontID, CGRect(x: 1, y: 33, width: 1724, height: 1000)),
            entry(backID, CGRect(x: 200, y: 180, width: 600, height: 400))
        ])
        XCTAssertNotNil(result.first { $0.id == frontID }, "Переднее развёрнутое окно получает свою опору")
        let back = try XCTUnwrap(result.first { $0.id == backID })
        XCTAssertFalse(back.blockers.isEmpty, "Окно сзади сохраняет маску перекрытия")
    }

    func testTransparentNotchPanelDoesNotHideWindowLedge() throws {
        let panel = entry(frontID + 1, CGRect(x: 384, y: 0, width: 960, height: 360)).mutableCopy() as! NSMutableDictionary
        panel[kCGWindowOwnerName] = "Oasis"
        panel[kCGWindowLayer] = NSNumber(value: NSWindow.Level.statusBar.rawValue + 1)
        let surface = try XCTUnwrap(surfaces([
            panel, entry(frontID, CGRect(x: 500, y: 180, width: 600, height: 400))
        ]).first { $0.id == frontID })
        XCTAssertTrue(surface.blockers.isEmpty,
                      "Прозрачная область панели выреза не перекрывает верхний край обычного окна")
        XCTAssertTrue(surface.cover.isEmpty,
                      "Прозрачная панель не скрывает дождь на поверхности окна")
    }

    func testOrdinaryOasisWindowStillBlocksWindowsBehindIt() throws {
        let settings = entry(frontID + 1, CGRect(x: 384, y: 90, width: 960, height: 792)).mutableCopy() as! NSMutableDictionary
        settings[kCGWindowOwnerName] = "Oasis"
        let surface = try XCTUnwrap(surfaces([
            settings, entry(frontID, CGRect(x: 500, y: 180, width: 600, height: 400))
        ]).first { $0.id == frontID })
        XCTAssertFalse(surface.blockers.isEmpty, "Обычное окно Oasis сохраняет перекрытие")
    }
}
