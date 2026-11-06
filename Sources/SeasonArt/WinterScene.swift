import Foundation
import CoreGraphics

enum WinterBallSize: Int, CaseIterable {
    case small, medium, large

    var radius: CGFloat {
        switch self {
        case .small: return 14
        case .medium: return 21
        case .large: return 28
        }
    }
}

enum WinterBallGeometry {
    static let minimumRadius: CGFloat = 6
    static let maximumRadius: CGFloat = 36

    static func isValid(_ radius: CGFloat) -> Bool {
        radius.isFinite && (minimumRadius...maximumRadius).contains(radius)
    }
}

struct WinterObject: Identifiable {
    let id: UUID
    /// Состав снизу вверх. center задаёт центр нижнего шара.
    var radii: [CGFloat]
    var center: CGPoint
    var velocity: CGVector
    var support: CGWindowID?
    var parked: Bool
    var isDragged: Bool

    var rotation: CGFloat = 0

    /// Локальные границы шаров: стык перекрывает 15% диаметра меньшего из соседей.
    var ballFrames: [CGRect] {
        let widest = radii.max() ?? 0
        var bottom: CGFloat = 0
        return radii.enumerated().map { index, radius in
            if index > 0 { bottom -= min(radii[index - 1], radius) * 0.3 }
            let rect = CGRect(x: widest - radius, y: bottom,
                              width: radius * 2, height: radius * 2)
            bottom = rect.maxY
            return rect
        }
    }

    var frame: CGRect {
        let radius = radii.max() ?? 0
        return CGRect(x: center.x - radius, y: center.y - (radii.first ?? 0),
                      width: radius * 2, height: ballFrames.last?.maxY ?? 0)
    }

    var isSnowman: Bool { radii.count == 3 }
}

/// Геометрия украшений использует радиус соответствующего шара.
struct WinterDecoration {
    let eyes: [CGRect]
    let buttons: [CGRect]
    let nose: [CGPoint]
    let scarf: [CGRect]
}

extension WinterObject {
    var decoration: WinterDecoration? {
        guard isSnowman else { return nil }
        let frames = ballFrames
        let x = frames[0].midX
        let base = frames[0]
        let torso = frames[1]
        let head = frames[2]
        let headScale = radii[2] / 14
        let torsoScale = radii[1] / 21
        let baseScale = radii[0] / 28
        let neckScale = min(radii[1], radii[2]) / 14
        func dot(x: CGFloat, y: CGFloat, scale: CGFloat) -> CGRect {
            CGRect(x: x - 1.8 * scale, y: y - 1.8 * scale, width: 3.6 * scale, height: 3.6 * scale)
        }
        return WinterDecoration(
            eyes: [-5, 5].map { dot(x: x + CGFloat($0) * headScale, y: head.midY + 3 * headScale, scale: headScale) },
            buttons: [dot(x: x, y: torso.midY + 10 * torsoScale, scale: torsoScale),
                      dot(x: x, y: torso.midY - 3 * torsoScale, scale: torsoScale),
                      dot(x: x, y: base.midY + 11 * baseScale, scale: baseScale)],
            nose: [CGPoint(x: x - headScale, y: head.midY - headScale),
                   CGPoint(x: x + 12 * headScale, y: head.midY - 4 * headScale),
                   CGPoint(x: x - headScale, y: head.midY - 6 * headScale)],
            scarf: [CGRect(x: x - 14 * neckScale, y: head.minY - 2 * neckScale,
                           width: 28 * neckScale, height: 6 * neckScale),
                    CGRect(x: x + 6 * neckScale, y: head.minY - 18 * torsoScale,
                           width: 6 * neckScale, height: 20 * torsoScale)])
    }
}

/// Удар до остановки игрушки, с массой относительно маленького шара.
struct WinterImpact {
    let support: CGWindowID?
    let x: CGFloat
    let radius: CGFloat
    let mass: CGFloat
    let velocity: CGVector
}

