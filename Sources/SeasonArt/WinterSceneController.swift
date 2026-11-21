import AppKit
import QuartzCore

/// Тикает от экрана, пока сцена движется, и редким таймером в покое.
private final class WinterTicker: NSObject {
    /// 0 означает синхронизацию с обновлением экрана.
    let interval: TimeInterval
    private var link: CADisplayLink?
    private var timer: Timer?
    private let action: () -> Void

    init(interval: TimeInterval, screen: NSScreen?, action: @escaping () -> Void) {
        self.interval = interval
        self.action = action
        super.init()
        if interval == 0, let screen {
            let link = screen.displayLink(target: self, selector: #selector(fire))
            link.add(to: .main, forMode: .common)
            self.link = link
        } else {
            let timer = Timer(timeInterval: interval > 0 ? interval : 1.0 / 60, repeats: true) { [weak self] _ in self?.fire() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    @objc private func fire() { action() }

    func invalidate() {
        link?.invalidate()
        link = nil
        timer?.invalidate()
        timer = nil
    }
}

/// Связывает чистую модель с небольшими интерактивными окнами одного экрана.
final class WinterSceneController {
    let scene: WinterScene
    private let simulation: SnowSimulation
    private let presentsWindows: Bool
    private var screenFrame: CGRect
    private var windows: [UUID: WinterObjectWindow] = [:]
    private var plowWindow: WinterPlowWindow?
    private var treeDecorations = Preferences.treeDecorations
    private var treeSupport: (id: CGWindowID, offset: CGFloat)?
    private var treeMotion = WinterTreeMotion()
    private var sleigh: WinterSleighShow?
    private let finderGarlands = FinderGarlands()
    var showsFinderGarlands = false { didSet { refresh() } }
    var pollVisibleWindows: () -> Void = {}
    private var toyWindows: [WinterToy: WinterToyWindow] = [:]
    private var accessoryFlights: [WinterAccessoryFlight] = []
    private var shelf: WindowSurface?
    private var timer: WinterTicker?
    private var lastFrame: CFTimeInterval = 0
    private var syncing = false
    private var closed = false
    private(set) var plow: WinterPlowPass?
    private(set) var sculptingPreview: SnowSculptingPreviewWindow?
    private var sculptingGesture: SnowSculptingGesture? {
        didSet { simulation.previewSculpting(sculptingGesture) }
    }
    private var lastPointer: CGPoint?
    private var stationaryTime: TimeInterval = 0
    private var waitsForExit = false
    private var trackedSurfaces: [WindowSurface] = []
    var isSculpting: Bool { sculptingGesture != nil }
    var changed: () -> Void = {}

    var isEnabled = false { didSet { refresh() } }
    var isActive = true { didSet { refresh() } }
    var isSuppressed = false { didSet { refresh() } }
    var showsInScreenshots = false {
        didSet {
            for window in windows.values { window.showsInScreenshots = showsInScreenshots }
            sleigh?.window.showsInScreenshots = showsInScreenshots
            finderGarlands.showsInScreenshots = showsInScreenshots
            plowWindow?.showsInScreenshots = showsInScreenshots
            for window in toyWindows.values { window.showsInScreenshots = showsInScreenshots }
            for flight in accessoryFlights { flight.window.showsInScreenshots = showsInScreenshots }
            sculptingPreview?.showsInScreenshots = showsInScreenshots
        }
    }
    var canUseToys: Bool { !closed && isEnabled && isActive && !isSuppressed }
    var canCreate: Bool { canUseToys && scene.hasCapacity }
    var canPlow: Bool { !closed && isEnabled && isActive && !isSuppressed && shelf != nil && plow == nil }
    var objectWindowCount: Int { windows.count }
    var isRunning: Bool { timer != nil }
    var hasObjects: Bool { needsAnimation || !toyWindows.isEmpty }
    private var needsAnimation: Bool { treeMotion.isMoving || sleigh != nil || !scene.objects.isEmpty || plow != nil || isSculpting || !accessoryFlights.isEmpty }
    var needsUpdates: Bool { canUseToys && (needsAnimation || simulation.hasSculptableSnow) }

    init(screenFrame: CGRect, simulation: SnowSimulation, presentsWindows: Bool = true) {
        self.screenFrame = screenFrame
        self.simulation = simulation
        self.presentsWindows = presentsWindows
        scene = WinterScene(width: screenFrame.width, height: screenFrame.height)
        scene.surfaceHeight = { [weak simulation] id, x in simulation?.winterSurfaceY(at: x, on: id) }
        scene.dockContact = { [weak simulation] id, x, radius in simulation?.winterDockContact(on: id, at: x, radius: radius) }
        scene.dockBody = { [weak simulation] id in simulation?.winterDockBody(for: id) }
        scene.dockProfile = { [weak simulation] id in simulation?.winterDockProfile(on: id) }
        scene.didLand = { [weak simulation] impact in simulation?.displaceSnow(for: impact) }
        scene.didChip = { [weak simulation] chip in
            let count = max(3, min(10, Int(chip.strength * 40)))
            let pieces = (0..<count).map { index -> ScatterPiece in
                let side = Float(index) / Float(count - 1) * 2 - 1
                return ScatterPiece(
                    position: SIMD2(Float(chip.center.x) + side * Float(chip.radius) * 0.55, Float(chip.center.y)),
                    velocity: SIMD2(side * 100, 25 + (1 - abs(side)) * 65), color: SIMD3(repeating: 1))
            }
            simulation?.scatter(pieces)
        }
        scene.didBreakSnowman = { [weak self] object in self?.scatterOutfit(of: object) }
    }

    @discardableResult
    func create(_ size: WinterBallSize, at point: CGPoint) -> UUID? {
        guard canCreate else { return nil }
        let id = scene.place(radius: size.radius, near: point)
        refresh()
        changed()
        return id
    }

    func updateDockContacts() {
        guard !closed, isEnabled, isActive, !isSuppressed, hasObjects else { return }
        alignTreeWithSupport()
        if scene.synchronizeDockSupports() { refresh() }
    }

    func updateSnowmanGaze(at point: CGPoint, dt: TimeInterval) {
        guard canUseToys else { return }
        let point = local(point)
        for object in scene.objects where object.isSnowman && !object.parked {
            (windows[object.id]?.contentView as? WinterObjectView)?.lookToward(point, dt: dt)
        }
    }

    /// Вызывается до шага симуляции, чтобы обычная расчистка не забирала снег черновика.
    func updateAutomaticSculpting(at point: CGPoint, dt: TimeInterval, mouseButtons: Int) {
        guard !closed, isEnabled, isActive, !isSuppressed else {
            cancelSculpting()
            return
        }
        guard mouseButtons == 0, !scene.objects.contains(where: \.isDragged) else {
            let stillWaitsForExit = waitsForExit && simulation.sculptingSource(at: local(point)) != nil
            cancelSculpting()
            waitsForExit = stillWaitsForExit
            return
        }
        simulation.cursorInteracts = false
        let point = local(point)
        let previous = lastPointer
        lastPointer = point
        let moved = previous.map { $0 != point } ?? false
        if let gesture = sculptingGesture, !simulation.isSculptingSourceValid(gesture.source) {
            cancelSculpting()
            simulation.cursorInteracts = false
            lastPointer = point
            return
        }
        guard moved || isSculpting else { return }
        if let gesture = sculptingGesture, gesture.source.isDock {
            sculptingGesture?.updateSource(simulation.sculptingSource(for: gesture.source.layer))
        }
        // При движении внутри снимка не копируем весь слой на каждом кадре.
        let source: SculptingSource?
        if let gesture = sculptingGesture, gesture.source.column(at: point) != nil {
            source = gesture.source
        } else {
            source = simulation.sculptingSource(at: point)
        }
        guard let source else {
            finishSculpting(waitForExit: false)
            waitsForExit = false
            stationaryTime = 0
            return
        }
        guard canCreate, !waitsForExit else { return }
        if let gesture = sculptingGesture, gesture.source.layer !== source.layer {
            finishSculpting(waitForExit: false)
            return
        }
        if moved {
            stationaryTime = 0
            if sculptingGesture == nil {
                // Начальная колонка тоже принадлежит проходу, если указатель уже был на этой опоре.
                let start = previous.flatMap { source.column(at: $0) != nil ? $0 : nil } ?? point
                sculptingGesture = SnowSculptingGesture(source: source, at: start, paced: true)
            }
            sculptingGesture?.include(point, dt: dt)
            // Растущий снежок отталкивает соседей. Лепка заканчивается, только если толкать их некуда.
            var touches = false
            if let gesture = sculptingGesture, let radius = gesture.radius {
                guard simulation.canPlaceSculptedBall(gesture, radius: radius) else {
                    cancelSculpting()
                    return
                }
                let center = CGPoint(x: gesture.lastPoint.x, y: gesture.center.y)
                if !scene.isFree(radius: radius, at: center) {
                    touches = !scene.makeRoom(radius: radius, at: center)
                    if !touches { refresh() }
                }
            }
            if sculptingGesture?.isFull == true || touches {
                finishSculpting(waitForExit: true)
            } else if let gesture = sculptingGesture, gesture.radius != nil {
                if sculptingPreview == nil {
                    sculptingPreview = SnowSculptingPreviewWindow()
                    sculptingPreview?.showsInScreenshots = showsInScreenshots
                }
                sculptingPreview?.display(gesture, screenFrame: screenFrame)
                if presentsWindows && sculptingPreview?.isVisible == false { sculptingPreview?.orderFrontRegardless() }
            }
        } else if isSculpting {
            stationaryTime += dt.isFinite ? max(0, dt) : 0
            if stationaryTime >= 0.35 { finishSculpting(waitForExit: true) }
        }
    }

    func cancelSculpting() {
        sculptingGesture = nil
        sculptingPreview?.close()
        sculptingPreview = nil
        lastPointer = nil
        stationaryTime = 0
        waitsForExit = false
        simulation.cursorInteracts = true
    }

    private func finishSculpting(waitForExit: Bool) {
        let gesture = sculptingGesture
        sculptingGesture = nil
        sculptingPreview?.close()
        sculptingPreview = nil
        stationaryTime = 0
        waitsForExit = false
        guard canCreate, let gesture, let ball = simulation.commitSculpting(gesture) else { return }
        waitsForExit = waitForExit
        scene.place(radius: ball.radius, near: ball.center)
        refresh()
        changed()
    }

    func updateWindows(_ update: WindowUpdate) {
        // Tracker сообщает изменения раньше симуляции. Не подтверждаем устаревший снимок даже между кадрами.
        if let gesture = sculptingGesture,
           update.sliding || !simulation.isSculptingSource(gesture.source, unchangedFrom: trackedSurfaces, to: update.surfaces) {
            cancelSculpting()
        }
        trackedSurfaces = update.surfaces
        shelf = update.surfaces.first { WinterPlowPass(surface: $0) != nil }
        if let pass = plow {
            let waiting = shelf == nil && (update.elsewhere.contains(pass.surfaceID) || update.parked.contains(pass.surfaceID))
            if !waiting && (shelf?.id != pass.surfaceID || shelf?.frame != pass.shelf) {
                plow = nil
                plowWindow?.close()
                plowWindow = nil
            }
        }
        scene.updateWindows(update)
        refresh()
    }

    func dockSnowPositionChanged() {
        cancelSculpting()
        if let pass = plow, pass.clearsGround != simulation.snowInFrontOfDock {
            plow = nil
            refresh()
        }
    }

    @discardableResult
    func startPlow() -> Bool {
        guard canPlow, let shelf, let pass = WinterPlowPass(surface: shelf, clearsGround: simulation.snowInFrontOfDock) else { return false }
        plow = pass
        refresh()
        changed()
        return true
    }

    var canLaunchSleigh: Bool { canUseToys && sleigh == nil }

    @discardableResult
    func launchSleigh() -> Bool {
        guard canLaunchSleigh else { return false }
        let show = WinterSleighShow(screen: screenFrame)
        show.window.showsInScreenshots = showsInScreenshots
        if presentsWindows { show.window.orderFrontRegardless() }
        sleigh = show
        refresh()
        changed()
        return true
    }

    private func clearSleigh() {
        sleigh?.window.close()
        sleigh = nil
    }

    func updateTree(_ decorations: WinterTreeDecorations) {
        treeDecorations = decorations
        guard let tree = toyWindows[.tree] else { return }
        let frame = tree.frame
        let size = decorations.height.size
        let origin = CGPoint(x: frame.midX - size.width / 2, y: frame.minY)
        tree.setFrame(CGRect(origin: clampedOrigin(origin, size: size), size: size), display: false)
        alignTreeWithSupport()
        tree.redrawArtwork()
    }

    func hasToy(_ toy: WinterToy) -> Bool { toyWindows[toy] != nil }

    @discardableResult
    func toggleToy(_ toy: WinterToy, at point: CGPoint) -> Bool {
        guard canUseToys, point.x.isFinite, point.y.isFinite else { return false }
        if let existing = toyWindows.removeValue(forKey: toy) {
            if toy == .tree {
                treeSupport = nil
                treeMotion = WinterTreeMotion()
            }
            existing.close()
        } else {
            let size = toy == .tree ? treeDecorations.height.size : toy.size
            var origin = CGPoint(x: point.x + screenFrame.minX, y: point.y + screenFrame.minY)
            if toy == .tree {
                let left = clampedOrigin(origin, size: size).x - screenFrame.minX
                let ground = simulation.winterSurfaceY(at: left + size.width / 2, on: nil) ?? 0
                origin.y = max(origin.y, screenFrame.minY + ground + min(140, screenFrame.height * 0.25))
            }
            let frame = CGRect(origin: clampedOrigin(origin, size: size), size: size)
            let window = WinterToyWindow(frame: frame, interactive: true) { [weak self] rect in
                if toy == .tree, let self {
                    let tilt = NSAffineTransform()
                    tilt.translateX(by: rect.midX, yBy: rect.minY)
                    tilt.rotate(byRadians: treeMotion.lean)
                    tilt.translateX(by: -rect.midX, yBy: -rect.minY)
                    tilt.concat()
                    WinterTreeArtwork.draw(in: rect.insetBy(dx: rect.width * 0.026, dy: 0), decorations: treeDecorations)
                } else {
                    toy.draw(in: rect)
                }
            }
            window.title = "SeasonArt · " + toy.menuTitle
            window.showsInScreenshots = showsInScreenshots
            window.onDrag = { [weak self, weak window] origin in
                guard let self, let window, canUseToys else { return }
                let previous = window.frame.origin
                let next = clampedOrigin(origin, size: window.frame.size)
                guard previous != next else { return }
                if toy == .shovel {
                    let blade = WinterToy.shovelBlade
                    simulation.shovelSnow(
                        from: local(CGPoint(x: previous.x + blade.x, y: previous.y + blade.y)),
                        to: local(CGPoint(x: next.x + blade.x, y: next.y + blade.y)))
                }
                window.setFrameOrigin(next)
            }
            if toy == .tree {
                treeMotion.drop()
                window.onDragBegan = { [weak self, weak window] in
                    self?.treeSupport = nil
                    self?.treeMotion = WinterTreeMotion()
                    window?.redrawArtwork()
                }
                window.onDragEnded = { [weak self] in
                    guard let self else { return }
                    treeMotion.drop()
                    refresh()
                }
            }
            toyWindows[toy] = window
        }
        refresh()
        changed()
        return true
    }

    private func clampedOrigin(_ point: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: min(max(screenFrame.minX, point.x), max(screenFrame.minX, screenFrame.maxX - size.width)),
                y: min(max(screenFrame.minY, point.y), max(screenFrame.minY, screenFrame.maxY - size.height)))
    }

    private func treeRestingHeight(on surface: WindowSurface, at x: CGFloat) -> CGFloat? {
        guard surface.id != Marquee.id, x > surface.frame.minX + 2, x < surface.frame.maxX - 2 else { return nil }
        let roof = surface.winterRoof(at: x)
        let height = max(roof, simulation.winterSurfaceY(at: x, on: surface.id) ?? roof)
        let foot = CGRect(x: x - 2, y: height - 1, width: 4, height: 3)
        guard !surface.blockers.contains(where: { $0.intersects(foot) }) else { return nil }
        return height
    }

    func advanceTree(dt: TimeInterval) {
        guard canUseToys, let tree = toyWindows[.tree], !tree.isDragging, treeMotion.isMoving else { return }
        let frame = tree.frame
        if treeMotion.isFalling {
            let foot = local(CGPoint(x: frame.midX, y: frame.minY))
            var supportHeight = max(0, simulation.winterSurfaceY(at: foot.x, on: nil) ?? 0)
            var support: WindowSurface?
            for surface in trackedSurfaces {
                guard let height = treeRestingHeight(on: surface, at: foot.x),
                      height <= foot.y + 0.5, height > supportHeight else { continue }
                supportHeight = height
                support = surface
            }
            let result = treeMotion.fall(from: foot.y, toward: supportHeight, dt: dt)
            let origin = CGPoint(x: frame.minX, y: screenFrame.minY + result.height)
            if origin != frame.origin { tree.setFrameOrigin(origin) }
            if let impact = result.impact {
                treeSupport = support.map { ($0.id, foot.x - $0.frame.minX) }
                if impact >= 80 {
                    simulation.shedSnowFromTree(frame: CGRect(origin: local(origin), size: frame.size), impact: impact)
                }
            }
        } else {
            treeMotion.advanceSpring(dt: dt)
            alignTreeWithSupport()
        }
        tree.redrawArtwork()
    }

    private func alignTreeWithSupport() {
        guard let tree = toyWindows[.tree], !tree.isDragging, !treeMotion.isFalling else { return }
        let frame = tree.frame
        var x = frame.minX
        var height: CGFloat?
        if let anchor = treeSupport, let surface = trackedSurfaces.first(where: { $0.id == anchor.id }) {
            let center = screenFrame.minX + surface.frame.minX + anchor.offset
            let left = clampedOrigin(CGPoint(x: center - frame.width / 2, y: frame.minY), size: frame.size).x
            height = treeRestingHeight(on: surface, at: left + frame.width / 2 - screenFrame.minX)
            if height != nil { x = left }
        }
        if height == nil {
            let ground = max(0, simulation.winterSurfaceY(at: frame.midX - screenFrame.minX, on: nil) ?? 0)
            if treeSupport != nil, frame.minY - screenFrame.minY > ground + 0.5 {
                treeSupport = nil
                treeMotion.drop()
                return
            }
            treeSupport = nil
            height = ground
        }
        let position = CGPoint(x: x, y: screenFrame.minY + (height ?? 0) + treeMotion.lift)
        if position != frame.origin { tree.setFrameOrigin(position) }
    }

    private func scatterOutfit(of object: WinterObject) {
        guard presentsWindows, canUseToys, let decoration = object.decoration else { return }
        let frame = object.frame
        let origin = CGPoint(x: screenFrame.minX + frame.minX, y: screenFrame.minY + frame.minY)
        let flights = [
            WinterAccessoryFlight(rect: decoration.hat, screenOrigin: origin, direction: 1) {
                decoration.outfit.drawHat(decoration.hat)
            },
            WinterAccessoryFlight(rect: decoration.scarf.bounds, screenOrigin: origin, direction: -1) {
                decoration.outfit.drawScarf(decoration.scarf)
            }
        ]
        for flight in flights {
            flight.window.showsInScreenshots = showsInScreenshots
            flight.window.orderFrontRegardless()
        }
        accessoryFlights.append(contentsOf: flights)
    }

    private func clearAccessories() {
        for flight in accessoryFlights { flight.window.close() }
        accessoryFlights.removeAll()
    }

    private func clearToys() {
        clearSleigh()
        for window in toyWindows.values { window.close() }
        toyWindows.removeAll()
        treeSupport = nil
        treeMotion = WinterTreeMotion()
        clearAccessories()
    }

    func clear() {
        clearToys()
        cancelSculpting()
        scene.removeAll()
        plow = nil
        refresh()
        changed()
    }

    func fit(to frame: CGRect) {
        cancelSculpting()
        let offset = CGPoint(x: frame.minX - screenFrame.minX, y: frame.minY - screenFrame.minY)
        screenFrame = frame
        for window in toyWindows.values {
            let previous = window.frame.origin
            let next = CGPoint(x: previous.x + offset.x, y: previous.y + offset.y)
            window.setFrameOrigin(clampedOrigin(next, size: window.frame.size))
        }
        clearAccessories()
        clearSleigh()
        scene.resize(width: frame.width, height: frame.height)
        refresh()
    }

    func close() {
        guard !closed else { return }
        cancelSculpting()
        closed = true
        finderGarlands.close()
        clearToys()
        scene.removeAll()
        plow = nil
        timer?.invalidate()
        timer = nil
        let old = Array(windows.values)
        windows.removeAll()
        for window in old { window.close() }
        plowWindow?.close()
        plowWindow = nil
    }

    private func local(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - screenFrame.minX, y: point.y - screenFrame.minY)
    }

    private func refresh() {
        guard !closed, !syncing else { return }
        syncing = true
        defer { syncing = false }
        let visible = canUseToys
        if visible { alignTreeWithSupport() }
        if visible && presentsWindows && showsFinderGarlands {
            finderGarlands.display(trackedSurfaces, on: screenFrame)
        } else {
            finderGarlands.close()
        }
        if !visible || !canCreate { cancelSculpting() }
        if !visible {
            if toyWindows[.tree]?.isDragging == true { treeMotion.drop() }
            clearSleigh()
            clearAccessories()
            for object in scene.objects where object.isDragged { scene.cancelDragging(object.id) }
        }
        let ids = Set(scene.objects.map(\.id))
        for id in Array(windows.keys) where !ids.contains(id) { windows.removeValue(forKey: id)?.close() }
        for object in scene.objects {
            let window: WinterObjectWindow
            if let existing = windows[object.id] {
                window = existing
            } else {
                window = WinterObjectWindow(object: object, screenFrame: screenFrame)
                window.showsInScreenshots = showsInScreenshots
                let id = object.id
                window.dragBegan = { [weak self] point in
                    guard let self else { return }
                    scene.beginDragging(id, at: local(point))
                    refresh()
                }
                window.dragged = { [weak self] point, dt in
                    guard let self else { return }
                    scene.drag(id, to: local(point), dt: dt)
                    refresh()
                }
                window.dragEnded = { [weak self] idleTime in
                    guard let self else { return }
                    scene.endDragging(id, idleTime: idleTime)
                    refresh()
                    changed()
                }
                window.dragCancelled = { [weak self] in
                    self?.scene.cancelDragging(id)
                    self?.refresh()
                }
                windows[id] = window
            }
            window.title = object.isSnowman ? "SeasonArt · снеговик" : "SeasonArt · снежный шар"
            window.display(object: object, screenFrame: screenFrame,
                           shadows: WinterContactShadow.shadows(on: object, among: scene.objects))
            if visible && !object.parked && presentsWindows {
                if !window.isVisible { window.orderFrontRegardless() }
            } else if window.isVisible {
                window.orderOut(nil)
            }
        }
        if let pass = plow {
            let frame = pass.frame.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
            if plowWindow == nil {
                plowWindow = WinterPlowWindow(frame: frame)
                plowWindow?.title = "SeasonArt · снегоуборщик"
                plowWindow?.showsInScreenshots = showsInScreenshots
            }
            plowWindow?.display(frame: frame)
            if visible && presentsWindows && shelf?.id == pass.surfaceID {
                if plowWindow?.isVisible == false { plowWindow?.orderFrontRegardless() }
            } else {
                plowWindow?.orderOut(nil)
            }
        } else {
            plowWindow?.close()
            plowWindow = nil
        }
        for window in toyWindows.values {
            if visible && presentsWindows {
                if !window.isVisible { window.orderFrontRegardless() }
            } else if window.isVisible {
                window.orderOut(nil)
            }
        }
        scheduleTimer()
    }

    private func scheduleTimer() {
        guard needsUpdates || (canUseToys && (showsFinderGarlands || treeSupport != nil)) else {
            timer?.invalidate()
            timer = nil
            return
        }
        let interval: TimeInterval = treeMotion.isMoving || scene.isMoving || plow != nil || sleigh != nil || !accessoryFlights.isEmpty ? 0 : 0.2
        guard timer?.interval != interval else { return }
        timer?.invalidate()
        lastFrame = CACurrentMediaTime()
        let screen = NSScreen.screens.first { $0.frame == screenFrame } ?? NSScreen.main
        timer = WinterTicker(interval: interval, screen: screen) { [weak self] in self?.tick() }
    }

    private func tick() {
        if let gesture = sculptingGesture, !simulation.isSculptingSourceValid(gesture.source) {
            cancelSculpting()
        }
        if showsFinderGarlands || treeMotion.isFalling || treeSupport != nil { pollVisibleWindows() }
        let now = CACurrentMediaTime()
        // Сцена сама ограничивает догонку. Здесь время не обрезается, иначе задержка превращается в замедление.
        let dt = min(max(now - lastFrame, 0), 0.25)
        lastFrame = now
        if sleigh?.advance(dt) == false { sleigh = nil }
        accessoryFlights.removeAll { !$0.advance(dt) }
        advanceTree(dt: dt)
        scene.step(dt: dt)
        if var pass = plow, shelf?.id == pass.surfaceID {
            let before = pass.bladeX
            if let range = pass.advance(dt: dt) {
                simulation.plowDock(id: pass.surfaceID, fromX: range.lowerBound, toX: range.upperBound)
            }
            let swept = CGRect(x: pass.bladeX - 4, y: pass.frame.minY - 4,
                               width: max(8, before - pass.bladeX + 8), height: 150)
            scene.shoveObjects(in: swept, by: pass.bladeX - before)
            plow = pass.finished ? nil : pass
        }
        refresh()
    }
}
