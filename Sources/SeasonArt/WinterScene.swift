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
    static let jointOverlap: CGFloat = 0.6

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
    /// Угловая скорость одиночного шара, рад/с, положительная против часовой стрелки.
    var spin: CGFloat = 0
    var ballDamage: [WinterBallDamage] = []

    /// Локальные границы шаров: стык перекрывает 30% диаметра меньшего из соседей.
    var ballFrames: [CGRect] {
        let widest = radii.max() ?? 0
        var bottom: CGFloat = 0
        return radii.enumerated().map { index, radius in
            if index > 0 { bottom -= min(radii[index - 1], radius) * WinterBallGeometry.jointOverlap }
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

    /// Круги шаров в координатах сцены.
    var ballCircles: [(center: CGPoint, radius: CGFloat)] {
        let origin = frame.origin
        return ballFrames.map { (CGPoint(x: origin.x + $0.midX, y: origin.y + $0.midY), $0.width / 2) }
    }
}

/// Геометрия украшений использует радиус соответствующего шара.
struct WinterDecoration {
    let eyes: [CGRect]
    let mouth: [CGRect]
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
            mouth: [(-6.0, -6.5), (-3.2, -8.2), (0, -8.8), (3.2, -8.2), (6.0, -6.5)].map { dx, dy in
                dot(x: x + dx * headScale, y: head.midY + dy * headScale, scale: headScale * 0.5)
            },
            buttons: [dot(x: x, y: min(torso.midY + 10 * torsoScale,
                                      head.minY - 2 * neckScale - 3.8 * torsoScale), scale: torsoScale),
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
    /// Трение снега о снег.
    static let ballFriction: CGFloat = 0.5
    /// Липкий снег удерживает шар на шаре при отклонении до 20° и медленном движении.
    static let stickyNormal: CGFloat = 0.94
    static let stickySpeed: CGFloat = 40
    /// Сопротивление качению по другому шару: снег мнётся в месте касания.
    static let rollingDrag: CGFloat = 10
    /// Фиксированный шаг: на экранах 60 и 120 Гц в кадр помещается целое число шагов.
    static let fixedStep: TimeInterval = 1.0 / 240
    /// После сна или долгой задержки шары не пролетают экран за один кадр.
    static let maximumCatchUp: TimeInterval = 0.25
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
    var dockContact: (_ id: CGWindowID, _ x: CGFloat, _ radius: CGFloat) -> (top: CGFloat, floor: CGFloat)? = { _, _, _ in nil }
    /// Текущий корпус Dock: при увеличении он шире рамки окна. nil оставляет рамку окна.
    var dockBody: (_ id: CGWindowID) -> CGRect? = { _ in nil }
    var didLand: (WinterImpact) -> Void = { _ in }
    var didChip: (WinterBallChip) -> Void = { _ in }
    var isMoving: Bool {
        !settledStacks.isEmpty || objects.contains { !$0.parked && ($0.isDragged || !resting.contains($0.id) || $0.velocity.dx != 0) }
    }

    private var width: CGFloat
    private var height: CGFloat
    private var surfaces: [CGWindowID: WindowSurface] = [:]
    private var visibleSupports: Set<CGWindowID> = []
    private var resting: Set<UUID> = []
    private var pushed: Set<UUID> = []
    private var objectSupports: [UUID: (id: UUID, center: CGPoint, radii: [CGFloat], carriedCenter: CGPoint)] = [:]
    private var bouncing: [UUID: WinterContact] = [:]
    private var settledStacks: [UUID: (ids: [UUID], duration: TimeInterval)] = [:]
    private var dragOffset: CGPoint = .zero
    private var captured: UUID?
    private var dragHistory: [(duration: TimeInterval, velocity: CGVector)] = []
    private var fastDragSample: (duration: TimeInterval, velocity: CGVector)?
    /// Реальное время, ещё не пройденное фиксированными шагами.
    private var pendingTime: TimeInterval = 0
    /// Корпуса Dock при последней синхронизации опор.
    private var lastDockBodies: [CGWindowID: CGRect] = [:]
    /// Центры после последнего решения контактов.
    private var solvedCenters: [UUID: CGPoint] = [:]

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
        synchronizeDockSupports()
        return object.id
    }

    /// Ставит шар в ближайшее свободное место у точки, иначе кладёт его сверху на мешающие фигуры.
    @discardableResult
    func place(radius: CGFloat, near point: CGPoint) -> UUID? {
        guard hasCapacity, WinterBallGeometry.isValid(radius), point.x.isFinite, point.y.isFinite else { return nil }
        func blockers(at center: CGPoint) -> [Int] { self.blockers(radius: radius, at: center) }
        func clampedX(_ x: CGFloat) -> CGFloat { min(max(x, radius), max(radius, width - radius)) }
        // Новый шар появляется там, где его лепили, и отодвигает соседей, если за ними есть место.
        let spot = CGPoint(x: clampedX(point.x), y: point.y)
        if makeRoom(radius: radius, at: spot) { return create(radius: radius, at: spot) }
        // Иначе та же опора рядом, на расстоянии до трёх диаметров, затем сверху на мешающие фигуры.
        for offset in 0...24 {
            for side: CGFloat in offset == 0 ? [0] : [-1, 1] {
                let center = CGPoint(x: clampedX(point.x + side * CGFloat(offset) * radius / 4), y: point.y)
                if blockers(at: center).isEmpty { return create(radius: radius, at: center) }
            }
        }
        var center = CGPoint(x: clampedX(point.x), y: point.y)
        for _ in 0..<Self.maximumObjects {
            let hits = blockers(at: center)
            guard !hits.isEmpty else { break }
            center.y = hits.map { objects[$0].frame.maxY }.max()! + radius + 0.5
        }
        // Экран заполнен до верха: шар появляется как раньше, решатель разведёт его с соседями.
        guard center.y + radius <= height, blockers(at: center).isEmpty else { return create(radius: radius, at: point) }
        return create(radius: radius, at: center)
    }

    /// Отодвигает фигуры вбок от круга, по цепочке. Если цепочка упирается в край экрана, ничего не меняет и возвращает false.
    @discardableResult
    func makeRoom(radius: CGFloat, at center: CGPoint) -> Bool {
        let saved = objects
        var pushers: [(center: CGPoint, radius: CGFloat, direction: CGFloat?, owner: UUID?)] = [(center, radius, nil, nil)]
        var moved: Set<UUID> = []
        while let pusher = pushers.popLast() {
            for index in objects.indices where !objects[index].parked && !objects[index].isDragged && objects[index].id != pusher.owner {
                var shift: CGFloat = 0
                var direction = pusher.direction ?? (objects[index].center.x >= pusher.center.x ? 1 : -1)
                for circle in objects[index].ballCircles {
                    let dy = circle.center.y - pusher.center.y
                    let reach = circle.radius + pusher.radius
                    guard abs(dy) < reach - 0.01 else { continue }
                    let dx = circle.center.x - pusher.center.x
                    guard hypot(dx, dy) < reach - 0.01 else { continue }
                    if pusher.direction == nil, abs(dx) < 0.01 { direction = 1 }
                    // Сдвиг вдоль направления до касания кругов.
                    let needed = sqrt(reach * reach - dy * dy) - dx * direction
                    shift = max(shift, needed + 0.01)
                }
                guard shift > 0 else { continue }
                if moved.contains(objects[index].id) && pusher.direction == nil { continue }
                let half = objects[index].frame.width / 2
                let target = objects[index].center.x + shift * direction
                guard target - half >= -0.01, target + half <= width + 0.01, moved.count < Self.maximumObjects * 2 else {
                    objects = saved
                    return false
                }
                objects[index].center.x = target
                objects[index].velocity = .zero
                moved.insert(objects[index].id)
                for circle in objects[index].ballCircles { pushers.append((circle.center, circle.radius, direction, objects[index].id)) }
            }
        }
        for index in objects.indices where moved.contains(objects[index].id) {
            resting.remove(objects[index].id)
            objectSupports.removeValue(forKey: objects[index].id)
            if let support = objects[index].support, let surface = surfaces[support],
               objects[index].center.x - objects[index].frame.width / 2 < surface.frame.minX
                || objects[index].center.x + objects[index].frame.width / 2 > surface.frame.maxX {
                // Отодвинутый с края окна шар падает.
                objects[index].support = nil
            }
        }
        wakeUnsupportedObjects()
        return true
    }

    /// Место занято шаром любой видимой фигуры.
    func isFree(radius: CGFloat, at center: CGPoint) -> Bool { blockers(radius: radius, at: center).isEmpty }

    private func blockers(radius: CGFloat, at center: CGPoint) -> [Int] {
        objects.indices.filter { index in
            !objects[index].parked && objects[index].ballCircles.contains {
                hypot($0.center.x - center.x, $0.center.y - center.y) < $0.radius + radius - 0.01
            }
        }
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
        objects[index].spin = 0
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
        restOnSupports(index)
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

    /// Шар в руке упирается в лежащую под ним фигуру сразу, а не следующим шагом: окно не показывает его внутри неё.
    private func restOnSupports(_ index: Int) {
        for _ in 0..<4 {
            var moved = false
            for other in objects.indices where other != index && !objects[other].parked && resting.contains(objects[other].id) {
                for support in objects[other].ballCircles {
                    for held in objects[index].ballCircles {
                        let dx = held.center.x - support.center.x
                        let dy = held.center.y - support.center.y
                        let distance = hypot(dx, dy)
                        let overlap = held.radius + support.radius - distance
                        guard overlap > 0, distance > 0.000001, dy / distance > 0.8 else { continue }
                        objects[index].center.x += dx / distance * overlap
                        objects[index].center.y += dy / distance * overlap
                        moved = true
                    }
                }
            }
            if !moved { break }
            clamp(&objects[index])
        }
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
        guard !hasPendingMotion, (1...2).contains(held.radii.count), let radius = held.radii.first,
              hypot(held.velocity.dx, held.velocity.dy) <= WinterMotion.placementSpeed else { return }
        let candidates = objects.indices.filter { candidate in
            let base = objects[candidate]
            let canStack = (1...2).contains(base.radii.count) && base.radii.count + held.radii.count <= 3
            let contactRadius = min(radius, base.radii.last ?? radius)
            let tolerance = min(8, max(2, contactRadius * 0.35))
            let gap = held.frame.minY - base.frame.maxY
            // Допускаем касание и перекрытие готового стыка, но не притягиваем маленькие шары издалека.
            let hasContact = gap <= tolerance && gap >= -contactRadius * WinterBallGeometry.jointOverlap - tolerance
            return candidate != index && canStack && !base.parked && !base.isDragged
                && hasContact
                && abs(held.center.x - base.center.x) <= min(radius, base.radii.last!) * 0.9
        }
        guard let base = candidates.min(by: {
            abs(objects[$0].center.x - held.center.x) < abs(objects[$1].center.x - held.center.x)
        }) else { return }
        merge([id], onto: objects[base].id)
    }

    private func merge(_ ids: [UUID], onto base: UUID) {
        guard let index = objects.firstIndex(where: { $0.id == base }) else { return }
        for id in ids {
            guard let held = objects.first(where: { $0.id == id }) else { continue }
            // Порядок повреждений совпадает с порядком шаров, в том числе у целых шаров.
            objects[index].ballDamage = objects[index].assembledDamage
            objects[index].ballDamage.append(contentsOf: held.assembledDamage)
            objects[index].radii.append(contentsOf: held.radii)
            resting.remove(id)
            objectSupports.removeValue(forKey: id)
            bouncing.removeValue(forKey: id)
            pushed.remove(id)
        }
        objects.removeAll { ids.contains($0.id) }
        wakeUnsupportedObjects()
    }

    /// Три шара, спокойно стоящие друг на друге, собираются и после завершения падения.
    private func assembleSettledSnowmen(dt: TimeInterval) {
        var next: [UUID: (ids: [UUID], duration: TimeInterval)] = [:]
        var ready: [(base: UUID, ids: [UUID])] = []
        func stable(_ object: WinterObject) -> Bool {
            !object.parked && !object.isDragged && resting.contains(object.id) && object.velocity == .zero
        }
        for base in objects where stable(base) && objectSupports[base.id] == nil && base.radii.count < 3 {
            var chain = [base.id]
            var count = base.radii.count
            while count < 3, let top = chain.last,
                  let upper = objects.first(where: { stable($0) && objectSupports[$0.id]?.id == top }) {
                chain.append(upper.id)
                count += upper.radii.count
            }
            guard count == 3 else { continue }
            let previous = settledStacks[base.id]
            let duration = (previous?.ids == chain ? previous!.duration : 0) + dt
            if duration >= 0.2 {
                ready.append((base.id, Array(chain.dropFirst())))
            } else {
                next[base.id] = (chain, duration)
            }
        }
        settledStacks = next
        for stack in ready { merge(stack.ids, onto: stack.base) }
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

    /// Продвигает физику на реальное время кадра фиксированными шагами. Задержка догоняется, а не замедляет движение.
    func step(dt: TimeInterval) {
        guard dt.isFinite, dt > 0 else { return }
        pendingTime = min(pendingTime + dt, WinterMotion.maximumCatchUp)
        guard isMoving else {
            // Спящим шарам достаточно одной проверки опор: снег под ними мог осесть.
            pendingTime = 0
            integrate(elapsed: 0)
            assembleSettledSnowmen(dt: dt)
            return
        }
        var elapsed: TimeInterval = 0
        while pendingTime >= WinterMotion.fixedStep - 1e-9 {
            integrate(elapsed: CGFloat(WinterMotion.fixedStep))
            pendingTime -= WinterMotion.fixedStep
            elapsed += WinterMotion.fixedStep
        }
        pendingTime = max(0, pendingTime)
        if elapsed > 0 { assembleSettledSnowmen(dt: elapsed) }
    }

    /// Обновляет контакт в кадре Dock, не продвигая время физики повторно.
    @discardableResult
    func synchronizeDockSupports() -> Bool {
        let before = objects.map(\.center)
        let docks = surfaces.values.filter { $0.isDock && visibleSupports.contains($0.id) }
        for index in objects.indices where !objects[index].parked && !objects[index].isDragged {
            if resting.contains(objects[index].id), let id = objects[index].support,
               let surface = surfaces[id], surface.isDock {
                fit(&objects[index], on: surface)
            }
            // Увеличение расширяет Dock в стороны: горка может оказаться под шаром на земле.
            for surface in docks {
                guard let contact = dockContact(surface.id, objects[index].center.x, objects[index].radii[0]),
                      contact.floor.isFinite, objects[index].frame.minY < contact.floor,
                      contact.top + objects[index].frame.height <= height,
                      supportHeight(surface, at: objects[index].center.x, radius: objects[index].radii[0]) != nil
                else { continue }
                land(&objects[index], on: surface.id, at: contact.top)
            }
        }
        // Расширяющийся Dock сдвигает шары сразу, а не на следующем шаге покоя. Шар, вставший на горку, уже снаружи.
        let bodies = Dictionary(physicalDocks.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
        let widened = bodies.contains { id, body in lastDockBodies[id].map { $0 != body } ?? false }
        lastDockBodies = bodies
        if widened { resolveDockContacts() }
        guard before != objects.map(\.center) else { return false }
        wakeUnsupportedObjects()
        resolveObjectContacts()
        return true
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
                    // По земле шар катится без проскальзывания.
                    objects[index].spin = -objects[index].velocity.dx / objects[index].radii[0]
                }
                if let support = objects[index].support, let surface = surfaces[support] {
                    fit(&objects[index], on: surface)
                } else {
                    let top = ground(at: objects[index].center.x)
                    let bottom = restingHeight(top, for: objects[index])
                    objects[index].center.y = bottom + objects[index].radii[0]
                }
                if resting.contains(objects[index].id) { continue }
            }
            let beforeBottom = objects[index].frame.minY
            if objects[index].radii.count == 1 { objects[index].rotation += objects[index].spin * elapsed }
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
    /// Dock с текущей шириной: увеличенные иконки раздвигают корпус в стороны.
    private var physicalDocks: [WindowSurface] {
        surfaces.values.filter { $0.isDock && visibleSupports.contains($0.id) }.map { dock in
            guard let body = dockBody(dock.id), body.width > 0, body.minX.isFinite, body.width.isFinite else { return dock }
            return WindowSurface(id: dock.id, frame: CGRect(x: body.minX, y: dock.frame.minY, width: body.width, height: dock.frame.height),
                                 blockers: dock.blockers, cover: dock.cover, cornerRadius: dock.cornerRadius,
                                 cornerExponent: dock.cornerExponent, isDock: true)
        }
    }

    private func resolveDockContacts() {
        let docks = physicalDocks
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
        guard !objectSupports.isEmpty else { return }
        var changed = true
        while changed {
            changed = false
            let indices = Dictionary(objects.indices.map { (objects[$0].id, $0) }, uniquingKeysWith: { first, _ in first })
            for (id, support) in objectSupports {
                if let index = indices[id], let baseIndex = indices[support.id] {
                    let base = objects[baseIndex]
                    if !base.parked, !base.isDragged, base.center == support.center, base.radii == support.radii,
                       objects[index].center == support.carriedCenter,
                       resting.contains(base.id), base.velocity.dx == 0, objects[index].velocity.dx == 0 {
                        continue
                    }
                }
                objectSupports.removeValue(forKey: id)
                resting.remove(id)
                changed = true
            }
        }
    }

    /// Прямоугольники отсекают далёкие пары, контакт проверяется по каждому шару фигуры.
    private func resolveObjectContacts() {
        // Шар в руке — кинематическое тело: расталкивает соседей и упирается в то, что сдвинуть нельзя.
        let active = objects.indices.filter { !objects[$0].parked }
        guard active.count > 1 else { return }
        // Спящий шар на месте прошлого решения уже разведён с такими же соседями.
        func sleeps(_ index: Int) -> Bool {
            resting.contains(objects[index].id) && objects[index].velocity == .zero
                && solvedCenters[objects[index].id] == objects[index].center
        }
        defer { solvedCenters = Dictionary(objects.map { ($0.id, $0.center) }, uniquingKeysWith: { first, _ in first }) }
        guard active.contains(where: { !sleeps($0) }) else { return }
        var components = objects.map(\.collisionBallFrames)
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
                    if sleeps(a) && sleeps(b) { continue }
                    let framesA = components[a]
                    let framesB = components[b]
                    for (componentA, frameA) in framesA.enumerated() {
                        for (componentB, frameB) in framesB.enumerated() {
                            let dx = objects[b].frame.minX + frameB.midX - objects[a].frame.minX - frameA.midX
                            let dy = objects[b].center.y - objects[b].radii[0] + frameB.midY -
                                objects[a].center.y + objects[a].radii[0] - frameA.midY
                            let distance = hypot(dx, dy)
                            let nx: CGFloat = distance > 0.000001 ? dx / distance : 1
                            let ny: CGFloat = distance > 0.000001 ? dy / distance : 0
                            func reach(_ frame: CGRect) -> CGFloat {
                                1 / sqrt(pow(nx / (frame.width / 2), 2) + pow(ny / (frame.height / 2), 2))
                            }
                            let radius = reach(frameA) + reach(frameB)
                            guard distance < radius + 0.002 else { continue }
                            var inverseA: CGFloat = ny > 0.8 && resting.contains(objects[a].id) ? 0 : inverseMasses[a]
                            var inverseB: CGFloat = ny < -0.8 && resting.contains(objects[b].id) ? 0 : inverseMasses[b]
                            let draggedA = objects[a].isDragged
                            let draggedB = objects[b].isDragged
                            if draggedA && draggedB { continue }
                            if draggedA { inverseA = inverseB > 0 ? 0 : inverseMasses[a] }
                            if draggedB { inverseB = inverseA > 0 ? 0 : inverseMasses[b] }
                            let total = inverseA + inverseB
                            guard total > 0 else { continue }
                            let overlap = max(0, radius - distance)
                            maximumOverlap = max(maximumOverlap, overlap)
                            objects[a].center.x -= nx * overlap * inverseA / total
                            objects[a].center.y -= ny * overlap * inverseA / total
                            objects[b].center.x += nx * overlap * inverseB / total
                            objects[b].center.y += ny * overlap * inverseB / total
                            // Скорость шара в руке задаёт курсор, импульсы её не меняют.
                            let velocityA: CGFloat = draggedA ? 0 : inverseA
                            let velocityB: CGFloat = draggedB ? 0 : inverseB
                            let velocityTotal = velocityA + velocityB
                            let relative = (objects[b].velocity.dx - objects[a].velocity.dx) * nx +
                                (objects[b].velocity.dy - objects[a].velocity.dy) * ny
                            var normalImpulse: CGFloat = 0
                            if relative < 0, velocityTotal > 0 {
                                if ny > 0.65 {
                                    chip(&objects[b], component: componentB, speed: -relative, angle: atan2(-ny, -nx),
                                         at: CGPoint(x: objects[b].center.x, y: objects[b].frame.minY + frameB.minY))
                                    components[b] = objects[b].collisionBallFrames
                                } else if ny < -0.65 {
                                    chip(&objects[a], component: componentA, speed: -relative, angle: atan2(ny, nx),
                                         at: CGPoint(x: objects[a].center.x, y: objects[a].frame.minY + frameA.minY))
                                    components[a] = objects[a].collisionBallFrames
                                }
                                let restitution: CGFloat = relative < -220 ? 0.12 : 0
                                normalImpulse = -(1 + restitution) * relative / velocityTotal
                                objects[a].velocity.dx -= normalImpulse * velocityA * nx
                                objects[a].velocity.dy -= normalImpulse * velocityA * ny
                                objects[b].velocity.dx += normalImpulse * velocityB * nx
                                objects[b].velocity.dy += normalImpulse * velocityB * ny
                            }
                            if normalImpulse > 0 {
                                applyFriction(a, b, nx: nx, ny: ny, reachA: reach(frameA), reachB: reach(frameB),
                                              inverseA: velocityA, inverseB: velocityB, normalImpulse: normalImpulse)
                            }
                            if !draggedA { constrainContact(a) }
                            if !draggedB { constrainContact(b) }
                            if ny > WinterMotion.stickyNormal, !draggedB { restOnObject(b, base: a) }
                            if ny < -WinterMotion.stickyNormal, !draggedA { restOnObject(a, base: b) }
                        }
                    }
                }
            }
            if maximumOverlap < 0.001 { break }
        }
    }

    private func constrainContact(_ index: Int) {
        if !pushed.contains(objects[index].id) { clampX(&objects[index]) }
        let surface = objects[index].support.flatMap { surfaces[$0] }
        let top = surface.flatMap {
            supportHeight($0, at: objects[index].center.x, radius: objects[index].radii[0])
        } ?? ground(at: objects[index].center.x)
        let floor = restingHeight(top, for: objects[index], on: surface)
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

    /// Кулоново трение в точке касания: скольжение переходит во вращение, качение по снегу быстро гаснет.
    private func applyFriction(_ a: Int, _ b: Int, nx: CGFloat, ny: CGFloat, reachA: CGFloat, reachB: CGFloat,
                               inverseA: CGFloat, inverseB: CGFloat, normalImpulse: CGFloat) {
        let tx = -ny
        let ty = nx
        let rollsA = objects[a].radii.count == 1 && inverseA > 0
        let rollsB = objects[b].radii.count == 1 && inverseB > 0
        let spinA = rollsA ? objects[a].spin : 0
        let spinB = rollsB ? objects[b].spin : 0
        let pointA = CGVector(dx: objects[a].velocity.dx - spinA * ny * reachA, dy: objects[a].velocity.dy + spinA * nx * reachA)
        let pointB = CGVector(dx: objects[b].velocity.dx + spinB * ny * reachB, dy: objects[b].velocity.dy - spinB * nx * reachB)
        let sliding = (pointB.dx - pointA.dx) * tx + (pointB.dy - pointA.dy) * ty
        // Для сплошного шара r²/I = 5/(2m).
        let resistance = inverseA + inverseB + (rollsA ? 2.5 * inverseA : 0) + (rollsB ? 2.5 * inverseB : 0)
        guard resistance > 0 else { return }
        let limit = WinterMotion.ballFriction * normalImpulse
        let impulse = min(max(-sliding / resistance, -limit), limit)
        objects[a].velocity.dx -= impulse * inverseA * tx
        objects[a].velocity.dy -= impulse * inverseA * ty
        objects[b].velocity.dx += impulse * inverseB * tx
        objects[b].velocity.dy += impulse * inverseB * ty
        if rollsA { objects[a].spin -= 2.5 * impulse * inverseA / reachA }
        if rollsB { objects[b].spin -= 2.5 * impulse * inverseB / reachB }
        // Касание мнёт снег: качение шара по шару затухает.
        let drag = exp(-WinterMotion.rollingDrag * CGFloat(WinterMotion.fixedStep))
        for (index, rolls) in [(a, rollsA), (b, rollsB)] where rolls {
            objects[index].spin *= drag
        }
        if inverseB > 0, ny > 0.5 {
            let along = objects[b].velocity.dx * tx + objects[b].velocity.dy * ty
            objects[b].velocity.dx -= along * (1 - drag) * tx
            objects[b].velocity.dy -= along * (1 - drag) * ty
        } else if inverseA > 0, ny < -0.5 {
            let along = objects[a].velocity.dx * tx + objects[a].velocity.dy * ty
            objects[a].velocity.dx -= along * (1 - drag) * tx
            objects[a].velocity.dy -= along * (1 - drag) * ty
        }
    }

    private func restOnObject(_ index: Int, base: Int) {
        guard resting.contains(objects[base].id), objects[base].velocity == .zero,
              hypot(objects[index].velocity.dx, objects[index].velocity.dy) < WinterMotion.stickySpeed else { return }
        objects[index].velocity = .zero
        objects[index].spin = 0
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
        pendingTime = 0
        settledStacks.removeAll()
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

    /// Свежий снег не поднимает фигуру. Движущаяся иконка поднимает её вместе с лежащим на ней снегом.
    private func restingHeight(_ height: CGFloat, for object: WinterObject, on surface: WindowSurface? = nil) -> CGFloat {
        guard resting.contains(object.id), object.velocity == .zero else { return height }
        let physicalTop = surface.map {
            $0.isDock ? dockRestHeight($0, at: object.center.x, radius: object.radii[0]) : -CGFloat.infinity
        } ?? 0
        let movingFloor = surface.flatMap { dockContact($0.id, object.center.x, object.radii[0]) }?.floor ?? -CGFloat.infinity
        return max(physicalTop, movingFloor, min(object.frame.minY, height))
    }

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
        let contact = dockContact(surface.id, x, radius)
        guard contact != nil || (x >= surface.frame.minX && x <= surface.frame.maxX) else { return nil }
        let physicalTop = surface.isDock ? dockRestHeight(surface, at: x, radius: radius) : -CGFloat.infinity
        let fallback = surface.isDock ? physicalTop : surface.frame.maxY
        let y = max(contact?.top ?? surfaceHeight(surface.id, x) ?? fallback, physicalTop)
        guard !surface.blockers.contains(where: { $0.contains(CGPoint(x: x, y: y + 1)) }) else { return nil }
        return y
    }

    private func land(_ object: inout WinterObject, on support: CGWindowID?, at y: CGFloat) {
        objectSupports.removeValue(forKey: object.id)
        let contact = WinterContact(support: support)
        if bouncing[object.id] != contact {
            chip(&object, component: 0, speed: -object.velocity.dy, angle: -.pi / 2,
                 at: CGPoint(x: object.center.x, y: y + 1))
            didLand(WinterImpact(support: support, x: object.center.x, radius: object.radii[0],
                             mass: object.radii.reduce(0) { $0 + pow($1 / WinterBallSize.small.radius, 3) },
                             velocity: object.velocity))
        }
        let physicalTop = support.flatMap { surfaces[$0] }.map {
            $0.isDock ? dockRestHeight($0, at: object.center.x, radius: object.radii[0]) : -CGFloat.infinity
        } ?? -CGFloat.infinity
        let contactTop = support.flatMap { dockContact($0, object.center.x, object.radii[0]) }?.top
        object.center.y = max(contactTop ?? surfaceHeight(support, object.center.x) ?? y, physicalTop) + object.radii[0]
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

    private func chip(_ object: inout WinterObject, component: Int, speed: CGFloat, angle: CGFloat, at point: CGPoint) {
        var damage = object.damage(for: component)
        let amount = damage.hit(speed: speed, angle: angle - (object.radii.count == 1 ? object.rotation : 0))
        guard amount > 0 else { return }
        while object.ballDamage.count < object.radii.count { object.ballDamage.append(WinterBallDamage()) }
        object.ballDamage[component] = damage
        didChip(WinterBallChip(center: point, radius: object.radii[component], strength: amount))
    }

    private func fit(_ object: inout WinterObject, on surface: WindowSurface, clampToSupport: Bool = false) {
        let radius = object.frame.width / 2
        let low = max(radius, surface.frame.minX + radius)
        let high = min(width - radius, surface.frame.maxX - radius)
        guard low <= high else { detach(&object); return }
        if clampToSupport { object.center.x = min(max(object.center.x, low), high) }
        guard let y = supportHeight(surface, at: object.center.x, radius: object.radii[0]), y >= 0,
              y + object.frame.height <= height else { detach(&object); return }
        let bottom = restingHeight(y, for: object, on: surface)
        object.center.y = bottom + object.radii[0]
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
