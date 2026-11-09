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
    func testWindowOnAllSpacesDoesNotHideDockAsFullscreenApp() {
        let list = [entry(frontID, screen)]
        let tracker = WindowTracker(windowListProvider: { list as CFArray },
                                    fullScreenSpaceProvider: { [22] },
                                    windowSpacesProvider: { _ in [1, 22] })
        tracker.screen = screen
        tracker.primaryHeight = screen.height
        tracker.menuBarHeight = 33
        _ = tracker.poll(now: 100, eager: true)
        XCTAssertFalse(tracker.fullScreenInView,
                       "Окно на обычном и полноэкранном Spaces не является полноэкранным приложением")
        XCTAssertEqual(tracker.fullScreenShare, 0, "Общий холст не запускает затухание обычного рабочего стола")
        XCTAssertNil(tracker.desktopShare(now: 100), "Общий холст не подменяет сведения о переходе между Spaces")
    }

    func testWindowBelongingOnlyToFullscreenSpaceStillHidesDock() {
        let list = [entry(frontID, screen)]
        let tracker = WindowTracker(windowListProvider: { list as CFArray },
                                    fullScreenSpaceProvider: { [22] },
                                    windowSpacesProvider: { _ in [22] })
        tracker.screen = screen
        tracker.primaryHeight = screen.height
        _ = tracker.poll(now: 100, eager: true)
        XCTAssertTrue(tracker.fullScreenInView, "Настоящее полноэкранное окно сохраняет скрытие Dock")
        XCTAssertEqual(tracker.fullScreenShare, 1)
    }

    func testDockSnowWaitsDuringFullscreenTransition() throws {
        try checkDockSnowWaits(dockRemainsListed: true)
    }

    func testСугробСохраняетсяКогдаDockПолностьюПропалПриВходеВFullscreen() throws {
        try checkDockSnowWaits(dockRemainsListed: false)
    }

    private func checkDockSnowWaits(dockRemainsListed: Bool) throws {
        let dockID = frontID + 2
        let dock = entry(dockID, screen).mutableCopy() as! NSMutableDictionary
        dock[kCGWindowOwnerName] = "Dock"
        dock[kCGWindowLayer] = NSNumber(value: CGWindowLevelForKey(.dockWindow))
        var list: [NSDictionary] = [dock]
        let tracker = WindowTracker(windowListProvider: { list as CFArray },
                                    fullScreenSpaceProvider: { [22] },
                                    windowSpacesProvider: { _ in [22] },
                                    dockReservedProvider: { CGRect(x: 400, y: 1040, width: 900, height: 77) })
        tracker.screen = screen
        tracker.primaryHeight = screen.height
        tracker.menuBarHeight = 33
        let simulation = SnowSimulation(width: Float(screen.width), height: Float(screen.height), snowfall: .off)
        simulation.thaws = false
        func layers() -> [SnowLayer] {
            Mirror(reflecting: simulation).children.first { $0.label == "layers" }!.value as! [SnowLayer]
        }
        func apply(_ update: WindowUpdate) {
            simulation.updateWindows(update.surfaces, interval: update.interval,
                                     parked: update.parked, elsewhere: update.elsewhere, sliding: update.sliding)
        }
        apply(try XCTUnwrap(tracker.poll(now: 100, eager: true)))
        let layer = try XCTUnwrap(layers().first { $0.isDock })
        layer.set(layer.count / 2, 8)
        let mass = layer.heights.reduce(0, +)

        list = dockRemainsListed ? [entry(frontID, screen), dock] : [entry(frontID, screen)]
        let entering = try XCTUnwrap(tracker.poll(now: 100.1, eager: true))
        XCTAssertFalse(entering.surfaces.contains { $0.isDock }, "Скрытый Dock не оставляет невидимую опору")
        XCTAssertTrue(entering.elsewhere.contains(dockID), "Снег Dock ожидает возвращения из полноэкранного Space")
        apply(entering)
        XCTAssertEqual(simulation.spriteCount, 0, "Переход не сбрасывает сугроб в падающие частицы")

        list = [dock]
        apply(try XCTUnwrap(tracker.poll(now: 101, eager: true)))
        let restored = try XCTUnwrap(layers().first { $0.isDock })
        XCTAssertTrue(restored === layer, "Возвращается прежний сугроб")
        XCTAssertEqual(restored.heights.reduce(0, +), mass, accuracy: 0.001, "Масса сохраняется после перехода")
    }

    func testПостоянныйDockСНулевойРезервнойВысотойОстаётсяОпоройБезНаведения() throws {
        let dockID = frontID + 2
        let dock = entry(dockID, screen).mutableCopy() as! NSMutableDictionary
        dock[kCGWindowOwnerName] = "Dock"
        dock[kCGWindowLayer] = NSNumber(value: CGWindowLevelForKey(.dockWindow))
        var pointer = CGPoint(x: 700, y: 400)
        let tracker = WindowTracker(windowListProvider: { [dock] as CFArray },
            fullScreenSpaceProvider: { [] }, windowSpacesProvider: { _ in [] },
            dockReservedProvider: { CGRect(x: 400, y: self.screen.maxY, width: 900, height: 0) },
            pointerProvider: { pointer }, dockAutoHideProvider: { false })
        tracker.screen = screen
        tracker.primaryHeight = screen.height
        let first = try XCTUnwrap(tracker.poll(now: 100, eager: true))
        let shelf = try XCTUnwrap(first.surfaces.first { $0.isDock },
                                 "CUA: видимый Dock при выключенном автоскрытии существует и без наведения")
        for (index, y): (Int, CGFloat) in [20, 80, 400].enumerated() {
            pointer.y = y
            if let update = tracker.poll(now: 101 + Double(index), eager: true) {
                XCTAssertEqual(update.surfaces.first { $0.isDock }?.frame, shelf.frame)
                XCTAssertFalse(update.elsewhere.contains(dockID))
            }
        }
    }

    func testСкачокПоявленияDockНеПодбрасываетСнегКакРывокОкна() throws {
        let dockID = frontID + 2
        let dock = entry(dockID, screen).mutableCopy() as! NSMutableDictionary
        dock[kCGWindowOwnerName] = "Dock"
        dock[kCGWindowLayer] = NSNumber(value: CGWindowLevelForKey(.dockWindow))
        var reserved = CGRect(x: 400, y: screen.maxY, width: 900, height: 0)
        let tracker = WindowTracker(windowListProvider: { [dock] as CFArray },
            fullScreenSpaceProvider: { [] }, windowSpacesProvider: { _ in [] },
            dockReservedProvider: { reserved }, pointerProvider: { CGPoint(x: 700, y: 20) }, dockAutoHideProvider: { true })
        tracker.screen = screen
        tracker.primaryHeight = screen.height
        let simulation = SnowSimulation(width: Float(screen.width), height: Float(screen.height), snowfall: .off)
        simulation.thaws = false
        simulation.cursorInteracts = false
        func layers() -> [SnowLayer] {
            Mirror(reflecting: simulation).children.first { $0.label == "layers" }!.value as! [SnowLayer]
        }
        func apply(_ now: Double) {
            guard let update = tracker.poll(now: now, eager: true) else { return }
            simulation.updateWindows(update.surfaces, interval: update.interval,
                parked: update.parked, elsewhere: update.elsewhere, sliding: update.sliding)
        }
        apply(100)
        apply(100.02)
        let layer = try XCTUnwrap(layers().first { $0.isDock })
        for i in 15..<(layer.count - 15) { layer.set(i, 8) }
        layer.refreshTop()
        let mass = layer.heights.reduce(0, +)
        // Реальная запись: незавершённое появление сменяется полной рамкой одним быстрым обновлением.
        reserved = CGRect(x: 400, y: screen.maxY - 67, width: 900, height: 67)
        apply(100.04)
        for _ in 0..<30 {
            _ = simulation.step(dt: 1 / 60, cursor: SIMD2(-1_000, -1_000))
            XCTAssertEqual(simulation.spriteCount, 0, "Появление Dock не стряхивает снег с его полки")
            XCTAssertEqual(layer.heights.reduce(0, +), mass, accuracy: 0.01)
            XCTAssertEqual(layer.offset.y, 0, accuracy: 0.001)
        }
    }

    func testUnknownWindowSpacesDoNotCreateFullscreenState() {
        let list = [entry(frontID, screen)]
        let tracker = WindowTracker(windowListProvider: { list as CFArray },
                                    fullScreenSpaceProvider: { [22] },
                                    windowSpacesProvider: { _ in [] })
        tracker.screen = screen
        tracker.primaryHeight = screen.height
        _ = tracker.poll(now: 100, eager: true)
        XCTAssertFalse(tracker.fullScreenInView)
    }

    func testУвеличеннаяИконкаНеСкрываетПолкуКогдаУказательВышеОбычногоDock() throws {
        let dockID = frontID + 2
        let dock = entry(dockID, screen).mutableCopy() as! NSMutableDictionary
        dock[kCGWindowOwnerName] = "Dock"
        dock[kCGWindowLayer] = NSNumber(value: CGWindowLevelForKey(.dockWindow))
        var pointer = CGPoint(x: 700, y: 20)
        let tracker = WindowTracker(windowListProvider: { [dock] as CFArray },
            fullScreenSpaceProvider: { [] }, windowSpacesProvider: { _ in [] },
            dockReservedProvider: { CGRect(x: 400, y: self.screen.maxY, width: 900, height: 0) },
            pointerProvider: { pointer }, dockAutoHideProvider: { true })
        tracker.screen = screen
        tracker.primaryHeight = screen.height
        tracker.menuBarHeight = 33
        _ = tracker.poll(now: 100, eager: true)
        let shown = try XCTUnwrap(tracker.poll(now: 100.3, eager: true)?.surfaces.first { $0.isDock })
        // Видимый значок выше обычной полки. Это остаётся наведением на Dock.
        tracker.dockInteractionFrame = shown.frame.insetBy(dx: -50, dy: -50)
        pointer.y = shown.frame.maxY + 15
        XCTAssertLessThan(pointer.y, tracker.dockInteractionFrame!.maxY)
        let hovered = tracker.poll(now: 100.4, eager: true)
        let retained = hovered?.surfaces.first { $0.isDock }
        XCTAssertEqual(retained?.id ?? shown.id, shown.id)
        XCTAssertFalse(hovered?.elsewhere.contains(dockID) ?? false)
        XCTAssertTrue(hovered == nil || retained != nil, "Увеличенная иконка не удаляет видимую опору")
    }

    func testУходИВозвратКDockНеРассыпаетСугробПодНегоИКБокам() throws {
        let dockID = frontID + 2
        let dock = entry(dockID, screen).mutableCopy() as! NSMutableDictionary
        dock[kCGWindowOwnerName] = "Dock"
        dock[kCGWindowLayer] = NSNumber(value: CGWindowLevelForKey(.dockWindow))
        var pointer = CGPoint(x: 700, y: 20)
        let tracker = WindowTracker(windowListProvider: { [dock] as CFArray },
            fullScreenSpaceProvider: { [] }, windowSpacesProvider: { _ in [] },
            dockReservedProvider: { CGRect(x: 400, y: self.screen.maxY, width: 900, height: 0) },
            pointerProvider: { pointer }, dockAutoHideProvider: { true })
        tracker.screen = screen
        tracker.primaryHeight = screen.height
        let simulation = SnowSimulation(width: Float(screen.width), height: Float(screen.height), snowfall: .off)
        simulation.thaws = false
        simulation.cursorInteracts = false
        func layers() -> [SnowLayer] {
            Mirror(reflecting: simulation).children.first { $0.label == "layers" }!.value as! [SnowLayer]
        }
        func apply(_ update: WindowUpdate?) {
            guard let update else { return }
            simulation.updateWindows(update.surfaces, interval: update.interval,
                parked: update.parked, elsewhere: update.elsewhere, sliding: update.sliding)
        }
        apply(tracker.poll(now: 100, eager: true))
        apply(tracker.poll(now: 100.3, eager: true))
        let layer = try XCTUnwrap(layers().first { $0.isDock })
        layer.set(layer.count / 2, 8)
        let heights = layer.heights
        for cycle in 0..<4 {
            let now = 101 + Double(cycle)
            pointer.y = 400
            let hidden = try XCTUnwrap(tracker.poll(now: now, eager: true))
            XCTAssertTrue(hidden.elsewhere.contains(dockID), "Скрытие Dock сохраняет прежнюю опору в ожидании")
            apply(hidden)
            XCTAssertEqual(simulation.spriteCount, 0, "Уход указателя не превращает сугроб в падающие частицы")
            for _ in 0..<120 { _ = simulation.step(dt: 1 / 60, cursor: SIMD2(-1_000, -1_000)) }
            XCTAssertEqual(layers()[0].heights.reduce(0, +), 0, accuracy: 0.001,
                           "Снег с полки не переезжает под Dock и к его боковым краям")
            pointer.y = 20
            apply(tracker.poll(now: now + 0.3, eager: true))
            apply(tracker.poll(now: now + 0.6, eager: true))
            let returned = try XCTUnwrap(layers().first { $0.isDock })
            XCTAssertTrue(returned === layer)
            XCTAssertEqual(returned.heights, heights)
        }
    }

}
