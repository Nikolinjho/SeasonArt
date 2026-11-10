import CBox2D
import CoreGraphics
import Foundation

/// Мир Box2D для снежков. Снаружи всё в пунктах экрана, внутри в метрах: Box2D настроен на тела 0,1–10 м.
final class SnowballWorld {
    static let pointsPerMeter: CGFloat = 50

    struct Material {
        var friction: Float = 0.6
        var restitution: Float = 0.05
        var rollingResistance: Float = 0.25
    }

    private let world: b2WorldId
    private let groundBody: b2BodyId
    private var groundChain: b2ChainId?
    private var groundSignature: [Float] = []
    var material = Material()

    init(gravity: CGFloat) {
        var def = b2DefaultWorldDef()
        def.gravity = b2Vec2(x: 0, y: Float(-gravity / Self.pointsPerMeter))
        // Снег вязкий: шары почти не отскакивают даже при быстром ударе.
        def.restitutionThreshold = Float(220 / Self.pointsPerMeter)
        world = b2CreateWorld(&def)
        var body = b2DefaultBodyDef()
        body.type = b2_staticBody
        groundBody = b2CreateBody(world, &body)
    }

    deinit { b2DestroyWorld(world) }

    static func meters(_ value: CGFloat) -> Float { Float(value / pointsPerMeter) }
    static func points(_ value: Float) -> CGFloat { CGFloat(value) * pointsPerMeter }
    static func meters(_ point: CGPoint) -> b2Vec2 { b2Vec2(x: meters(point.x), y: meters(point.y)) }
    static func points(_ vector: b2Vec2) -> CGPoint { CGPoint(x: points(vector.x), y: points(vector.y)) }

    /// Поверхность земли по колонкам. Цепочка пересобирается, только если профиль заметно изменился.
    func setGround(heights: [CGFloat], originX: CGFloat, columnWidth: CGFloat, tolerance: CGFloat = 0.5) {
        guard heights.count >= 2 else { return }
        let signature = heights.map { Float(($0 / tolerance).rounded()) }
        guard signature != groundSignature else { return }
        groundSignature = signature
        if let chain = groundChain { b2DestroyChain(chain) }
        // Цепочка односторонняя: точки идут справа налево, нормаль смотрит вверх. Края уходят вниз.
        var points: [b2Vec2] = []
        let right = originX + CGFloat(heights.count) * columnWidth
        points.append(Self.meters(CGPoint(x: right + 1000, y: -1000)))
        for index in heights.indices.reversed() {
            points.append(Self.meters(CGPoint(x: originX + (CGFloat(index) + 0.5) * columnWidth, y: heights[index])))
        }
        points.append(Self.meters(CGPoint(x: originX - 1000, y: -1000)))
        var surface = b2DefaultSurfaceMaterial()
        surface.friction = material.friction
        surface.restitution = material.restitution
        surface.rollingResistance = material.rollingResistance
        groundChain = points.withUnsafeBufferPointer { buffer in
            withUnsafePointer(to: surface) { surfacePointer in
                var def = b2DefaultChainDef()
                def.points = buffer.baseAddress
                def.count = Int32(buffer.count)
                def.materials = surfacePointer
                def.materialCount = 1
                return b2CreateChain(groundBody, &def)
            }
        }
    }

    @discardableResult
    func addBall(radius: CGFloat, center: CGPoint) -> b2BodyId {
        var def = b2DefaultBodyDef()
        def.type = b2_dynamicBody
        def.position = Self.meters(center)
        let body = b2CreateBody(world, &def)
        var shape = b2DefaultShapeDef()
        shape.density = 1
        shape.material.friction = material.friction
        shape.material.restitution = material.restitution
        shape.material.rollingResistance = material.rollingResistance
        var circle = b2Circle(center: b2Vec2(x: 0, y: 0), radius: Self.meters(radius))
        b2CreateCircleShape(body, &shape, &circle)
        return body
    }

    func center(of body: b2BodyId) -> CGPoint { Self.points(b2Body_GetPosition(body)) }
    func angle(of body: b2BodyId) -> CGFloat { CGFloat(b2Rot_GetAngle(b2Body_GetRotation(body))) }
    func isAwake(_ body: b2BodyId) -> Bool { b2Body_IsAwake(body) }
    func setVelocity(_ body: b2BodyId, _ velocity: CGVector) {
        b2Body_SetLinearVelocity(body, b2Vec2(x: Self.meters(velocity.dx), y: Self.meters(velocity.dy)))
        // Брошенный шар проверяет столкновения непрерывно: на скорости он не проскочит сквозь другой.
        b2Body_SetBullet(body, hypot(velocity.dx, velocity.dy) > 600)
    }

    func step(_ dt: TimeInterval) { b2World_Step(world, Float(dt), 4) }
}
