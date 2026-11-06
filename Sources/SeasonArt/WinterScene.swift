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

final class WinterScene {
    private(set) var objects: [WinterObject] = []
    /// Абсолютная высота снега. nil использует геометрию опоры или землю.
    var surfaceHeight: (_ id: CGWindowID?, _ x: CGFloat) -> CGFloat? = { _, _ in nil }
    var didLand: (WinterImpact) -> Void = { _ in }
    var isMoving: Bool {
        objects.contains { !$0.parked && ($0.isDragged || !resting.contains($0.id)) }
    }

    private var width: CGFloat
    private var height: CGFloat
    private var surfaces: [CGWindowID: WindowSurface] = [:]
    private var visibleSupports: Set<CGWindowID> = []
    private var resting: Set<UUID> = []
    private var pushed: Set<UUID> = []
    private var dragOffset: CGPoint = .zero
    private var captured: UUID?

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
        if let captured { endDragging(captured) }
        guard let index = objects.firstIndex(where: { $0.id == id }) else { return }
        captured = id
        dragOffset = CGPoint(x: objects[index].center.x - point.x, y: objects[index].center.y - point.y)
        objects[index].isDragged = true
        objects[index].support = nil
        objects[index].velocity = .zero
        resting.remove(id)
        pushed.remove(id)
    }

    func drag(_ id: UUID, to point: CGPoint, dt: TimeInterval) {
        guard captured == id, let index = objects.firstIndex(where: { $0.id == id }) else { return }
        let previous = objects[index].center
        objects[index].center = CGPoint(x: point.x + dragOffset.x, y: point.y + dragOffset.y)
        clamp(&objects[index])
        guard dt.isFinite, dt > 0 else { objects[index].velocity = .zero; return }
        var velocity = CGVector(dx: (objects[index].center.x - previous.x) / dt,
                                dy: (objects[index].center.y - previous.y) / dt)
        let speed = hypot(velocity.dx, velocity.dy)
        if speed > 900 { velocity.dx *= 900 / speed; velocity.dy *= 900 / speed }
        objects[index].velocity = velocity
    }

    func endDragging(_ id: UUID) {
        guard captured == id, let index = objects.firstIndex(where: { $0.id == id }) else { return }
        captured = nil
        objects[index].isDragged = false
        let held = objects[index]
        guard held.radii.count == 1, let radius = held.radii.first else { return }
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
            fit(&objects[index], on: next)
        }
        surfaces = visible.merging(surfaces.filter { update.elsewhere.contains($0.key) || update.parked.contains($0.key) }) { current, _ in current }
    }

    func step(dt: TimeInterval) {
        guard dt.isFinite, dt > 0 else { return }
        let elapsed = CGFloat(min(dt, 1.0 / 30))
        for index in objects.indices {
            guard !objects[index].isDragged, !objects[index].parked else { continue }
            if resting.contains(objects[index].id) {
                if let support = objects[index].support, let surface = surfaces[support] {
                    fit(&objects[index], on: surface)
                } else {
                    objects[index].center.y = ground(at: objects[index].center.x) + objects[index].radii[0]
                }
                if resting.contains(objects[index].id) { continue }
            }
            let beforeBottom = objects[index].frame.minY
            objects[index].velocity.dy -= 1200 * elapsed
            objects[index].center.x += objects[index].velocity.dx * elapsed
            objects[index].center.y += objects[index].velocity.dy * elapsed
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
    }

    func resize(width: CGFloat, height: CGFloat) {
        self.width = max(0, width)
        self.height = max(0, height)
        for index in objects.indices where !objects[index].parked {
            clamp(&objects[index])
            if let support = objects[index].support, let surface = surfaces[support] {
                fit(&objects[index], on: surface)
            }
        }
    }

    func removeAll() {
        objects.removeAll()
        resting.removeAll()
        pushed.removeAll()
        captured = nil
        dragOffset = .zero
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
        didLand(WinterImpact(support: support, x: object.center.x, radius: object.radii[0],
                             mass: object.radii.reduce(0) { $0 + pow($1 / WinterBallSize.small.radius, 3) },
                             velocity: object.velocity))
        object.center.y = (surfaceHeight(support, object.center.x) ?? y) + object.radii[0]
        object.support = support
        object.velocity = .zero
        resting.insert(object.id)
    }

    private func fit(_ object: inout WinterObject, on surface: WindowSurface) {
        let radius = object.frame.width / 2
        let low = max(radius, surface.frame.minX + radius)
        let high = min(width - radius, surface.frame.maxX - radius)
        guard low <= high else { detach(&object); return }
        object.center.x = min(max(object.center.x, low), high)
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