private enum WinterMotion {
    static let history: TimeInterval = 0.12
    static let maximumSpeed: CGFloat = 900
    static let outlierSpeedRatio: CGFloat = 3
    static let coherentDirection: CGFloat = 0.95
    static let placementSpeed: CGFloat = 85
    static let gravity: CGFloat = 1200
    static let friction: CGFloat = 2.8
    static let sleepSpeed: CGFloat = 2
    static let bounceThreshold: CGFloat = 220
    static let restitution: CGFloat = 0.17
}

private enum WinterContact: Equatable {
    case ground
    case window(CGWindowID)

    init(support: CGWindowID?) {
        self = support.map { .window($0) } ?? .ground
    }
}

final class WinterScene {
    private(set) var objects: [WinterObject] = []
    /// Абсолютная высота снега. nil использует геометрию опоры или землю.
    var surfaceHeight: (_ id: CGWindowID?, _ x: CGFloat) -> CGFloat? = { _, _ in nil }
    var didLand: (WinterImpact) -> Void = { _ in }
    var isMoving: Bool {
        objects.contains { !$0.parked && ($0.isDragged || !resting.contains($0.id) || $0.velocity.dx != 0) }
    }

    private var width: CGFloat
    private var height: CGFloat
    private var surfaces: [CGWindowID: WindowSurface] = [:]
    private var visibleSupports: Set<CGWindowID> = []
    private var resting: Set<UUID> = []
    private var pushed: Set<UUID> = []
    private var bouncing: [UUID: WinterContact] = [:]
    private var dragOffset: CGPoint = .zero
    private var captured: UUID?
    private var dragHistory: [(duration: TimeInterval, velocity: CGVector)] = []
    private var fastDragSample: (duration: TimeInterval, velocity: CGVector)?

    init(width: CGFloat, height: CGFloat) {
        self.width = max(0, width)
        self.height = max(0, height)
    }

    @discardableResult
    func create(_ size: WinterBallSize, at point: CGPoint) -> UUID? {
        return create(radius: size.radius, at: point)
    }

    @discardableResult
    func create(radius: CGFloat, at point: CGPoint) -> UUID? {
        guard objects.count < 12, WinterBallGeometry.isValid(radius),
              point.x.isFinite, point.y.isFinite else { return nil }
        var object = WinterObject(id: UUID(), radii: [radius], center: point, velocity: .zero,
                                  support: nil, parked: false, isDragged: false)
        clamp(&object)
        objects.append(object)
        return object.id
    }

    func beginDragging(_ id: UUID, at point: CGPoint) {
        guard captured != id, objects.contains(where: { $0.id == id && !$0.parked }) else { return }
        if let captured { cancelDragging(captured) }
        guard let index = objects.firstIndex(where: { $0.id == id }) else { return }
        captured = id
        dragHistory.removeAll()
        fastDragSample = nil
        dragOffset = CGPoint(x: objects[index].center.x - point.x, y: objects[index].center.y - point.y)
        objects[index].isDragged = true
        objects[index].support = nil
        objects[index].velocity = .zero
        resting.remove(id)
        pushed.remove(id)
        bouncing.removeValue(forKey: id)
    }

    func drag(_ id: UUID, to point: CGPoint, dt: TimeInterval) {
        guard captured == id, let index = objects.firstIndex(where: { $0.id == id }) else { return }
        guard point.x.isFinite, point.y.isFinite else { return }
        let previous = objects[index].center
        objects[index].center = CGPoint(x: point.x + dragOffset.x, y: point.y + dragOffset.y)
        clamp(&objects[index])
        let dx = objects[index].center.x - previous.x
        let dy = objects[index].center.y - previous.y
        guard dt.isFinite, dt > 0 else {
            dragHistory.removeAll()
            fastDragSample = nil
            objects[index].velocity = .zero
            return
        }
        let velocity = CGVector(dx: dx / dt, dy: dy / dt)
        let speed = hypot(velocity.dx, velocity.dy)
        guard speed.isFinite else {
            dragHistory.removeAll()
            fastDragSample = nil
            objects[index].velocity = .zero
            return
        }
        if speed > WinterMotion.maximumSpeed * WinterMotion.outlierSpeedRatio {
            // Одиночный скачок ждёт подтверждения соседним сегментом того же движения.
            let previous = fastDragSample
            fastDragSample = (dt, velocity)
            if let previous, isCoherent(previous.velocity, with: velocity) {
                if dragHistory.isEmpty { appendDragSample(duration: previous.duration, velocity: previous.velocity) }
                appendDragSample(duration: dt, velocity: velocity)
            } else {
                dragHistory.removeAll()
            }
        } else {
            fastDragSample = nil
            appendDragSample(duration: dt, velocity: velocity)
        }
        objects[index].velocity = releaseVelocity
    }

