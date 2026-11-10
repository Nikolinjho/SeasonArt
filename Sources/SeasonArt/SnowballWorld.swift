import CBox2D
import CoreGraphics
import Foundation

/// Слои столкновений. Полный круг шара касается ложа и других шаров, стопа нижнего шара — только снега.
enum SnowballCategory {
    static let ball: UInt64 = 1 << 0
    /// Дно экрана и тело Dock: их не проходит даже шар в руке.
    static let bed: UInt64 = 1 << 1
    /// Кромка окна под снегом.
    static let ledge: UInt64 = 1 << 2
    static let snow: UInt64 = 1 << 3
    static let wall: UInt64 = 1 << 4
    static let foot: UInt64 = 1 << 5

    static let ballMask = ball | bed | ledge | wall
    static let heldMask = ball | bed | wall
    static let pushedMask = ball | bed | ledge
}

/// Шар фигуры в координатах тела. Смятый шар — скруглённый многоугольник.
struct SnowballPart: Equatable {
    var center: CGPoint
    var radius: CGFloat
    /// Вершины без скругления относительно center. Пустой массив означает круг.
    var hull: [CGPoint] = []
    var rounding: CGFloat = 0
}

/// Мир Box2D для снежков. Снаружи всё в пунктах экрана, внутри в метрах: Box2D настроен на тела 0,1–10 м.
final class SnowballWorld {
    static let pointsPerMeter: CGFloat = 50
    /// Лежащий шар утоплен в снег на эту долю радиуса нижнего шара.
    static let footSink: CGFloat = 0.15
    /// Метка стопы в данных формы.
    static let footTag = 100

    struct Material {
        var friction: Float = 0.6
        var restitution: Float = 0.17
        var rollingResistance: Float = 0.2
    }

    let world: b2WorldId
    /// Неподвижное тело для пружины мыши.
    let anchor: b2BodyId
    let material = Material()

    init(gravity: CGFloat) {
        var def = b2DefaultWorldDef()
        def.gravity = b2Vec2(x: 0, y: Self.meters(-gravity))
        // Снег вязкий: шары почти не отскакивают даже при быстром ударе.
        def.restitutionThreshold = Self.meters(220)
        // Удар слабее этого шар не мнёт.
        def.hitEventThreshold = Self.meters(180)
        // Жёсткие контакты: лежащий шар оседает в опору на тысячные доли пункта.
        def.contactHertz = 120
        world = b2CreateWorld(&def)
        var body = b2DefaultBodyDef()
        body.type = b2_staticBody
        anchor = b2CreateBody(world, &body)
    }

    deinit { b2DestroyWorld(world) }

    static func meters(_ value: CGFloat) -> Float { Float(value / pointsPerMeter) }
    static func points(_ value: Float) -> CGFloat { CGFloat(value) * pointsPerMeter }
    static func meters(_ point: CGPoint) -> b2Vec2 { b2Vec2(x: meters(point.x), y: meters(point.y)) }
    static func meters(_ vector: CGVector) -> b2Vec2 { b2Vec2(x: meters(vector.dx), y: meters(vector.dy)) }
    static func points(_ vector: b2Vec2) -> CGPoint { CGPoint(x: points(vector.x), y: points(vector.y)) }
    static func velocity(_ vector: b2Vec2) -> CGVector { CGVector(dx: points(vector.x), dy: points(vector.y)) }
    static func key(_ value: Int) -> UnsafeMutableRawPointer? { UnsafeMutableRawPointer(bitPattern: value) }
    static func key(_ pointer: UnsafeMutableRawPointer?) -> Int { Int(bitPattern: pointer) }

    func step(_ dt: TimeInterval) { b2World_Step(world, Float(dt), 2) }

    private var surface: b2SurfaceMaterial {
        var surface = b2DefaultSurfaceMaterial()
        surface.friction = material.friction
        surface.restitution = material.restitution
        surface.rollingResistance = material.rollingResistance
        return surface
    }

    func makeStaticBody(key: Int) -> b2BodyId {
        var def = b2DefaultBodyDef()
        def.type = b2_staticBody
        def.userData = Self.key(key)
        return b2CreateBody(world, &def)
    }

