import CBox2D
import CoreGraphics
import Foundation

private enum WinterMotion {
    static let history: TimeInterval = 0.12
    static let maximumSpeed: CGFloat = 900
    static let outlierSpeedRatio: CGFloat = 3
    static let coherentDirection: CGFloat = 0.95
    static let placementSpeed: CGFloat = 85
    static let gravity: CGFloat = 1200
    /// Фиксированный шаг: на экранах 60 и 120 Гц в кадр помещается целое число шагов.
    static let fixedStep: TimeInterval = 1.0 / 240
    /// После сна или долгой задержки шары не пролетают экран за один кадр.
    static let maximumCatchUp: TimeInterval = 0.25
    /// Спящие шары проверяют снег под собой не чаще этого.
    static let restingCheck: TimeInterval = 0.2
    /// Шар медленнее этого считается спокойным для сборки.
    static let calmSpeed: CGFloat = 3
    /// Шар лежит на шаре, если нормаль касания отклонена от вертикали не больше чем на 20°.
    static let stackNormal: CGFloat = 0.94
    /// Быстрый бросок проверяет столкновения непрерывно и с другими шарами.
    static let bulletSpeed: CGFloat = 600
}

private enum WinterContact: Equatable {
    case ground
    case window(CGWindowID)

    var support: CGWindowID? {
        if case .window(let id) = self { return id }
        return nil
    }
}

/// Тело Box2D одной фигуры.
private final class Figure {
    let key: Int
    var body: b2BodyId
    var parts: [SnowballPart]
    /// Угол тела на прошлом шаге: rotation копится по приращениям, а не по углу в пределах ±π.
    var angle: CGFloat
    /// Последняя опора, о которую фигура ударилась. Повторное касание той же опоры снег не проминает.
    var landing: WinterContact?
    var pushed = false
    var joint: b2JointId?
    var velocityBeforeStep = CGVector.zero
    var fallPeakY: CGFloat?

    init(key: Int, body: b2BodyId, parts: [SnowballPart], angle: CGFloat) {
        self.key = key
        self.body = body
        self.parts = parts
        self.angle = angle
    }
}

/// Тела одной видимой опоры: кромка, снег и твёрдый корпус Dock.
private final class SupportBodies {
    let body: b2BodyId
    let bed: WinterChainProfile
    let snow: WinterChainProfile
    var solid: b2BodyId?
    var solidShape: WindowSurface?
    var range: ClosedRange<CGFloat> = 0...0

    init(body: b2BodyId, bed: WinterChainProfile, snow: WinterChainProfile) {
        self.body = body
        self.bed = bed
        self.snow = snow
    }

    var top: CGFloat { max(bed.top, snow.top) }
    var isRising: Bool { snow.isRising }
}

private final class SweepContext {
    let body: b2BodyId
    let start: b2Vec2
    let translation: b2Vec2
    var fraction: Float = 1
    var normal = b2Vec2(x: 0, y: 0)
    var hit = false

    init(body: b2BodyId, start: b2Vec2, translation: b2Vec2) {
        self.body = body
        self.start = start
        self.translation = translation
    }
}

private func same(_ a: b2BodyId, _ b: b2BodyId) -> Bool {
    a.index1 == b.index1 && a.world0 == b.world0 && a.generation == b.generation
}

private func winterShouldCollide(_ a: b2ShapeId, _ b: b2ShapeId, _ context: UnsafeMutableRawPointer?) -> Bool {
    guard let context else { return true }
    return Unmanaged<WinterScene>.fromOpaque(context).takeUnretainedValue().shouldCollide(a, b)
}

