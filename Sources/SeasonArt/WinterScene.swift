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

struct WinterObject: Identifiable {
    let id: UUID
    /// Состав снизу вверх. center задаёт центр нижнего шара.
    var sizes: [WinterBallSize]
    var center: CGPoint
    var velocity: CGVector
    var support: CGWindowID?
    var parked: Bool
    var isDragged: Bool

    var frame: CGRect {
        let radius = sizes.map(\.radius).max() ?? 0
        return CGRect(x: center.x - radius, y: center.y - (sizes.first?.radius ?? 0),
                      width: radius * 2, height: sizes.reduce(0) { $0 + $1.radius * 2 })
    }

    var isSnowman: Bool { sizes == [.large, .medium, .small] }
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
        guard objects.count < 12 else { return nil }
        var object = WinterObject(id: UUID(), sizes: [size], center: point, velocity: .zero,
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
        guard held.sizes.count == 1, let size = held.sizes.first else { return }
        let candidates = objects.indices.filter { candidate in
            let base = objects[candidate]
            let ordered = (base.sizes == [.large] && size == .medium)
                || (base.sizes == [.large, .medium] && size == .small)
            return candidate != index && ordered && !base.parked && !base.isDragged
                && abs(held.frame.minY - base.frame.maxY) <= 16
                && abs(held.center.x - base.center.x) <= min(size.radius, base.sizes.last!.radius) * 0.9
        }
        guard let base = candidates.min(by: {
            abs(objects[$0].center.x - held.center.x) < abs(objects[$1].center.x - held.center.x)
        }) else { return }
        objects[base].sizes.append(size)
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
                    objects[index].center.y = ground(at: objects[index].center.x) + objects[index].sizes[0].radius
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
        didLand(WinterImpact(support: support, x: object.center.x, radius: object.sizes[0].radius,
                             mass: object.sizes.reduce(0) { $0 + pow($1.radius / WinterBallSize.small.radius, 3) },
                             velocity: object.velocity))
        object.center.y = (surfaceHeight(support, object.center.x) ?? y) + object.sizes[0].radius
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
        object.center.y = y + object.sizes[0].radius
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
        let radius = object.sizes[0].radius
        object.center.y = min(max(object.center.y, radius), max(radius, height - object.frame.height + radius))
    }
}
