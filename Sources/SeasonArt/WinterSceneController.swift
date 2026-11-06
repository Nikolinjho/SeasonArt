import AppKit
import QuartzCore

/// Связывает чистую модель с небольшими интерактивными окнами одного экрана.
final class WinterSceneController {
    let scene: WinterScene
    private let simulation: SnowSimulation
    private let presentsWindows: Bool
    private var screenFrame: CGRect
    private var windows: [UUID: WinterObjectWindow] = [:]
    private var plowWindow: WinterPlowWindow?
    private var shelf: WindowSurface?
    private var timer: Timer?
    private var lastFrame: CFTimeInterval = 0
    private var syncing = false
    private var closed = false
    private(set) var plow: WinterPlowPass?
    private(set) var sculptingWindow: SnowSculptingWindow?
    private var sculptingGesture: SnowSculptingGesture?
    private var sculptingID: UUID?
    private var trackedSurfaces: [WindowSurface] = []
    var isSculpting: Bool { sculptingID != nil }
    var changed: () -> Void = {}

    var isEnabled = false { didSet { refresh() } }
    var isActive = true { didSet { refresh() } }
    var isSuppressed = false { didSet { refresh() } }
    var showsInScreenshots = false {
        didSet {
            for window in windows.values { window.showsInScreenshots = showsInScreenshots }
            plowWindow?.showsInScreenshots = showsInScreenshots
            sculptingWindow?.showsInScreenshots = showsInScreenshots
        }
    }
    var canCreate: Bool { !closed && isEnabled && isActive && !isSuppressed && scene.objects.count < 12 }
    var canPlow: Bool { !closed && isEnabled && isActive && shelf != nil && plow == nil }
    var objectWindowCount: Int { windows.count }
    var isRunning: Bool { timer != nil }
    var hasObjects: Bool { !scene.objects.isEmpty || plow != nil || isSculpting }
    var needsUpdates: Bool { !closed && isEnabled && isActive && !isSuppressed && hasObjects }

    init(screenFrame: CGRect, simulation: SnowSimulation, presentsWindows: Bool = true) {
        self.screenFrame = screenFrame
        self.simulation = simulation
        self.presentsWindows = presentsWindows
        scene = WinterScene(width: screenFrame.width, height: screenFrame.height)
        scene.surfaceHeight = { [weak simulation] id, x in simulation?.winterSurfaceY(at: x, on: id) }
    }

    @discardableResult
    func create(_ size: WinterBallSize, at point: CGPoint) -> UUID? {
        guard canCreate else { return nil }
        let id = scene.create(size, at: point)
        refresh()
        changed()
        return id
    }

    @discardableResult
    func startSculpting() -> Bool {
        cancelSculpting()
        guard canCreate else { return false }
        let token = UUID()
        sculptingID = token
        simulation.cursorInteracts = false
        let panel = SnowSculptingWindow(screenFrame: screenFrame)
        panel.showsInScreenshots = showsInScreenshots
        panel.began = { [weak self] point in
            guard let self, sculptingID == token else { return }
            beginSculpting(at: point)
        }
        panel.moved = { [weak self] point in
            guard let self, sculptingID == token else { return }
            continueSculpting(at: point)
        }
        panel.ended = { [weak self] point in
            guard let self, sculptingID == token else { return }
            finishSculpting(at: point)
        }
        panel.cancelled = { [weak self] in
            guard let self, sculptingID == token else { return }
            cancelSculpting()
        }
        sculptingWindow = panel
        refresh()
        changed()
        if presentsWindows { panel.present() }
        return true
    }

    func cancelSculpting() {
        guard isSculpting else { return }
        sculptingID = nil
        simulation.cursorInteracts = true
        sculptingGesture = nil
        let panel = sculptingWindow
        sculptingWindow = nil
        panel?.close()
        refresh()
        changed()
    }

    private func beginSculpting(at point: CGPoint) {
        guard canCreate, let source = simulation.sculptingSource(at: local(point)) else {
            cancelSculpting()
            return
        }
        sculptingGesture = SnowSculptingGesture(source: source, at: local(point))
        sculptingWindow?.display(sculptingGesture)
    }