/// Ближайшее препятствие на пути шара в руке. Обратную сторону односторонней цепочки и выход из перекрытия не считаем.
private func winterSweepResult(_ shape: b2ShapeId, _ point: b2Vec2, _ normal: b2Vec2, _ fraction: Float,
                               _ context: UnsafeMutableRawPointer?) -> Float {
    guard let context else { return -1 }
    let sweep = Unmanaged<SweepContext>.fromOpaque(context).takeUnretainedValue()
    if same(b2Shape_GetBody(shape), sweep.body) { return -1 }
    if normal.x * sweep.translation.x + normal.y * sweep.translation.y >= 0 { return -1 }
    if b2Shape_GetType(shape) == b2_chainSegmentShape {
        let segment = b2Shape_GetChainSegment(shape).segment
        let dx = segment.point2.x - segment.point1.x
        let dy = segment.point2.y - segment.point1.y
        if (sweep.start.x - segment.point1.x) * dy - (sweep.start.y - segment.point1.y) * dx < 0 { return -1 }
    }
    if fraction < sweep.fraction {
        sweep.fraction = fraction
        sweep.normal = normal
        sweep.hit = true
    }
    return fraction
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
    /// Весь контур горки Dock за один вызов. nil опрашивает surfaceHeight по точкам.
    var dockProfile: (_ id: CGWindowID) -> WinterSurfaceProfile? = { _ in nil }
    var didLand: (WinterImpact) -> Void = { _ in }
    var didChip: (WinterBallChip) -> Void = { _ in }
    var isMoving: Bool {
        captured != nil || !settledStacks.isEmpty || isSnowRising || figures.indices.contains {
            !objects[$0].parked && b2Body_IsAwake(figures[$0].body)
        }
    }

    private var width: CGFloat
    private var height: CGFloat
    private let physics = SnowballWorld(gravity: WinterMotion.gravity)
    private var figures: [Figure] = []
    private var indexByKey: [Int: Int] = [:]
    private var nextKey = 1
    private var surfaces: [CGWindowID: WindowSurface] = [:]
    private var visibleSupports: Set<CGWindowID> = []
    private var supports: [CGWindowID: SupportBodies] = [:]
    private let groundBody: b2BodyId
    private let groundBed: WinterChainProfile
    private let groundSnow: WinterChainProfile
    private var wallBody: b2BodyId?
    private var groundBuilt = false
    private var settledStacks: [UUID: (ids: [UUID], duration: TimeInterval)] = [:]
    private var dragOffset: CGPoint = .zero
    private var captured: UUID?
    private var dragHistory: [(duration: TimeInterval, velocity: CGVector)] = []
    private var fastDragSample: (duration: TimeInterval, velocity: CGVector)?
    /// Реальное время, ещё не пройденное фиксированными шагами.
    private var pendingTime: TimeInterval = 0
    /// Время с прошлой проверки снега под шарами.
    private var supportClock: TimeInterval = 0

    private static let groundKey = -1
    private static let wallKey = -2
    private static func surfaceKey(_ id: CGWindowID) -> Int { -10 - Int(id) }

    init(width: CGFloat, height: CGFloat) {
        self.width = max(0, width)
        self.height = max(0, height)
        groundBody = physics.makeStaticBody(key: Self.groundKey)
        groundBed = WinterChainProfile(world: physics, body: groundBody, category: SnowballCategory.bed,
                                       mask: SnowballCategory.ball, hysteresis: false)
        groundSnow = WinterChainProfile(world: physics, body: groundBody, category: SnowballCategory.snow,
                                        mask: SnowballCategory.foot, hysteresis: true)
        b2World_SetCustomFilterCallback(physics.world, winterShouldCollide, Unmanaged.passUnretained(self).toOpaque())
        buildWalls()
    }

    deinit {
        b2World_SetCustomFilterCallback(physics.world, nil, nil)
    }

    // MARK: Создание

    @discardableResult
    func create(_ size: WinterBallSize, at point: CGPoint) -> UUID? {
        create(radius: size.radius, at: point)
    }

    @discardableResult
    func create(radius: CGFloat, at point: CGPoint) -> UUID? {
        guard hasCapacity, WinterBallGeometry.isValid(radius),
              point.x.isFinite, point.y.isFinite else { return nil }
        var object = WinterObject(id: UUID(), radii: [radius], center: point, velocity: .zero,
                                  support: nil, parked: false, isDragged: false)
        clamp(&object)
        // У совпадающих центров нет нормали касания: Box2D не развёл бы шары.
        if objects.contains(where: { other in !other.parked && other.ballCircles.contains {
            hypot($0.center.x - object.center.x, $0.center.y - object.center.y) < 0.01 } }) {
            object.center.x += object.center.x + radius < width ? 0.02 : -0.02
        }
        append(object)
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
        // Экран заполнен до верха: шар появляется как раньше, Box2D разведёт его с соседями.
        guard center.y + radius <= height, blockers(at: center).isEmpty else { return create(radius: radius, at: point) }
        return create(radius: radius, at: center)
    }

    /// Отодвигает фигуры вбок от круга, по цепочке. Если цепочка упирается в край экрана, ничего не меняет и возвращает false.
    @discardableResult
    func makeRoom(radius: CGFloat, at center: CGPoint) -> Bool {
        var centers = Dictionary(objects.indices.map { ($0, objects[$0].center) }, uniquingKeysWith: { first, _ in first })
        func circles(_ index: Int) -> [(center: CGPoint, radius: CGFloat)] {
            var object = objects[index]
            object.center = centers[index]!
            return object.ballCircles
        }
        var pushers: [(center: CGPoint, radius: CGFloat, direction: CGFloat?, owner: Int?)] = [(center, radius, nil, nil)]
        var moved: Set<Int> = []
        while let pusher = pushers.popLast() {
            for index in objects.indices where !objects[index].parked && !objects[index].isDragged && index != pusher.owner {
                var shift: CGFloat = 0
                var direction = pusher.direction ?? (centers[index]!.x >= pusher.center.x ? 1 : -1)
                for circle in circles(index) {
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
                if moved.contains(index) && pusher.direction == nil { continue }
                let half = objects[index].frame.width / 2
                let target = centers[index]!.x + shift * direction
                guard target - half >= -0.01, target + half <= width + 0.01, moved.count < Self.maximumObjects * 2 else { return false }
                centers[index]!.x = target
                moved.insert(index)
                for circle in circles(index) { pushers.append((circle.center, circle.radius, direction, index)) }
            }
        }
        for index in moved {
            teleport(index, to: centers[index]!)
            b2Body_SetLinearVelocity(figures[index].body, b2Vec2(x: 0, y: 0))
            if let support = objects[index].support, let surface = surfaces[support],
               objects[index].center.x - objects[index].frame.width / 2 < surface.frame.minX
                || objects[index].center.x + objects[index].frame.width / 2 > surface.frame.maxX {
                // Отодвинутый с края окна шар падает.
                objects[index].support = nil
            }
        }
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

    // MARK: Перетаскивание

    func beginDragging(_ id: UUID, at point: CGPoint) {
        guard captured != id, objects.contains(where: { $0.id == id && !$0.parked }) else { return }
        if let captured { cancelDragging(captured) }
        guard let index = objects.firstIndex(where: { $0.id == id }) else { return }
        captured = id
        dragHistory.removeAll()
        fastDragSample = nil
        dragOffset = CGPoint(x: objects[index].center.x - point.x, y: objects[index].center.y - point.y)
        settledStacks.removeValue(forKey: id)
        objects[index].isDragged = true
        objects[index].support = nil
        objects[index].velocity = .zero
        objects[index].spin = 0
        let figure = figures[index]
        figure.landing = nil
        figure.fallPeakY = nil
        // Шар в руке — тело без гравитации на пружине: расталкивает свободных соседей и упирается в опёртых.
        b2Body_SetGravityScale(figure.body, 0)
        b2Body_SetFixedRotation(figure.body, true)
        b2Body_SetLinearVelocity(figure.body, b2Vec2(x: 0, y: 0))
        b2Body_SetAngularVelocity(figure.body, 0)
        b2Body_SetBullet(figure.body, false)
        setMasks(figure, ball: SnowballCategory.heldMask, foot: 0)
        var def = b2DefaultMouseJointDef()
        def.bodyIdA = physics.anchor
        def.bodyIdB = figure.body
        def.target = SnowballWorld.meters(objects[index].center)
        def.hertz = 20
        def.dampingRatio = 1
        def.maxForce = 50 * b2Body_GetMass(figure.body) * SnowballWorld.meters(WinterMotion.gravity)
        figure.joint = b2CreateMouseJoint(physics.world, &def)
        wakeAround(index)
    }

    func drag(_ id: UUID, to point: CGPoint, dt: TimeInterval) {
        guard captured == id, let index = objects.firstIndex(where: { $0.id == id }) else { return }
        guard point.x.isFinite, point.y.isFinite else { return }
        let previous = objects[index].center
        var target = objects[index]
        target.center = CGPoint(x: point.x + dragOffset.x, y: point.y + dragOffset.y)
        clamp(&target)
        if let joint = figures[index].joint { b2MouseJoint_SetTarget(joint, SnowballWorld.meters(target.center)) }
        // Шар сразу встаёт под курсор, но не внутрь других шаров и твёрдых опор: окно не показывает перекрытий.
        teleport(index, to: slide(index, from: previous, to: target.center))
        b2Body_SetLinearVelocity(figures[index].body, b2Vec2(x: 0, y: 0))
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

    /// Сдвиг со скольжением вдоль препятствий: до трёх касаний за одно движение.
    private func slide(_ index: Int, from start: CGPoint, to target: CGPoint) -> CGPoint {
        var position = start
        var remaining = CGVector(dx: target.x - start.x, dy: target.y - start.y)
        for _ in 0..<3 {
            let length = hypot(remaining.dx, remaining.dy)
            guard length > 0.0001 else { break }
            guard let hit = sweep(index, from: position, by: remaining) else {
                position.x += remaining.dx
                position.y += remaining.dy
                break
            }
            // Отступ больше допуска Box2D: следующий проход начинается без перекрытия.
            let travel = max(0, hit.fraction - 0.3 / length)
            position.x += remaining.dx * travel
            position.y += remaining.dy * travel
            remaining.dx *= 1 - hit.fraction
            remaining.dy *= 1 - hit.fraction
            let into = remaining.dx * hit.normal.dx + remaining.dy * hit.normal.dy
            if into < 0 {
                remaining.dx -= into * hit.normal.dx
                remaining.dy -= into * hit.normal.dy
            }
        }
        return position
    }

    private func sweep(_ index: Int, from position: CGPoint, by translation: CGVector) -> (fraction: CGFloat, normal: CGVector)? {
        let figure = figures[index]
        var best: (fraction: CGFloat, normal: CGVector)?
        let rotation = b2Body_GetRotation(figure.body)
        for part in figure.parts {
            let center = SnowballWorld.meters(CGPoint(x: position.x + part.center.x, y: position.y + part.center.y))
            // Смятый шар проверяется своим многоугольником, иначе вмятина у опоры сразу считалась бы препятствием.
            let points = part.hull.isEmpty ? [center] : part.hull.map { point -> b2Vec2 in
                let local = b2RotateVector(rotation, SnowballWorld.meters(point))
                return b2Vec2(x: center.x + local.x, y: center.y + local.y)
            }
            let radius = part.hull.isEmpty ? part.radius : part.rounding
            var proxy = points.withUnsafeBufferPointer { b2MakeProxy($0.baseAddress, Int32($0.count), SnowballWorld.meters(radius)) }
            let context = SweepContext(body: figure.body, start: center, translation: SnowballWorld.meters(translation))
            let filter = b2QueryFilter(categoryBits: SnowballCategory.ball, maskBits: SnowballCategory.heldMask)
            withExtendedLifetime(context) {
                _ = b2World_CastShape(physics.world, &proxy, context.translation, filter, winterSweepResult,
                                      Unmanaged.passUnretained(context).toOpaque())
            }
            guard context.hit, CGFloat(context.fraction) < best?.fraction ?? 2 else { continue }
            best = (CGFloat(context.fraction), CGVector(dx: CGFloat(context.normal.x), dy: CGFloat(context.normal.y)))
        }
        return best
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
        release(index, velocity: .zero)
    }

    func endDragging(_ id: UUID, idleTime: TimeInterval = 0) {
        guard captured == id, let index = objects.firstIndex(where: { $0.id == id }) else { return }
        let hasPendingMotion = fastDragSample != nil && !(idleTime.isFinite && idleTime >= WinterMotion.history)
        if idleTime.isFinite, idleTime > 0 { appendDragSample(duration: idleTime, velocity: .zero) }
        let velocity = releaseVelocity
        captured = nil
        dragHistory.removeAll()
        fastDragSample = nil
        release(index, velocity: velocity)
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

    /// Возвращает телу гравитацию. Одиночный шар сразу катится без проскальзывания.
    private func release(_ index: Int, velocity: CGVector) {
        let figure = figures[index]
        figure.fallPeakY = objects[index].center.y
        if let joint = figure.joint { b2DestroyJoint(joint) }
        figure.joint = nil
        objects[index].isDragged = false
        objects[index].velocity = velocity
        let single = objects[index].radii.count == 1
        b2Body_SetGravityScale(figure.body, 1)
        b2Body_SetFixedRotation(figure.body, !single)
        setMasks(figure, ball: figure.pushed ? SnowballCategory.pushedMask : SnowballCategory.ballMask, foot: SnowballCategory.snow)
        b2Body_SetLinearVelocity(figure.body, SnowballWorld.meters(velocity))
        let spin = single ? -velocity.dx / objects[index].radii[0] : 0
        objects[index].spin = spin
        b2Body_SetAngularVelocity(figure.body, Float(spin))
        b2Body_SetBullet(figure.body, hypot(velocity.dx, velocity.dy) > WinterMotion.bulletSpeed)
        b2Body_SetAwake(figure.body, true)
    }

    // MARK: Сборка

    private func merge(_ ids: [UUID], onto base: UUID) {
        guard let index = objects.firstIndex(where: { $0.id == base }) else { return }
        var object = objects[index]
        for id in ids {
            guard let held = objects.first(where: { $0.id == id }) else { continue }
            // Порядок повреждений совпадает с порядком шаров, в том числе у целых шаров.
            object.ballDamage = object.assembledDamage
            object.ballDamage.append(contentsOf: held.assembledDamage)
            object.radii.append(contentsOf: held.radii)
        }
        object.rotation = 0
        object.spin = 0
        for id in ids {
            if let other = objects.firstIndex(where: { $0.id == id }) { remove(at: other) }
        }
        guard let index = objects.firstIndex(where: { $0.id == base }) else { return }
        objects[index] = object
        let figure = figures[index]
        figure.parts = object.physicalParts
        figure.angle = 0
        physics.replaceShapes(of: figure.body, with: figure.parts)
        b2Body_SetTransform(figure.body, SnowballWorld.meters(object.center), b2Rot_identity)
        b2Body_SetFixedRotation(figure.body, true)
        b2Body_SetAngularVelocity(figure.body, 0)
        if figure.pushed { setMasks(figure, ball: SnowballCategory.pushedMask, foot: SnowballCategory.snow) }
        wakeAround(index)
    }

    /// Три шара, спокойно стоящие друг на друге, собираются и после завершения падения.
    private func assembleSettledSnowmen(dt: TimeInterval) {
        var next: [UUID: (ids: [UUID], duration: TimeInterval)] = [:]
        var ready: [(base: UUID, ids: [UUID])] = []
        var restsOn: [Int: Int] = [:]
        func calm(_ index: Int) -> Bool {
            let object = objects[index]
            return !object.parked && !object.isDragged && hypot(object.velocity.dx, object.velocity.dy) < WinterMotion.calmSpeed
        }
        for index in objects.indices where calm(index) {
            for contact in contacts(of: figures[index].body) where contact.manifold.pointCount > 0 {
                guard let (other, normal) = otherFigure(index, contact), normal.dy > WinterMotion.stackNormal else { continue }
                restsOn[index] = other
            }
        }
        for base in objects.indices where calm(base) && restsOn[base] == nil && objects[base].radii.count < 3 {
            var chain = [base]
            var count = objects[base].radii.count
            while count < 3, let top = chain.last,
                  let upper = objects.indices.first(where: { calm($0) && restsOn[$0] == top && !chain.contains($0) }) {
                chain.append(upper)
                count += objects[upper].radii.count
            }
            guard count == 3 else { continue }
            let ids = chain.map { objects[$0].id }
            let previous = settledStacks[ids[0]]
            let duration = (previous?.ids == ids ? previous!.duration : 0) + dt
            if duration >= 0.2 {
                ready.append((ids[0], Array(ids.dropFirst())))
            } else {
                next[ids[0]] = (ids, duration)
            }
        }
        settledStacks = next
        for stack in ready { merge(stack.ids, onto: stack.base) }
    }

    /// Соседняя фигура в касании и нормаль, направленная от неё к этой фигуре.
    private func otherFigure(_ index: Int, _ contact: b2ContactData) -> (Int, CGVector)? {
        let bodyA = b2Shape_GetBody(contact.shapeIdA)
        let bodyB = b2Shape_GetBody(contact.shapeIdB)
        let mine = same(bodyA, figures[index].body)
        let key = SnowballWorld.key(b2Body_GetUserData(mine ? bodyB : bodyA))
        guard key > 0, let other = indexByKey[key] else { return nil }
        let normal = contact.manifold.normal
        let sign: CGFloat = mine ? -1 : 1
        return (other, CGVector(dx: CGFloat(normal.x) * sign, dy: CGFloat(normal.y) * sign))
    }

    // MARK: Окна

    func updateWindows(_ update: WindowUpdate) {
        visibleSupports = Set(update.surfaces.map(\.id))
        let visible = Dictionary(update.surfaces.map { ($0.id, $0) }, uniquingKeysWith: { _, next in next })
        var moved: Set<Int> = []
        for index in objects.indices {
            guard let support = objects[index].support, !objects[index].isDragged else { continue }
            guard let next = visible[support] else {
                let parked = update.elsewhere.contains(support) || update.parked.contains(support)
                if parked && !objects[index].parked {
                    objects[index].parked = true
                    wakeAround(index)
                    b2Body_Disable(figures[index].body)
                } else if !parked {
                    objects[index].support = nil
                    wakeAround(index)
                }
                continue
            }
            let resized = surfaces[support].map { $0.frame.size != next.frame.size } ?? false
            if let previous = surfaces[support], !moved.contains(index) {
                let dx = next.frame.minX - previous.frame.minX
                let dy = next.frame.maxY - previous.frame.maxY
                if dx != 0 || dy != 0 {
                    // Окно уносит лежащие на нём фигуры и стопки над ними.
                    for carried in stack(on: index) where !moved.contains(carried) {
                        moved.insert(carried)
                        teleport(carried, to: CGPoint(x: objects[carried].center.x + dx, y: objects[carried].center.y + dy), wake: false)
                    }
                }
            }
            if objects[index].parked {
                objects[index].parked = false
                b2Body_SetTransform(figures[index].body, SnowballWorld.meters(objects[index].center), b2Body_GetRotation(figures[index].body))
                b2Body_Enable(figures[index].body)
                // Выключенное тело теряет скорость: припаркованный шар продолжает прежнее движение.
                b2Body_SetLinearVelocity(figures[index].body, SnowballWorld.meters(objects[index].velocity))
                b2Body_SetAngularVelocity(figures[index].body, Float(objects[index].spin))
                b2Body_SetAwake(figures[index].body, true)
            }
            // Сузившееся окно удерживает лежащий шар над собой. Неизменная опора шар не трогает.
            fit(index, on: next, clampToSupport: resized && abs(objects[index].velocity.dx) < 1)
        }
        let previous = surfaces
        surfaces = visible.merging(surfaces.filter { update.elsewhere.contains($0.key) || update.parked.contains($0.key) }) { current, _ in current }
        for (id, bodies) in supports where visible[id] == nil {
            destroy(bodies)
            supports.removeValue(forKey: id)
        }
        for surface in update.surfaces {
            if let bodies = supports[surface.id], let old = previous[surface.id], old.frame.size == surface.frame.size {
                bodies.snow.shift(dx: surface.frame.minX - old.frame.minX, dy: surface.frame.maxY - old.frame.maxY)
                bodies.bed.shift(dx: surface.frame.minX - old.frame.minX, dy: surface.frame.maxY - old.frame.maxY)
            }
            refreshSupport(surface, dt: 0)
        }
        // Появившийся или расширившийся Dock будит шары, которые оказались в его теле.
        for index in objects.indices where !objects[index].parked && !objects[index].isDragged {
            if physicalDocks.contains(where: { isInside(index, $0) }) { wakeAround(index) }
        }
    }

    /// Фигура и всё, что лежит на ней, по касаниям шар–шар.
    private func stack(on index: Int) -> [Int] {
        var result = [index]
        var cursor = 0
        while cursor < result.count {
            let lower = result[cursor]
            cursor += 1
            for contact in contacts(of: figures[lower].body) where contact.manifold.pointCount > 0 {
                guard let (other, normal) = otherFigure(lower, contact), normal.dy < -0.5,
                      !result.contains(other), !objects[other].isDragged, !objects[other].parked else { continue }
                result.append(other)
            }
        }
        return result
    }

    private func fit(_ index: Int, on surface: WindowSurface, clampToSupport: Bool) {
        let radius = objects[index].frame.width / 2
        let low = max(radius, surface.frame.minX + radius)
        let high = min(width - radius, surface.frame.maxX - radius)
        let top = surfaceHeight(surface.id, objects[index].center.x) ?? surface.frame.maxY
        guard low <= high, top + objects[index].frame.height <= height else {
            objects[index].support = nil
            wakeAround(index)
            return
        }
        guard clampToSupport else { return }
        let x = min(max(objects[index].center.x, low), high)
        if x != objects[index].center.x { teleport(index, to: CGPoint(x: x, y: objects[index].center.y)) }
    }

    // MARK: Шаг

    /// Продвигает физику на реальное время кадра фиксированными шагами. Задержка догоняется, а не замедляет движение.
    func step(dt: TimeInterval) {
        guard dt.isFinite, dt > 0 else { return }
        pendingTime = min(pendingTime + dt, WinterMotion.maximumCatchUp)
        supportClock += dt
        guard isMoving || !groundBuilt else {
            // Спящим шарам достаточно редкой проверки снега под ними.
            pendingTime = 0
            // Подъём над снегом только отмечается: шаги начнутся со следующего кадра вместе с физикой.
            if supportClock >= WinterMotion.restingCheck { refreshSupports(dt: 0) }
            return
        }
        refreshSupports(dt: supportClock)
        escapeDocks()
        var elapsed: TimeInterval = 0
        while pendingTime >= WinterMotion.fixedStep - 1e-9 {
            substep()
            pendingTime -= WinterMotion.fixedStep
            elapsed += WinterMotion.fixedStep
        }
        pendingTime = max(0, pendingTime)
        synchronizeObjects()
        if let captured, let index = objects.firstIndex(where: { $0.id == captured }) { separateHeld(index) }
        removeLostObjects()
        if elapsed > 0 { assembleSettledSnowmen(dt: elapsed) }
    }

    private func substep() {
        for index in figures.indices where objects[index].isSnowman {
            let figure = figures[index]
            if objects[index].isDragged || objects[index].parked {
                figure.fallPeakY = nil
            } else {
                let y = SnowballWorld.points(b2Body_GetPosition(figure.body)).y
                figure.fallPeakY = max(figure.fallPeakY ?? y, y)
            }
        }
        for index in figures.indices where !objects[index].parked && b2Body_IsAwake(figures[index].body) {
            figures[index].velocityBeforeStep = SnowballWorld.velocity(b2Body_GetLinearVelocity(figures[index].body))
        }
        physics.step(WinterMotion.fixedStep)
        for index in figures.indices where objects[index].radii.count == 1 && !objects[index].parked {
            let figure = figures[index]
            guard b2Body_IsAwake(figure.body) else { continue }
            let angle = CGFloat(b2Rot_GetAngle(b2Body_GetRotation(figure.body)))
            objects[index].rotation += remainder(angle - figure.angle, 2 * .pi)
            figure.angle = angle
        }
        handleContactEvents()
        handleSnowmanFalls()
    }

    private func handleContactEvents() {
        let events = b2World_GetContactEvents(physics.world)
        var landings: [(Int, WinterContact)] = []
        for i in 0..<Int(events.beginCount) {
            let event = events.beginEvents[i]
            for (ball, other) in [(event.shapeIdA, event.shapeIdB), (event.shapeIdB, event.shapeIdA)] {
                guard let index = figureIndex(ball), let contact = surfaceContact(other) else { continue }
                landings.append((index, contact))
            }
        }
        var chips: [(index: Int, component: Int, speed: CGFloat, point: CGPoint)] = []
        for i in 0..<Int(events.hitCount) {
            let event = events.hitEvents[i]
            let speed = SnowballWorld.points(event.approachSpeed)
            let point = SnowballWorld.points(event.point)
            let a = figureIndex(event.shapeIdA)
            let b = figureIndex(event.shapeIdB)
            if let a, b == nil, surfaceContact(event.shapeIdB) != nil {
                chips.append((a, component(event.shapeIdA), speed, point))
            } else if let b, a == nil, surfaceContact(event.shapeIdA) != nil {
                chips.append((b, component(event.shapeIdB), speed, point))
            } else if let a, let b {
                // Мнётся верхний шар: он падает на нижний.
                if event.normal.y > 0.65 {
                    chips.append((b, component(event.shapeIdB), speed, point))
                } else if event.normal.y < -0.65 {
                    chips.append((a, component(event.shapeIdA), speed, point))
                }
            }
        }
        for (index, contact) in landings {
            let figure = figures[index]
            guard !objects[index].isDragged, !objects[index].parked, figure.landing != contact else { continue }
            figure.landing = contact
            objects[index].support = contact.support
            let velocity = CGVector(dx: figure.velocityBeforeStep.dx,
                                    dy: figure.velocityBeforeStep.dy - WinterMotion.gravity * CGFloat(WinterMotion.fixedStep))
            didLand(WinterImpact(support: contact.support, x: objects[index].center.x, radius: objects[index].radii[0],
                                 mass: objects[index].radii.reduce(0) { $0 + pow($1 / WinterBallSize.small.radius, 3) },
                                 velocity: velocity))
        }
        var reshaped: Set<Int> = []
        for chip in chips where !objects[chip.index].isDragged && !objects[chip.index].isSnowman && objects[chip.index].radii.indices.contains(chip.component) {
            if self.chip(chip.index, component: chip.component, speed: chip.speed, at: chip.point) { reshaped.insert(chip.index) }
        }
        for index in reshaped {
            let figure = figures[index]
            figure.parts = objects[index].physicalParts
            physics.replaceShapes(of: figure.body, with: figure.parts)
            if figure.pushed { setMasks(figure, ball: SnowballCategory.pushedMask, foot: SnowballCategory.snow) }
        }
    }

    /// Высота считается от вершины свободного полёта. Опора снизу завершает падение один раз.
    private func handleSnowmanFalls() {
        var broken: [Int] = []
        for index in objects.indices where objects[index].isSnowman && !objects[index].isDragged && !objects[index].parked {
            let figure = figures[index]
            let position = SnowballWorld.points(b2Body_GetPosition(figure.body))
            figure.fallPeakY = max(figure.fallPeakY ?? position.y, position.y)
            let supported = contacts(of: figure.body).contains { contact in
                guard contact.manifold.pointCount > 0 else { return false }
                let mine = same(b2Shape_GetBody(contact.shapeIdA), figure.body)
                return (mine ? -contact.manifold.normal.y : contact.manifold.normal.y) > 0.5
            }
            guard supported else { continue }
            let distance = max(0, (figure.fallPeakY ?? position.y) - position.y)
            figure.fallPeakY = nil
            let speed = sqrt(2 * WinterMotion.gravity * distance)
            guard speed > 180 else { continue }
            // Координаты Box2D хранятся во Float: не разрушаем фигуру из-за шума меньше 0,001 pt.
            if distance - height / 3 > 0.001 { broken.append(index) }
            var reshaped = false
            for component in objects[index].radii.indices {
                let center = SnowballWorld.points(b2Body_GetWorldPoint(figure.body, SnowballWorld.meters(figure.parts[component].center)))
                let point = CGPoint(x: center.x, y: center.y - objects[index].radii[component])
                reshaped = chip(index, component: component, speed: speed, at: point) || reshaped
            }
            if reshaped {
                figure.parts = objects[index].physicalParts
                physics.replaceShapes(of: figure.body, with: figure.parts)
                if figure.pushed { setMasks(figure, ball: SnowballCategory.pushedMask, foot: SnowballCategory.snow) }
            }
        }
        // Сначала дочитываем контакты всех фигур, затем меняем массивы и тела Box2D.
        for index in broken.reversed() { breakSnowman(at: index) }
    }

    private func breakSnowman(at index: Int) {
        var object = objects[index]
        object.center = SnowballWorld.points(b2Body_GetPosition(figures[index].body))
        let velocity = SnowballWorld.velocity(b2Body_GetLinearVelocity(figures[index].body))
        let circles = object.ballCircles
        let available = Self.maximumObjects - objects.count + 1
        remove(at: index)
        for (component, circle) in circles.enumerated() {
            didChip(WinterBallChip(center: circle.center, radius: circle.radius, strength: 0.7))
            // При полном лимите лишние части рассыпаются в крошку вместо создания новых тел.
            guard component < available else { continue }
            let piece = WinterObject(id: UUID(), radii: [circle.radius], center: circle.center,
                velocity: .zero, support: nil, parked: false, isDragged: false,
                ballDamage: [object.damage(for: component)])
            append(piece)
            release(objects.count - 1, velocity: CGVector(
                dx: velocity.dx * 0.3 + CGFloat(component - 1) * 110,
                dy: 55 + CGFloat(component) * 35))
        }
    }

    private func chip(_ index: Int, component: Int, speed: CGFloat, at point: CGPoint) -> Bool {
        let figure = figures[index]
        let part = figure.parts[component]
        let center = SnowballWorld.points(b2Body_GetWorldPoint(figure.body, SnowballWorld.meters(part.center)))
        let angle = atan2(point.y - center.y, point.x - center.x)
        var damage = objects[index].damage(for: component)
        let single = objects[index].radii.count == 1
        let amount = damage.hit(speed: speed, angle: angle - (single ? objects[index].rotation : 0))
        guard amount > 0 else { return false }
        while objects[index].ballDamage.count < objects[index].radii.count { objects[index].ballDamage.append(WinterBallDamage()) }
        objects[index].ballDamage[component] = damage
        didChip(WinterBallChip(center: point, radius: objects[index].radii[component], strength: amount))
        return true
    }

    private func figureIndex(_ shape: b2ShapeId) -> Int? {
        let key = SnowballWorld.key(b2Body_GetUserData(b2Shape_GetBody(shape)))
        return key > 0 ? indexByKey[key] : nil
    }

    private func component(_ shape: b2ShapeId) -> Int {
        SnowballWorld.key(b2Shape_GetUserData(shape)) % SnowballWorld.footTag
    }

    private func surfaceContact(_ shape: b2ShapeId) -> WinterContact? {
        let key = SnowballWorld.key(b2Body_GetUserData(b2Shape_GetBody(shape)))
        if key == Self.groundKey { return .ground }
        guard key <= -10 else { return nil }
        return .window(CGWindowID(-10 - key))
    }

    /// Копирует состояние тел в модель. Сдвиг меньше тысячной пункта — шум float, координата остаётся точной.
    private func synchronizeObjects() {
        for index in objects.indices where !objects[index].parked {
            let body = figures[index].body
            let position = SnowballWorld.points(b2Body_GetPosition(body))
            if hypot(position.x - objects[index].center.x, position.y - objects[index].center.y) > 0.001 {
                objects[index].center = position
            }
            guard !objects[index].isDragged else { continue }
            let awake = b2Body_IsAwake(body)
            objects[index].velocity = awake ? SnowballWorld.velocity(b2Body_GetLinearVelocity(body)) : .zero
            objects[index].spin = awake && objects[index].radii.count == 1 ? CGFloat(b2Body_GetAngularVelocity(body)) : 0
            guard awake else { continue }
            var support: CGWindowID?
            for contact in contacts(of: body) where contact.manifold.pointCount > 0 {
                let mine = same(b2Shape_GetBody(contact.shapeIdA), body)
                guard let surface = surfaceContact(mine ? contact.shapeIdB : contact.shapeIdA),
                      (mine ? -contact.manifold.normal.y : contact.manifold.normal.y) > 0.5 else { continue }
                if let id = surface.support { support = id }
            }
            objects[index].support = support
        }
    }

    /// Пружина вдавливает шар в руке в соседа на доли пункта. Окно показывает его уже снаружи.
    private func separateHeld(_ index: Int) {
        var center = objects[index].center
        for _ in 0..<4 {
            var moved = false
            var held = objects[index]
            held.center = center
            for other in objects.indices where other != index && !objects[other].parked {
                for (a, circle) in held.ballCircles.enumerated() {
                    for (b, neighbor) in objects[other].ballCircles.enumerated() {
                        let dx = circle.center.x - neighbor.center.x
                        let dy = circle.center.y - neighbor.center.y
                        let distance = hypot(dx, dy)
                        let reach = circle.radius * (1 - held.damage(for: a).depth * 1.25)
                            + neighbor.radius * (1 - objects[other].damage(for: b).depth * 1.25)
                        guard distance > 0.0001, reach - distance > 0.05 else { continue }
                        center.x += dx / distance * (reach - distance)
                        center.y += dy / distance * (reach - distance)
                        held.center = center
                        moved = true
                    }
                }
            }
            if !moved { break }
        }
        if center != objects[index].center { teleport(index, to: center) }
    }

    private func removeLostObjects() {
        let lost = objects.indices.filter { index in
            let frame = objects[index].frame
            return (figures[index].pushed && (frame.maxX < 0 || frame.minX > width)) || objects[index].center.y < -1000
        }
        for index in lost.reversed() { remove(at: index) }
    }

    // MARK: Опоры

    private var isSnowRising: Bool { groundSnow.isRising || supports.values.contains { $0.isRising } }

    /// Снег под шарами: пересобираются только изменившиеся куски, рост с мёртвой зоной.
    private func refreshSupports(dt elapsed: TimeInterval) {
        let dt = CGFloat(min(elapsed, WinterMotion.maximumCatchUp))
        supportClock = 0
        refreshGround(dt: dt)
        for id in visibleSupports {
            if let surface = surfaces[id] { refreshSupport(surface, dt: dt) }
        }
    }

    private func grid(_ low: CGFloat, _ high: CGFloat) -> [CGFloat] {
        guard low.isFinite, high.isFinite, high > low else { return [] }
        // Сетка от левого края: окно сдвигается вместе со своей сеткой и сохраняет мёртвую зону снега.
        let count = max(1, Int(((high - low) / 2).rounded(.up)))
        return (0...count).map { low + (high - low) * CGFloat($0) / CGFloat(count) }
    }

    private func refreshGround(dt: CGFloat) {
        let xs = grid(0, width)
        guard xs.count >= 2 else { return }
        func snow(_ x: CGFloat) -> CGFloat { surfaceHeight(nil, min(max(x, 0), width)) ?? 0 }
        groundSnow.update(xs: xs, live: xs.map { max(snow($0 - 1), snow($0 + 1)) }, dt: groundBuilt ? dt : 0)
        groundBed.update(xs: xs, live: xs.map { _ in 0 }, dt: 0)
        groundBuilt = true
    }

    private func refreshSupport(_ surface: WindowSurface, dt: CGFloat) {
        let bodies: SupportBodies
        if let existing = supports[surface.id] {
            bodies = existing
        } else {
            let body = physics.makeStaticBody(key: Self.surfaceKey(surface.id))
            bodies = SupportBodies(
                body: body,
                bed: WinterChainProfile(world: physics, body: body, category: SnowballCategory.ledge,
                                        mask: SnowballCategory.ball, hysteresis: false),
                snow: WinterChainProfile(world: physics, body: body, category: SnowballCategory.snow,
                                         mask: SnowballCategory.foot, hysteresis: true))
            supports[surface.id] = bodies
        }
        func blocked(_ x: CGFloat, _ y: CGFloat) -> Bool { surface.blockers.contains { $0.contains(CGPoint(x: x, y: y + 1)) } }
        var xs: [CGFloat]
        var snow: [CGFloat?]
        var lifted: [Bool]
        if surface.isDock {
            let body = physicalDock(surface)
            rebuildSolid(bodies, for: body)
            bodies.range = body.frame.minX...body.frame.maxX
            if let profile = dockProfile(surface.id) {
                (xs, snow, lifted) = profile.vertices
            } else {
                xs = grid(body.frame.minX, body.frame.maxX)
                snow = xs.map { x in
                    let left = surfaceHeight(surface.id, max(body.frame.minX, x - 1)) ?? body.winterRoof(at: x)
                    let right = surfaceHeight(surface.id, min(body.frame.maxX, x + 1)) ?? body.winterRoof(at: x)
                    return max(left, right)
                }
                lifted = xs.map { dockContact(surface.id, $0, 0)?.floor.isFinite ?? false }
            }
        } else {
            bodies.range = surface.frame.minX...surface.frame.maxX
            xs = grid(surface.frame.minX, surface.frame.maxX)
            snow = xs.map { x in
                max(surfaceHeight(surface.id, max(surface.frame.minX, x - 1)) ?? surface.frame.maxY,
                    surfaceHeight(surface.id, min(surface.frame.maxX, x + 1)) ?? surface.frame.maxY)
            }
            lifted = []
            bodies.bed.update(xs: xs, live: xs.map { blocked($0, surface.frame.maxY) ? nil : surface.frame.maxY }, dt: 0)
        }
        for i in xs.indices { if let y = snow[i], blocked(xs[i], y) { snow[i] = nil } }
        bodies.snow.update(xs: xs, live: snow, immediate: lifted, dt: dt)
    }

    /// Dock с текущей шириной: увеличенные иконки раздвигают корпус в стороны.
    private func physicalDock(_ dock: WindowSurface) -> WindowSurface {
        guard let body = dockBody(dock.id), body.width > 0, body.minX.isFinite, body.width.isFinite else { return dock }
        return WindowSurface(id: dock.id, frame: CGRect(x: body.minX, y: dock.frame.minY, width: body.width, height: dock.frame.height),
                             blockers: dock.blockers, cover: dock.cover, cornerRadius: dock.cornerRadius,
                             cornerExponent: dock.cornerExponent, isDock: true)
    }

    private var physicalDocks: [WindowSurface] {
        surfaces.values.filter { $0.isDock && visibleSupports.contains($0.id) }.map(physicalDock)
    }

    /// Корпус Dock — петля по контуру и прямоугольник внутри. Возвращает true, если корпус изменился.
    @discardableResult
    private func rebuildSolid(_ bodies: SupportBodies, for dock: WindowSurface) -> Bool {
        guard bodies.solidShape != dock else { return false }
        if let solid = bodies.solid { b2DestroyBody(solid) }
        bodies.solidShape = dock
        let solid = physics.makeStaticBody(key: Self.surfaceKey(dock.id))
        bodies.solid = solid
        let outline = dock.winterOutline
        if outline.count >= 4 {
            physics.makeChain(on: solid, points: outline, loop: true, category: SnowballCategory.bed, mask: SnowballCategory.ball)
        }
        let corner = max(0, min(dock.cornerRadius, dock.frame.width / 2, dock.frame.height / 2))
        physics.makeBox(on: solid, rect: CGRect(x: dock.frame.minX + 2, y: dock.frame.minY + 2,
                                                width: dock.frame.width - 4, height: dock.frame.height - corner - 4),
                        category: SnowballCategory.bed, mask: SnowballCategory.ball)
        return true
    }

    private func destroy(_ bodies: SupportBodies) {
        bodies.bed.destroy()
        bodies.snow.destroy()
        if let solid = bodies.solid { b2DestroyBody(solid) }
        b2DestroyBody(bodies.body)
    }

    private func buildWalls() {
        if let wallBody { b2DestroyBody(wallBody) }
        let body = physics.makeStaticBody(key: Self.wallKey)
        for x in [0, width] {
            physics.makeSegment(on: body, from: CGPoint(x: x, y: -1000), to: CGPoint(x: x, y: height + 1000),
                                category: SnowballCategory.wall, mask: SnowballCategory.ball)
        }
        wallBody = body
    }

    /// Опора, на которой фигура не помещается по высоте экрана или ширине, её не ловит.
    fileprivate func shouldCollide(_ a: b2ShapeId, _ b: b2ShapeId) -> Bool {
        let keyA = SnowballWorld.key(b2Body_GetUserData(b2Shape_GetBody(a)))
        let keyB = SnowballWorld.key(b2Body_GetUserData(b2Shape_GetBody(b)))
        let (ball, surface, surfaceShape) = keyA > 0 ? (keyA, keyB, b) : (keyB, keyA, a)
        guard ball > 0, surface <= -10,
              b2Shape_GetFilter(surfaceShape).categoryBits & (SnowballCategory.ledge | SnowballCategory.snow) != 0,
              let index = indexByKey[ball], let bodies = supports[CGWindowID(-10 - surface)] else { return true }
        let frame = objects[index].frame
        let half = frame.width / 2
        return bodies.top + frame.height <= height + 0.01
            && max(half, bodies.range.lowerBound + half) <= min(width - half, bodies.range.upperBound - half)
    }

    /// Обновляет контакт в кадре Dock, не продвигая время физики повторно.
    @discardableResult
    func synchronizeDockSupports() -> Bool {
        let before = objects.map(\.center)
        var widened = false
        for surface in surfaces.values where surface.isDock && visibleSupports.contains(surface.id) {
            if let bodies = supports[surface.id] { widened = rebuildSolid(bodies, for: physicalDock(surface)) || widened }
            refreshSupport(surface, dt: 0)
        }
        let docks = physicalDocks
        for index in objects.indices where !objects[index].parked && !objects[index].isDragged {
            // Увеличенная иконка поднимает лежащий шар вместе со снегом, в том числе шар рядом с прежним краем.
            for dock in docks {
                let x = objects[index].center.x
                let radius = objects[index].radii[0]
                let sink = radius * SnowballWorld.footSink
                guard x >= dock.frame.minX, x <= dock.frame.maxX,
                      let contact = dockContact(dock.id, x, radius), contact.floor.isFinite,
                      objects[index].frame.minY < contact.floor - sink - 0.01,
                      contact.top + objects[index].frame.height <= height else { continue }
                let bottom = max(contact.top - sink, dock.winterRestHeight(at: x, radius: radius))
                let dy = bottom - objects[index].frame.minY
                for carried in stack(on: index) {
                    teleport(carried, to: CGPoint(x: objects[carried].center.x, y: objects[carried].center.y + dy))
                }
                objects[index].support = dock.id
                figures[index].landing = .window(dock.id)
            }
        }
        if widened { escapeDocks() }
        return before != objects.map(\.center)
    }

    /// Шар глубоко в теле Dock выходит к ближайшей допустимой грани: Box2D выталкивал бы его медленно и, может быть, под панель.
    private func escapeDocks() {
        let docks = physicalDocks
        guard !docks.isEmpty else { return }
        for index in objects.indices where !objects[index].parked && !objects[index].isDragged {
            for dock in docks where objects[index].frame.intersects(dock.frame.insetBy(dx: -0.001, dy: -0.001)) {
                for _ in 0..<4 where escape(index, from: dock) {}
            }
        }
    }

    /// Шар глубоко в корпусе Dock, а не просто касается его.
    private func isInside(_ index: Int, _ dock: WindowSurface) -> Bool {
        let object = objects[index]
        return object.ballFrames.enumerated().contains { component, frame in
            let center = CGPoint(x: object.center.x, y: object.frame.minY + frame.midY)
            let closest = dock.winterClosestPoint(to: center)
            let allowance = 0.5 + frame.width / 2 * object.damage(for: component).depth * 1.25
            return closest == center || hypot(center.x - closest.x, center.y - closest.y) < frame.width / 2 - allowance
        }
    }

    private func escape(_ index: Int, from dock: WindowSurface) -> Bool {
        let body = dock.frame
        for (component, frame) in objects[index].ballFrames.enumerated() {
            let object = objects[index]
            let radius = frame.width / 2
            let center = CGPoint(x: object.center.x, y: object.frame.minY + frame.midY)
            let closest = dock.winterClosestPoint(to: center)
            let dx = center.x - closest.x
            let dy = center.y - closest.y
            let distance = hypot(dx, dy)
            let inside = closest == center
            // Смятый шар законно опускается на глубину вмятины.
            let allowance = 0.5 + radius * object.damage(for: component).depth * 1.25
            guard inside || distance < radius - allowance else { continue }
            func legal(_ move: CGVector) -> Bool {
                let shifted = object.frame.offsetBy(dx: move.dx, dy: move.dy)
                let floor = max(0, (surfaceHeight(nil, object.center.x + move.dx) ?? 0) - object.radii[0] * SnowballWorld.footSink)
                return shifted.minY >= floor - 0.001 && shifted.minX >= -0.001 && shifted.maxX <= width + 0.001
                    && shifted.maxY <= height + 0.001
            }
            var correction = inside ? CGVector.zero : CGVector(dx: dx / distance * (radius - distance), dy: dy / distance * (radius - distance))
            if inside || !legal(correction) {
                let faces = [CGVector(dx: body.minX - radius - center.x, dy: 0),
                             CGVector(dx: body.maxX + radius - center.x, dy: 0),
                             CGVector(dx: 0, dy: body.minY - radius - center.y),
                             CGVector(dx: 0, dy: dock.winterRestHeight(at: center.x, radius: radius) + radius - center.y)]
                guard let nearest = faces.filter({ legal($0) }).min(by: { hypot($0.dx, $0.dy) < hypot($1.dx, $1.dy) }) else { continue }
                correction = nearest
            }
            let length = hypot(correction.dx, correction.dy)
            guard length > 0 else { continue }
            let normal = CGVector(dx: correction.dx / length, dy: correction.dy / length)
            var target = CGPoint(x: object.center.x + correction.dx, y: object.center.y + correction.dy)
            if normal.dy > 0.999 && component == 0 {
                // Шар встаёт на крышу или на снег на ней.
                let r0 = object.radii[0]
                let snow = dockContact(dock.id, target.x, r0)?.top ?? surfaceHeight(dock.id, target.x)
                let bottom = max(snow.map { $0 - r0 * SnowballWorld.footSink } ?? -.infinity,
                                 dock.winterRestHeight(at: target.x, radius: r0))
                target.y = bottom + r0
                objects[index].support = dock.id
                figures[index].landing = .window(dock.id)
            } else {
                objects[index].support = nil
            }
            teleport(index, to: target)
            let velocity = b2Body_GetLinearVelocity(figures[index].body)
            let incoming = CGFloat(velocity.x) * normal.dx + CGFloat(velocity.y) * normal.dy
            if incoming < 0 {
                b2Body_SetLinearVelocity(figures[index].body, b2Vec2(x: velocity.x - Float(incoming * normal.dx),
                                                                     y: velocity.y - Float(incoming * normal.dy)))
            }
            return true
        }
        return false
    }

    // MARK: Прочее

    func resize(width: CGFloat, height: CGFloat) {
        self.width = max(0, width)
        self.height = max(0, height)
        buildWalls()
        groundBuilt = false
        refreshGround(dt: 0)
        for (id, bodies) in supports {
            destroy(bodies)
            supports.removeValue(forKey: id)
        }
        for index in objects.indices where !objects[index].parked {
            var object = objects[index]
            clamp(&object)
            if object.center != objects[index].center { teleport(index, to: object.center) }
            if let support = objects[index].support, let surface = surfaces[support] {
                fit(index, on: surface, clampToSupport: true)
            }
            wakeAround(index)
        }
        for id in visibleSupports { if let surface = surfaces[id] { refreshSupport(surface, dt: 0) } }
    }

    func removeAll() {
        while !objects.isEmpty { remove(at: objects.count - 1) }
        pendingTime = 0
        settledStacks.removeAll()
        captured = nil
        dragOffset = .zero
        dragHistory.removeAll()
        fastDragSample = nil
    }

    func shoveObjects(in rect: CGRect, by dx: CGFloat) {
        guard dx.isFinite else { return }
        for index in objects.indices where !objects[index].parked && !objects[index].isDragged && objects[index].frame.intersects(rect) {
            let figure = figures[index]
            if !figure.pushed {
                // Отвал выталкивает фигуру за край экрана: стены её не держат.
                figure.pushed = true
                setMasks(figure, ball: SnowballCategory.pushedMask, foot: SnowballCategory.snow)
            }
            objects[index].support = nil
            teleport(index, to: CGPoint(x: objects[index].center.x + dx, y: objects[index].center.y))
        }
        let removed = objects.indices.filter {
            figures[$0].pushed && (objects[$0].frame.maxX < 0 || objects[$0].frame.minX > width)
        }
        for index in removed.reversed() { remove(at: index) }
    }

    // MARK: Тела

    private func append(_ object: WinterObject) {
        let key = nextKey
        nextKey += 1
        let parts = object.physicalParts
        let body = physics.makeFigure(parts: parts, at: object.center, rotation: object.rotation, key: key,
                                      fixedRotation: object.radii.count > 1)
        objects.append(object)
        figures.append(Figure(key: key, body: body, parts: parts, angle: object.rotation))
        indexByKey[key] = objects.count - 1
    }

    private func remove(at index: Int) {
        let figure = figures[index]
        if captured == objects[index].id { captured = nil }
        settledStacks.removeValue(forKey: objects[index].id)
        if let joint = figure.joint { b2DestroyJoint(joint) }
        if !objects[index].parked { wakeAround(index) }
        b2DestroyBody(figure.body)
        objects.remove(at: index)
        figures.remove(at: index)
        indexByKey = Dictionary(uniqueKeysWithValues: figures.enumerated().map { ($1.key, $0) })
    }

    private func teleport(_ index: Int, to center: CGPoint, wake: Bool = true) {
        // Перенос опорой, растущим снегом и рукой не относится к свободному падению.
        if let peak = figures[index].fallPeakY { figures[index].fallPeakY = peak + center.y - objects[index].center.y }
        objects[index].center = center
        let body = figures[index].body
        b2Body_SetTransform(body, SnowballWorld.meters(center), b2Body_GetRotation(body))
        if wake && !objects[index].parked { wakeAround(index) }
    }

    /// Будит фигуру и всех, кто её касается: сосед мог потерять опору.
    private func wakeAround(_ index: Int) {
        let body = figures[index].body
        guard b2Body_IsEnabled(body) else { return }
        b2Body_SetAwake(body, true)
        for contact in contacts(of: body) {
            for shape in [contact.shapeIdA, contact.shapeIdB] {
                let other = b2Shape_GetBody(shape)
                if !same(other, body), b2Body_GetType(other) == b2_dynamicBody { b2Body_SetAwake(other, true) }
            }
        }
    }

    private func contacts(of body: b2BodyId) -> [b2ContactData] {
        let capacity = Int(b2Body_GetContactCapacity(body))
        guard capacity > 0 else { return [] }
        var data = [b2ContactData](repeating: b2ContactData(), count: capacity)
        let count = data.withUnsafeMutableBufferPointer { Int(b2Body_GetContactData(body, $0.baseAddress, Int32(capacity))) }
        return Array(data.prefix(count))
    }

    private func setMasks(_ figure: Figure, ball: UInt64, foot: UInt64) {
        let count = Int(b2Body_GetShapeCount(figure.body))
        var shapes = [b2ShapeId](repeating: b2ShapeId(), count: count)
        _ = shapes.withUnsafeMutableBufferPointer { b2Body_GetShapes(figure.body, $0.baseAddress, Int32(count)) }
        for shape in shapes {
            var filter = b2Shape_GetFilter(shape)
            let mask = filter.categoryBits == SnowballCategory.foot ? foot : ball
            guard filter.maskBits != mask else { continue }
            filter.maskBits = mask
            b2Shape_SetFilter(shape, filter)
        }
    }

    private func clamp(_ object: inout WinterObject) {
        let half = object.frame.width / 2
        object.center.x = min(max(object.center.x, half), max(half, width - half))
        let radius = object.radii[0]
        object.center.y = min(max(object.center.y, radius), max(radius, height - object.frame.height + radius))
    }
}