    private func isCoherent(_ previous: CGVector, with current: CGVector) -> Bool {
        let a = hypot(previous.dx, previous.dy)
        let b = hypot(current.dx, current.dy)
        let alignment = (previous.dx / a) * (current.dx / b) + (previous.dy / a) * (current.dy / b)
        return alignment >= WinterMotion.coherentDirection && min(a, b) / max(a, b) >= 0.5
    }

    private func appendDragSample(duration: TimeInterval, velocity: CGVector) {
        dragHistory.append((min(duration, WinterMotion.history), velocity))
        var excess = dragHistory.reduce(0) { $0 + $1.duration } - WinterMotion.history
        while excess > 0.0000001, !dragHistory.isEmpty {
            let removed = min(excess, dragHistory[0].duration)
            dragHistory[0].duration -= removed
            excess -= removed
            if dragHistory[0].duration <= 0.0000001 { dragHistory.removeFirst() }
        }
    }

    private var releaseVelocity: CGVector {
        let duration = dragHistory.reduce(0) { $0 + $1.duration }
        guard duration > 0 else { return .zero }
        var result = dragHistory.reduce(CGVector.zero) { sum, sample in
            CGVector(dx: sum.dx + sample.velocity.dx * sample.duration / duration,
                     dy: sum.dy + sample.velocity.dy * sample.duration / duration)
        }
        let speed = hypot(result.dx, result.dy)
        if speed > WinterMotion.maximumSpeed {
            result.dx *= WinterMotion.maximumSpeed / speed
            result.dy *= WinterMotion.maximumSpeed / speed
        }
        return result
    }

    func cancelDragging(_ id: UUID) {
        guard captured == id, let index = objects.firstIndex(where: { $0.id == id }) else { return }
        captured = nil
        dragHistory.removeAll()
        fastDragSample = nil
        objects[index].isDragged = false
        objects[index].velocity = .zero
    }

    func endDragging(_ id: UUID, idleTime: TimeInterval = 0) {
        guard captured == id, let index = objects.firstIndex(where: { $0.id == id }) else { return }
        let hasPendingMotion = fastDragSample != nil && !(idleTime.isFinite && idleTime >= WinterMotion.history)
        if idleTime.isFinite, idleTime > 0 { appendDragSample(duration: idleTime, velocity: .zero) }
        objects[index].velocity = releaseVelocity
        captured = nil
        dragHistory.removeAll()
        fastDragSample = nil
        objects[index].isDragged = false
        let held = objects[index]
        guard !hasPendingMotion, held.radii.count == 1, let radius = held.radii.first,
              hypot(held.velocity.dx, held.velocity.dy) <= WinterMotion.placementSpeed else { return }
        let candidates = objects.indices.filter { candidate in
            let base = objects[candidate]
            let canStack = (1...2).contains(base.radii.count)
            let contactRadius = min(radius, base.radii.last ?? radius)
            let tolerance = min(8, max(2, contactRadius * 0.35))
            let gap = held.frame.minY - base.frame.maxY
            // Допускаем касание и перекрытие готового стыка, но не притягиваем маленькие шары издалека.
            let hasContact = gap <= tolerance && gap >= -contactRadius * 0.3 - tolerance
            return candidate != index && canStack && !base.parked && !base.isDragged
                && hasContact
                && abs(held.center.x - base.center.x) <= min(radius, base.radii.last!) * 0.9
        }
        guard let base = candidates.min(by: {
            abs(objects[$0].center.x - held.center.x) < abs(objects[$1].center.x - held.center.x)
        }) else { return }
        objects[base].radii.append(radius)
        resting.remove(id)
        objects.remove(at: index)
    }