    /// Ломаная из точек в пунктах. Открытая цепочка односторонняя: точки идут справа налево, нормаль смотрит вверх.
    /// Крайние точки открытой цепочки служат только призраками для гладкого качения.
    @discardableResult
    func makeChain(on body: b2BodyId, points: [CGPoint], loop: Bool = false, category: UInt64, mask: UInt64) -> b2ChainId {
        let vertices = points.map { Self.meters($0) }
        let material = surface
        return vertices.withUnsafeBufferPointer { buffer in
            withUnsafePointer(to: material) { materialPointer in
                var def = b2DefaultChainDef()
                def.points = buffer.baseAddress
                def.count = Int32(buffer.count)
                def.materials = materialPointer
                def.materialCount = 1
                def.isLoop = loop
                def.filter.categoryBits = category
                def.filter.maskBits = mask
                return b2CreateChain(body, &def)
            }
        }
    }

    func makeBox(on body: b2BodyId, rect: CGRect, category: UInt64, mask: UInt64) {
        guard rect.width > 0.02, rect.height > 0.02 else { return }
        var def = b2DefaultShapeDef()
        def.material = surface
        def.filter.categoryBits = category
        def.filter.maskBits = mask
        var box = b2MakeOffsetBox(Self.meters(rect.width / 2), Self.meters(rect.height / 2),
                                  Self.meters(CGPoint(x: rect.midX, y: rect.midY)), b2Rot_identity)
        b2CreatePolygonShape(body, &def, &box)
    }

    func makeSegment(on body: b2BodyId, from start: CGPoint, to end: CGPoint, category: UInt64, mask: UInt64) {
        var def = b2DefaultShapeDef()
        def.material = surface
        def.filter.categoryBits = category
        def.filter.maskBits = mask
        var segment = b2Segment(point1: Self.meters(start), point2: Self.meters(end))
        b2CreateSegmentShape(body, &def, &segment)
    }

    /// Тело фигуры: начало координат в центре нижнего шара.
    func makeFigure(parts: [SnowballPart], at center: CGPoint, rotation: CGFloat, key: Int, fixedRotation: Bool) -> b2BodyId {
        var def = b2DefaultBodyDef()
        def.type = b2_dynamicBody
        def.position = Self.meters(center)
        def.rotation = b2MakeRot(Float(rotation))
        def.userData = Self.key(key)
        def.fixedRotation = fixedRotation
        let body = b2CreateBody(world, &def)
        addShapes(parts, to: body)
        return body
    }

    func replaceShapes(of body: b2BodyId, with parts: [SnowballPart]) {
        let count = Int(b2Body_GetShapeCount(body))
        var shapes = [b2ShapeId](repeating: b2ShapeId(), count: count)
        _ = shapes.withUnsafeMutableBufferPointer { b2Body_GetShapes(body, $0.baseAddress, Int32(count)) }
        for shape in shapes { b2DestroyShape(shape, false) }
        addShapes(parts, to: body)
    }

    private func addShapes(_ parts: [SnowballPart], to body: b2BodyId) {
        for (index, part) in parts.enumerated() {
            var def = b2DefaultShapeDef()
            def.density = 1
            def.material = surface
            def.filter.categoryBits = SnowballCategory.ball
            def.filter.maskBits = SnowballCategory.ballMask
            def.enableHitEvents = true
            def.enableContactEvents = true
            def.updateBodyMass = false
            def.userData = Self.key(index)
            addShape(part, inset: 0, def: &def, to: body)
            guard index == 0 else { continue }
            // Стопа меньше шара: на снегу шар утоплен на 15% радиуса, но не ниже ложа.
            def.density = 0
            def.filter.categoryBits = SnowballCategory.foot
            def.filter.maskBits = SnowballCategory.snow
            def.userData = Self.key(Self.footTag)
            addShape(part, inset: part.radius * Self.footSink, def: &def, to: body)
        }
        b2Body_ApplyMassFromShapes(body)
    }

    private func addShape(_ part: SnowballPart, inset: CGFloat, def: inout b2ShapeDef, to body: b2BodyId) {
        if part.hull.count >= 3 {
            let points = part.hull.map { Self.meters(CGPoint(x: part.center.x + $0.x, y: part.center.y + $0.y)) }
            var hull = points.withUnsafeBufferPointer { b2ComputeHull($0.baseAddress, Int32($0.count)) }
            if hull.count >= 3 {
                var polygon = b2MakePolygon(&hull, Self.meters(max(0.5, part.rounding - inset)))
                b2CreatePolygonShape(body, &def, &polygon)
                return
            }
        }
        var circle = b2Circle(center: Self.meters(part.center), radius: Self.meters(part.radius - inset))
        b2CreateCircleShape(body, &def, &circle)
    }
}
