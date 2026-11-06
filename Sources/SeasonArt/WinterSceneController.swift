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
    private(set) var sculptingPreview: SnowSculptingPreviewWindow?
    private var sculptingGesture: SnowSculptingGesture?
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
            plowWindow?.showsInScreenshots = showsInScreenshots
            sculptingPreview?.showsInScreenshots = showsInScreenshots
        }
    }
    var canCreate: Bool { !closed && isEnabled && isActive && !isSuppressed && scene.objects.count < 12 }
    var canPlow: Bool { !closed && isEnabled && isActive && shelf != nil && plow == nil }
    var objectWindowCount: Int { windows.count }
    var isRunning: Bool { timer != nil }
    var hasObjects: Bool { !scene.objects.isEmpty || plow != nil || isSculpting }
    var needsUpdates: Bool { !closed && isEnabled && isActive && !isSuppressed && (hasObjects || simulation.hasSculptableSnow) }

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

    /// Вызывается до шага симуляции, чтобы обычная расчистка не забирала снег черновика.
    func updateAutomaticSculpting(at point: CGPoint, dt: TimeInterval, mouseButtons: Int) {
        guard !closed, isEnabled, isActive, !isSuppressed else {
            cancelSculpting()
            return
        }
        guard mouseButtons == 0 else {
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
                sculptingGesture = SnowSculptingGesture(source: source, at: start)
            }
            sculptingGesture?.include(point)
            if sculptingGesture?.size == .large {
                finishSculpting(waitForExit: true)
            } else if let gesture = sculptingGesture {
                if sculptingPreview == nil {
                    sculptingPreview = SnowSculptingPreviewWindow()
                    sculptingPreview?.showsInScreenshots = showsInScreenshots
                }
                sculptingPreview?.display(gesture, screenFrame: screenFrame)
                if presentsWindows { sculptingPreview?.orderFrontRegardless() }
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
        waitsForExit = waitForExit
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