    func updateWindows(_ update: WindowUpdate) {
        visibleSupports = Set(update.surfaces.map(\.id))
        let visible = Dictionary(update.surfaces.map { ($0.id, $0) }, uniquingKeysWith: { _, next in next })
        for index in objects.indices {
            guard let support = objects[index].support, !objects[index].isDragged else { continue }
            guard let next = visible[support] else {
                objects[index].parked = update.elsewhere.contains(support) || update.parked.contains(support)
                if !objects[index].parked {
                    objects[index].support = nil
                    resting.remove(objects[index].id)
                }
                continue
            }
            if let previous = surfaces[support] {
                objects[index].center.x += next.frame.minX - previous.frame.minX
                objects[index].center.y += next.frame.maxY - previous.frame.maxY
            }
            objects[index].parked = false
            fit(&objects[index], on: next, clampToSupport: objects[index].velocity.dx == 0)
        }
        surfaces = visible.merging(surfaces.filter { update.elsewhere.contains($0.key) || update.parked.contains($0.key) }) { current, _ in current }
    }

    func step(dt: TimeInterval) {
        guard dt.isFinite, dt > 0 else { return }
        let duration = min(dt, 1.0 / 30)
        let steps = max(1, Int(ceil(duration * 120)))
        for _ in 0..<steps { integrate(elapsed: CGFloat(duration / Double(steps))) }
    }

    private func integrate(elapsed: CGFloat) {
        for index in objects.indices {
            guard !objects[index].isDragged, !objects[index].parked else { continue }
            if resting.contains(objects[index].id) {
                let previousX = objects[index].center.x
                let decay = exp(-WinterMotion.friction * elapsed)
                objects[index].center.x += objects[index].velocity.dx * (1 - decay) / WinterMotion.friction
                objects[index].velocity.dx *= decay
                if abs(objects[index].velocity.dx) < WinterMotion.sleepSpeed { objects[index].velocity.dx = 0 }
                if !pushed.contains(objects[index].id) { clampX(&objects[index]) }
                if objects[index].radii.count == 1 {
                    objects[index].rotation -= (objects[index].center.x - previousX) / objects[index].radii[0]
                }
                if let support = objects[index].support, let surface = surfaces[support] {
                    fit(&objects[index], on: surface)
                } else {
                    objects[index].center.y = ground(at: objects[index].center.x) + objects[index].radii[0]
                }
                if resting.contains(objects[index].id) { continue }
            }
            let beforeBottom = objects[index].frame.minY
            objects[index].center.x += objects[index].velocity.dx * elapsed
            objects[index].center.y += objects[index].velocity.dy * elapsed - WinterMotion.gravity * elapsed * elapsed / 2
            objects[index].velocity.dy -= WinterMotion.gravity * elapsed
            if !pushed.contains(objects[index].id) { clampX(&objects[index]) }
            guard objects[index].velocity.dy <= 0 else { continue }
            let x = objects[index].center.x
            let afterBottom = objects[index].frame.minY
            let candidates = surfaces.values.compactMap { surface -> (CGWindowID, CGFloat)? in
                let radius = objects[index].frame.width / 2
                guard visibleSupports.contains(surface.id),
                      max(radius, surface.frame.minX + radius) <= min(width - radius, surface.frame.maxX - radius),
                      let y = supportHeight(surface, at: x), y >= 0,
                      y + objects[index].frame.height <= height,
                      y <= beforeBottom + 0.01, y >= afterBottom else { return nil }
                return (surface.id, y)
            }
            if let landing = candidates.max(by: { $0.1 < $1.1 }) {
                land(&objects[index], on: landing.0, at: landing.1)
            } else if afterBottom <= ground(at: x) {
                land(&objects[index], on: nil, at: ground(at: x))
            }
        }
        let removed = objects.filter { pushed.contains($0.id) && ($0.frame.maxX < 0 || $0.frame.minX > width) }.map(\.id)
        objects.removeAll { removed.contains($0.id) }
        resting.subtract(removed)
        pushed.subtract(removed)
        for id in removed { bouncing.removeValue(forKey: id) }
    }

