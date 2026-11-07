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
    static let maximumObjects = 64
    private(set) var objects: [WinterObject] = []
    var hasCapacity: Bool { objects.count < Self.maximumObjects }
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
    private var objectSupports: [UUID: (id: UUID, center: CGPoint, radii: [CGFloat], carriedCenter: CGPoint)] = [:]
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
        guard hasCapacity, WinterBallGeometry.isValid(radius),
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
        objectSupports.removeValue(forKey: id)
        wakeUnsupportedObjects()
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
        objectSupports.removeValue(forKey: id)
        objects.remove(at: index)
        wakeUnsupportedObjects()
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
        for object in objects where !object.parked && !object.isDragged {
            for dock in visible.values where dock.isDock && object.frame.intersects(dock.frame) {
                let intersects = object.ballFrames.contains { frame in
                    let center = CGPoint(x: object.center.x, y: object.frame.minY + frame.midY)
                    let closest = closestDockPoint(dock, to: center)
                    return hypot(center.x - closest.x, center.y - closest.y) < frame.width / 2 - 0.000001
                }
                if intersects { resting.remove(object.id) }
            }
        }
        wakeUnsupportedObjects()
    }

    func step(dt: TimeInterval) {
        guard dt.isFinite, dt > 0 else { return }
        let duration = min(dt, 1.0 / 30)
        let steps = max(1, Int(ceil(duration * (objects.count > 1 ? 360 : 120))))
        for _ in 0..<steps { integrate(elapsed: CGFloat(duration / Double(steps))) }
    }

    private func integrate(elapsed: CGFloat) {
        wakeUnsupportedObjects()
        for index in objects.indices {
            guard !objects[index].isDragged, !objects[index].parked else { continue }
            if resting.contains(objects[index].id) {
                if objectSupports[objects[index].id] != nil { continue }
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
                      let y = supportHeight(surface, at: x, radius: objects[index].radii[0]), y >= 0,
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
        resolveDockContacts()
        resolveObjectContacts()
        resolveDockContacts()
        wakeUnsupportedObjects()
        let removed = objects.filter { pushed.contains($0.id) && ($0.frame.maxX < 0 || $0.frame.minX > width) }.map(\.id)
        objects.removeAll { removed.contains($0.id) }
        resting.subtract(removed)
        pushed.subtract(removed)
        for id in removed {
            bouncing.removeValue(forKey: id)
            objectSupports.removeValue(forKey: id)
        }
    }

    /// Dock имеет твёрдое тело: бок и низ не пропускают шары к земле под панелью.
    private func resolveDockContacts() {
        let docks = surfaces.values.filter { $0.isDock && visibleSupports.contains($0.id) }
        guard !docks.isEmpty else { return }
        for index in objects.indices where !objects[index].parked && !objects[index].isDragged {
            for dock in docks {
                guard objects[index].frame.intersects(dock.frame.insetBy(dx: -0.001, dy: -0.001)) else { continue }
                for _ in 0..<4 {
                    var corrected = false
                    for (component, frame) in objects[index].ballFrames.enumerated() {
                        let body = dock.frame
                        let radius = frame.width / 2
                        let center = CGPoint(x: objects[index].center.x, y: objects[index].frame.minY + frame.midY)
                        let closest = closestDockPoint(dock, to: center)
                        let dx = center.x - closest.x
                        let dy = center.y - closest.y
                        let distance = hypot(dx, dy)
                        guard distance < radius - 0.000001 else { continue }
                        var correction: CGVector
                        if distance > 0.000001 {
                            correction = CGVector(dx: dx / distance * (radius - distance),
                                                  dy: dy / distance * (radius - distance))
                        } else {
                            correction = .zero
                        }
                        func legal(_ move: CGVector) -> Bool {
                            let shifted = objects[index].frame.offsetBy(dx: move.dx, dy: move.dy)
                            return shifted.minY >= ground(at: objects[index].center.x + move.dx) - 0.001 &&
                                shifted.minX >= -0.001 && shifted.maxX <= width + 0.001 && shifted.maxY <= height + 0.001
                        }
                        if distance <= 0.000001 || !legal(correction) {
                            let faces = [CGVector(dx: body.minX - radius - center.x, dy: 0),
                                         CGVector(dx: body.maxX + radius - center.x, dy: 0),
                                         CGVector(dx: 0, dy: body.minY - radius - center.y),
                                         CGVector(dx: 0, dy: dockRestHeight(dock, at: center.x, radius: radius) + radius - center.y)]
                            guard let nearest = faces.filter({ legal($0) }).min(by: {
                                hypot($0.dx, $0.dy) < hypot($1.dx, $1.dy)
                            }) else { continue }
                            correction = nearest
                        }
                        let length = hypot(correction.dx, correction.dy)
                        guard length > 0 else { continue }
                        let nx = correction.dx / length
                        let ny = correction.dy / length
                        objects[index].center.x += correction.dx
                        objects[index].center.y += correction.dy
                        if ny > 0.999 && component == 0 {
                            land(&objects[index], on: dock.id, at: dockRestHeight(dock, at: center.x, radius: radius))
                        } else {
                            let incoming = objects[index].velocity.dx * nx + objects[index].velocity.dy * ny
                            if incoming < 0 {
                                objects[index].velocity.dx -= incoming * nx * 1.12
                                objects[index].velocity.dy -= incoming * ny * 1.12
                            }
                            objects[index].support = nil
                            resting.remove(objects[index].id)
                            objectSupports.removeValue(forKey: objects[index].id)
                        }
                        corrected = true
                    }
                    if !corrected { break }
                }
            }
        }
    }

    private func wakeUnsupportedObjects() {
        var changed = true
        while changed {
            changed = false
            for index in objects.indices {
                let id = objects[index].id
                guard let support = objectSupports[id] else { continue }
                if let base = objects.first(where: { $0.id == support.id }),
                   !base.parked, !base.isDragged, base.center == support.center, base.radii == support.radii,
                   objects[index].center == support.carriedCenter,
                   resting.contains(base.id), base.velocity.dx == 0, objects[index].velocity.dx == 0 {
                    continue
                }
                objectSupports.removeValue(forKey: id)
                resting.remove(id)
                changed = true
            }
        }
    }

    /// Прямоугольники отсекают далёкие пары, контакт проверяется по каждому шару фигуры.
    private func resolveObjectContacts() {
        let active = objects.indices.filter { !objects[$0].parked && !objects[$0].isDragged }
        guard active.count > 1 else { return }
        let components = objects.map(\.ballFrames)
        let inverseMasses = objects.map { object in 1 / object.radii.reduce(0) { $0 + pow($1, 3) } }
        for _ in 0..<12 {
            var maximumOverlap: CGFloat = 0
            let bounds = objects.map(\.frame)
            let sorted = active.sorted { bounds[$0].minX < bounds[$1].minX }
            for position in sorted.indices {
                let a = sorted[position]
                for next in sorted.indices where next > position {
                    let b = sorted[next]
                    if bounds[b].minX > bounds[a].maxX + 0.01 { break }
                    if bounds[b].minY > bounds[a].maxY + 0.01 ||
                       bounds[a].minY > bounds[b].maxY + 0.01 { continue }
                    let framesA = components[a]
                    let framesB = components[b]
                    for frameA in framesA {
                        for frameB in framesB {
                            let dx = objects[b].center.x - objects[a].center.x
                            let dy = objects[b].center.y - objects[b].radii[0] + frameB.midY -
                                objects[a].center.y + objects[a].radii[0] - frameA.midY
                            let distance = hypot(dx, dy)
                            let radius = (frameA.width + frameB.width) / 2
                            guard distance < radius + 0.002 else { continue }
                            let nx: CGFloat = distance > 0.000001 ? dx / distance : 1
                            let ny: CGFloat = distance > 0.000001 ? dy / distance : 0
                            let inverseA: CGFloat = ny > 0.8 && resting.contains(objects[a].id) ? 0 : inverseMasses[a]
                            let inverseB: CGFloat = ny < -0.8 && resting.contains(objects[b].id) ? 0 : inverseMasses[b]
                            let total = inverseA + inverseB
                            guard total > 0 else { continue }
                            let overlap = max(0, radius - distance)
                            maximumOverlap = max(maximumOverlap, overlap)
                            objects[a].center.x -= nx * overlap * inverseA / total
                            objects[a].center.y -= ny * overlap * inverseA / total
                            objects[b].center.x += nx * overlap * inverseB / total
                            objects[b].center.y += ny * overlap * inverseB / total
                            let relative = (objects[b].velocity.dx - objects[a].velocity.dx) * nx +
                                (objects[b].velocity.dy - objects[a].velocity.dy) * ny
                            if relative < 0 {
                                let restitution: CGFloat = relative < -220 ? 0.12 : 0
                                let impulse = -(1 + restitution) * relative / total
                                objects[a].velocity.dx -= impulse * inverseA * nx
                                objects[a].velocity.dy -= impulse * inverseA * ny
                                objects[b].velocity.dx += impulse * inverseB * nx
                                objects[b].velocity.dy += impulse * inverseB * ny
                            }
                            constrainContact(a)
                            constrainContact(b)
                            if ny > 0.99 { restOnObject(b, base: a) }
                            if ny < -0.99 { restOnObject(a, base: b) }
                        }
                    }
                }
            }
            if maximumOverlap < 0.001 { break }
        }
    }

    private func constrainContact(_ index: Int) {
        if !pushed.contains(objects[index].id) { clampX(&objects[index]) }
        let floor = objects[index].support.flatMap { surfaces[$0] }.flatMap {
            supportHeight($0, at: objects[index].center.x, radius: objects[index].radii[0])
        } ?? ground(at: objects[index].center.x)
        if objects[index].frame.minY < floor {
            objects[index].center.y = floor + objects[index].radii[0]
            objects[index].velocity.dy = max(0, objects[index].velocity.dy)
        }
        if abs(objects[index].velocity.dx) < WinterMotion.sleepSpeed { objects[index].velocity.dx = 0 }
        if objects[index].velocity.dy > WinterMotion.sleepSpeed {
            resting.remove(objects[index].id)
            objectSupports.removeValue(forKey: objects[index].id)
            objects[index].support = nil
        }
    }

    private func restOnObject(_ index: Int, base: Int) {
        guard resting.contains(objects[base].id), objects[base].velocity == .zero,
              abs(objects[index].velocity.dy) < WinterMotion.sleepSpeed,
              objects[index].velocity.dx == 0 else { return }
        objects[index].velocity = .zero
        objects[index].support = nil
        resting.insert(objects[index].id)
        objectSupports[objects[index].id] = (objects[base].id, objects[base].center, objects[base].radii, objects[index].center)
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
        wakeUnsupportedObjects()
    }

    func removeAll() {
        objects.removeAll()
        resting.removeAll()
        objectSupports.removeAll()
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
        for id in removed {
            bouncing.removeValue(forKey: id)
            objectSupports.removeValue(forKey: id)
        }
        resting.subtract(removed)
        wakeUnsupportedObjects()
    }

    private func ground(at x: CGFloat) -> CGFloat { surfaceHeight(nil, x) ?? 0 }

    /// Физическая кромка повторяет superellipse основания SnowLayer, без высоты снега.
    private func dockRoof(_ surface: WindowSurface, at x: CGFloat) -> CGFloat {
        let radius = max(0, min(surface.cornerRadius, surface.frame.width / 2, surface.frame.height / 2))
        guard radius > 0 else { return surface.frame.maxY }
        let distance = max(0, min(x - surface.frame.minX, surface.frame.maxX - x))
        let u = max(0, 1 - distance / radius)
        let exponent = max(1, surface.cornerExponent)
        return surface.frame.maxY - radius * (1 - pow(max(0, 1 - pow(u, exponent)), 1 / exponent))
    }

    /// Нижняя точка шара учитывает всю ширину контакта с выпуклым силуэтом.
    private func dockRestHeight(_ surface: WindowSurface, at x: CGFloat, radius: CGFloat) -> CGFloat {
        guard radius > 0, surface.cornerRadius > 0 else { return dockRoof(surface, at: x) }
        let corner = min(surface.cornerRadius, surface.frame.width / 2, surface.frame.height / 2)
        if x >= surface.frame.minX + corner && x <= surface.frame.maxX - corner { return surface.frame.maxY }
        var low = max(surface.frame.minX, x - radius)
        var high = min(surface.frame.maxX, x + radius)
        guard low <= high else { return dockRoof(surface, at: x) }
        func clearance(_ sample: CGFloat) -> CGFloat {
            dockRoof(surface, at: sample) + sqrt(max(0, radius * radius - pow(sample - x, 2)))
        }
        for _ in 0..<40 {
            let a = low + (high - low) / 3
            let b = high - (high - low) / 3
            if clearance(a) < clearance(b) { low = a } else { high = b }
        }
        return clearance((low + high) / 2) - radius
    }

    private func closestDockPoint(_ surface: WindowSurface, to point: CGPoint) -> CGPoint {
        let body = surface.frame
        if point.x >= body.minX, point.x <= body.maxX,
           point.y >= body.minY, point.y <= dockRoof(surface, at: point.x) { return point }
        let radius = max(0, min(surface.cornerRadius, body.width / 2, body.height / 2))
        let sideTop = body.maxY - radius
        if point.y >= body.maxY, point.x >= body.minX + radius, point.x <= body.maxX - radius {
            return CGPoint(x: point.x, y: body.maxY)
        }
        if point.x <= body.minX, point.y >= body.minY, point.y <= sideTop {
            return CGPoint(x: body.minX, y: point.y)
        }
        if point.x >= body.maxX, point.y >= body.minY, point.y <= sideTop {
            return CGPoint(x: body.maxX, y: point.y)
        }
        var candidates = [CGPoint(x: min(max(point.x, body.minX), body.maxX), y: body.minY),
                          CGPoint(x: body.minX, y: min(max(point.y, body.minY), sideTop)),
                          CGPoint(x: body.maxX, y: min(max(point.y, body.minY), sideTop)),
                          CGPoint(x: min(max(point.x, body.minX + radius), body.maxX - radius), y: body.maxY)]
        func squaredDistance(_ x: CGFloat) -> CGFloat {
            pow(x - point.x, 2) + pow(dockRoof(surface, at: x) - point.y, 2)
        }
        if radius > 0 {
            for start in [body.minX, body.maxX - radius] {
                var low = start
                var high = start + radius
                for _ in 0..<40 {
                    let a = low + (high - low) / 3
                    let b = high - (high - low) / 3
                    if squaredDistance(a) < squaredDistance(b) { high = b } else { low = a }
                }
                let x = (low + high) / 2
                candidates.append(CGPoint(x: x, y: dockRoof(surface, at: x)))
            }
        }
        return candidates.min { hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y) }!
    }

    private func supportHeight(_ surface: WindowSurface, at x: CGFloat, radius: CGFloat = 0) -> CGFloat? {
        guard x >= surface.frame.minX, x <= surface.frame.maxX else { return nil }
        let physicalTop = surface.isDock ? dockRestHeight(surface, at: x, radius: radius) : -CGFloat.infinity
        let fallback = surface.isDock ? physicalTop : surface.frame.maxY
        let y = max(surfaceHeight(surface.id, x) ?? fallback, physicalTop)
        guard !surface.blockers.contains(where: { $0.contains(CGPoint(x: x, y: y + 1)) }) else { return nil }
        return y
    }

    private func land(_ object: inout WinterObject, on support: CGWindowID?, at y: CGFloat) {
        objectSupports.removeValue(forKey: object.id)
        let contact = WinterContact(support: support)
        if bouncing[object.id] != contact {
            didLand(WinterImpact(support: support, x: object.center.x, radius: object.radii[0],
                             mass: object.radii.reduce(0) { $0 + pow($1 / WinterBallSize.small.radius, 3) },
                             velocity: object.velocity))
        }
        let physicalTop = support.flatMap { surfaces[$0] }.map {
            $0.isDock ? dockRestHeight($0, at: object.center.x, radius: object.radii[0]) : -CGFloat.infinity
        } ?? -CGFloat.infinity
        object.center.y = max(surfaceHeight(support, object.center.x) ?? y, physicalTop) + object.radii[0]
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
        guard let y = supportHeight(surface, at: object.center.x, radius: object.radii[0]), y >= 0,
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