    private func continueSculpting(at point: CGPoint) {
        guard let gesture = sculptingGesture else { return }
        guard canCreate, simulation.isSculptingSourceValid(gesture.source) else {
            cancelSculpting()
            return
        }
        sculptingGesture?.include(local(point))
        sculptingWindow?.display(sculptingGesture)
    }

    private func finishSculpting(at point: CGPoint) {
        continueSculpting(at: point)
        guard isSculpting else { return }
        let gesture = sculptingGesture
        // Сначала отцепляем обработчики: повторный mouseUp не подтверждает тот же снег.
        cancelSculpting()
        guard canCreate, let gesture, let ball = simulation.commitSculpting(gesture) else { return }
        create(ball.size, at: ball.center)
    }

    func updateWindows(_ update: WindowUpdate) {
        // Tracker сообщает изменения раньше симуляции. Не подтверждаем устаревший снимок даже между кадрами.
        if sculptingGesture != nil, update.sliding || trackedSurfaces != update.surfaces {
            cancelSculpting()
        }
        trackedSurfaces = update.surfaces
        shelf = update.surfaces.first { WinterPlowPass(surface: $0) != nil }
        if let pass = plow, shelf?.id != pass.surfaceID || shelf?.frame != pass.shelf {
            plow = nil
            plowWindow?.close()
            plowWindow = nil
        }
        scene.updateWindows(update)
        refresh()
    }

    @discardableResult
    func startPlow() -> Bool {
        guard canPlow, let shelf, let pass = WinterPlowPass(surface: shelf) else { return false }
        plow = pass
        refresh()
        changed()
        return true
    }

    func clear() {
        cancelSculpting()
        scene.removeAll()
        plow = nil
        refresh()
        changed()
    }

    func fit(to frame: CGRect) {
        cancelSculpting()
        screenFrame = frame
        scene.resize(width: frame.width, height: frame.height)
        refresh()
    }

    func close() {
        guard !closed else { return }
        cancelSculpting()
        closed = true
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
        let visible = isEnabled && isActive && !isSuppressed
        if !visible || !canCreate { cancelSculpting() }
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
                window.dragEnded = { [weak self] in
                    guard let self else { return }
                    scene.endDragging(id)
                    refresh()
                    changed()
                }
                windows[id] = window
            }
            window.title = object.isSnowman ? "SeasonArt · снеговик" : "SeasonArt · снежный шар"
            window.display(object: object, screenFrame: screenFrame)
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
            if visible && presentsWindows {
                if plowWindow?.isVisible == false { plowWindow?.orderFrontRegardless() }
            } else {
                plowWindow?.orderOut(nil)
            }
        } else {
            plowWindow?.close()
            plowWindow = nil
        }
        scheduleTimer()
    }

    private func scheduleTimer() {
        guard needsUpdates else {
            timer?.invalidate()
            timer = nil
            return
        }
        let interval = scene.isMoving || plow != nil ? 1.0 / 60 : 0.2
        guard timer == nil || abs(timer!.timeInterval - interval) > 0.001 else { return }
        timer?.invalidate()
        lastFrame = CACurrentMediaTime()
        let next = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    private func tick() {
        if let gesture = sculptingGesture, !simulation.isSculptingSourceValid(gesture.source) {
            cancelSculpting()
        }
        let now = CACurrentMediaTime()
        let dt = min(max(now - lastFrame, 0), 1.0 / 30)
        lastFrame = now
        scene.step(dt: dt)
        if var pass = plow {
            let before = pass.bladeX
            if let range = pass.advance(dt: dt) {
                simulation.plowDock(id: pass.surfaceID, fromX: range.lowerBound, toX: range.upperBound)
            }
            let swept = CGRect(x: pass.bladeX - 4, y: pass.shelf.maxY - 4,
                               width: max(8, before - pass.bladeX + 8), height: 150)
            scene.shoveObjects(in: swept, by: pass.bladeX - before)
            plow = pass.finished ? nil : pass
        }
        refresh()
    }
}