    func resize(width: CGFloat, height: CGFloat) {
        self.width = max(0, width)
        self.height = max(0, height)
        for index in objects.indices where !objects[index].parked {
            clamp(&objects[index])
            if let support = objects[index].support, let surface = surfaces[support] {
                fit(&objects[index], on: surface, clampToSupport: true)
            }
        }
    }

    func removeAll() {
        objects.removeAll()
        resting.removeAll()
        pushed.removeAll()
        bouncing.removeAll()
        captured = nil
        dragOffset = .zero
        dragHistory.removeAll()
        fastDragSample = nil
    }

    func shoveObjects(in rect: CGRect, by dx: CGFloat) {
        guard dx.isFinite else { return }
        for index in objects.indices where !objects[index].parked && !objects[index].isDragged && objects[index].frame.intersects(rect) {
            objects[index].center.x += dx
            pushed.insert(objects[index].id)
            resting.remove(objects[index].id)
            objects[index].support = nil
        }
        let removed = objects.filter { pushed.contains($0.id) && ($0.frame.maxX < 0 || $0.frame.minX > width) }.map(\.id)
        objects.removeAll { removed.contains($0.id) }
        pushed.subtract(removed)
        for id in removed { bouncing.removeValue(forKey: id) }
        resting.subtract(removed)
    }

    private func ground(at x: CGFloat) -> CGFloat { surfaceHeight(nil, x) ?? 0 }

    private func supportHeight(_ surface: WindowSurface, at x: CGFloat) -> CGFloat? {
        guard x >= surface.frame.minX, x <= surface.frame.maxX else { return nil }
        let y = surfaceHeight(surface.id, x) ?? surface.frame.maxY
        guard !surface.blockers.contains(where: { $0.contains(CGPoint(x: x, y: y + 1)) }) else { return nil }
        return y
    }

    private func land(_ object: inout WinterObject, on support: CGWindowID?, at y: CGFloat) {
        let contact = WinterContact(support: support)
        if bouncing[object.id] != contact {
            didLand(WinterImpact(support: support, x: object.center.x, radius: object.radii[0],
                             mass: object.radii.reduce(0) { $0 + pow($1 / WinterBallSize.small.radius, 3) },
                             velocity: object.velocity))
        }
        object.center.y = (surfaceHeight(support, object.center.x) ?? y) + object.radii[0]
        object.support = support
        let rebound = -object.velocity.dy * WinterMotion.restitution
        if object.velocity.dy < -WinterMotion.bounceThreshold {
            bouncing[object.id] = contact
            object.velocity.dy = rebound
            object.support = nil
            resting.remove(object.id)
        } else {
            bouncing.removeValue(forKey: object.id)
            object.velocity.dy = 0
            if abs(object.velocity.dx) < WinterMotion.sleepSpeed { object.velocity.dx = 0 }
            resting.insert(object.id)
        }
    }

    private func fit(_ object: inout WinterObject, on surface: WindowSurface, clampToSupport: Bool = false) {
        let radius = object.frame.width / 2
        let low = max(radius, surface.frame.minX + radius)
        let high = min(width - radius, surface.frame.maxX - radius)
        guard low <= high else { detach(&object); return }
        if clampToSupport { object.center.x = min(max(object.center.x, low), high) }
        guard let y = supportHeight(surface, at: object.center.x), y >= 0,
              y + object.frame.height <= height else { detach(&object); return }
        object.center.y = y + object.radii[0]
    }

    private func detach(_ object: inout WinterObject) {
        object.support = nil
        resting.remove(object.id)
    }

    private func clampX(_ object: inout WinterObject) {
        let radius = object.frame.width / 2
        object.center.x = min(max(object.center.x, radius), max(radius, width - radius))
    }

    private func clamp(_ object: inout WinterObject) {
        clampX(&object)
        let radius = object.radii[0]
        object.center.y = min(max(object.center.y, radius), max(radius, height - object.frame.height + radius))
    }
}
