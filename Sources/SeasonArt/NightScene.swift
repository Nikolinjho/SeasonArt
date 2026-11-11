import CoreGraphics
import simd

/// Открытый участок опоры в координатах эффекта, с началом снизу слева.
struct NightSupport {
    let left: Float
    let right: Float
    let y: Float
}

/// Светлячки и метеоры используют общий вывод Sprite, но не создают массу снега.
final class NightScene {
    var mode = Mode.snow {
        didSet {
            guard mode != oldValue else { return }
            clear()
        }
    }
    private(set) var sprites: [Sprite] = []
    var colorfulFireflies = false {
        didSet { writeSprites() }
    }
    private static let fireflyPalette: [SIMD3<Float>] = [
        SIMD3(1, 0.87, 0.35), SIMD3(0.55, 1, 0.42), SIMD3(0.35, 1, 0.85),
        SIMD3(0.45, 0.72, 1), SIMD3(0.78, 0.52, 1), SIMD3(1, 0.5, 0.73),
    ]
    private var width: Float
    private var height: Float
    private var seed: UInt64
    private var time: Float = 0
    private var remainder: Double = 0
    private var pointerAnchor: SIMD2<Float>?
    private var stillTime: Float = 0
    private var nextMeteor: Float = 0.3
    private var flies: [Particle] = []
    private var meteors: [Particle] = []
    private var sparks: [Particle] = []

    private struct Particle {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float> = .zero
        var phase: Float
        var size: Float
        var age: Float = 0
        var life: Float = 1
    }

    init(width: Float, height: Float, seed: UInt64 = 0x534541534F4E) {
        self.width = width
        self.height = height
        self.seed = max(1, seed)
    }

    func resize(width: Float, height: Float) {
        self.width = width
        self.height = height
        for i in flies.indices {
            flies[i].position.x = min(max(0, flies[i].position.x), max(0, width))
            flies[i].position.y = min(max(0, flies[i].position.y), max(0, height))
        }
    }

    func step(dt: Float, intensity: Float, cursor: SIMD2<Float>, supports: [NightSupport]) {
        guard dt.isFinite, dt > 0 else { return }
        guard (mode == .fireflies || mode == .starfall), intensity.isFinite, intensity > 0,
              width.isFinite, height.isFinite, width > 0, height > 0 else {
            clear()
            return
        }
        let strength = min(intensity, 3)
        if mode == .fireflies {
            let count = min(160, max(6, Int(min(width * height / 1_000_000, 10) * 42 * strength)))
            if flies.count > count { flies.removeLast(flies.count - count) }
            while flies.count < count {
                let region = flightRegion(index: flies.count, count: count)
                let offset = SIMD2(random(-0.2, 0.2), random(-0.2, 0.2)) * region.size
                flies.append(Particle(position: region.center + offset,
                                      phase: random(0, 2 * .pi), size: random(9, 16)))
            }
        }
        remainder += Double(min(dt, 0.1))
        let fixed = 1.0 / 120
        while remainder + 0.00000001 >= fixed {
            remainder -= fixed
            time += Float(fixed)
            if mode == .fireflies {
                moveFlies(dt: Float(fixed), cursor: cursor)
            } else {
                moveMeteors(dt: Float(fixed), intensity: strength, supports: supports)
            }
        }
        writeSprites()
    }

    /// Ряды содержат почти одинаковое число областей, в том числе при нечётном количестве огоньков.
    private func flightRegion(index: Int, count: Int) -> (center: SIMD2<Float>, size: SIMD2<Float>) {
        let rows = min(count, max(1, Int(sqrt(Float(count) * height / width).rounded())))
        let perRow = count / rows
        let extra = count % rows
        let fullRows = (perRow + 1) * extra
        let row = index < fullRows ? index / (perRow + 1) : extra + (index - fullRows) / perRow
        let columns = perRow + (row < extra ? 1 : 0)
        let column = index - row * perRow - min(row, extra)
        let size = SIMD2(width / Float(columns), height / Float(rows))
        return (SIMD2(Float(column) + 0.5, Float(row) + 0.5) * size, size)
    }

    private func moveFlies(dt: Float, cursor: SIMD2<Float>) {
        let inside = cursor.x.isFinite && cursor.y.isFinite && cursor.x >= 0 && cursor.x <= width
            && cursor.y >= 0 && cursor.y <= height
        if inside {
            if let anchor = pointerAnchor, simd_distance(anchor, cursor) <= 8 {
                stillTime += dt
            } else {
                pointerAnchor = cursor
                stillTime = 0
            }
        } else {
            pointerAnchor = nil
            stillTime = 0
        }
        // Все силы читают один снимок: порядок обхода не меняет раздвигание соседей.
        let positions = flies.map(\.position)
        let spacing = min(85, sqrt(width * height / Float(flies.count)) * 0.45)
        for i in flies.indices {
            let phase = flies[i].phase
            let region = flightRegion(index: i, count: flies.count)
            let wander = SIMD2(sin(time * 0.11 + phase), cos(time * 0.09 + phase * 3)) * region.size * 0.28
            var force = SIMD2(sin(time * 0.7 + phase) * 22, cos(time * 0.53 + phase * 3) * 18)
            force += (region.center + wander - positions[i]) * 0.18
            let distance = simd_distance(positions[i], cursor)
            if inside, stillTime >= 0.6, distance < 200 {
                force += (cursor - positions[i]) * (0.035 * (1 - distance / 200))
            }
            for j in positions.indices where j != i {
                let delta = positions[i] - positions[j]
                let separation = simd_length(delta)
                if separation < spacing {
                    let direction = separation > 0.001 ? delta / separation
                        : SIMD2(cos(phase), sin(phase))
                    force += direction * ((spacing - separation) * 0.8)
                }
            }
            // Мягкая граница удерживает огоньки на экране без скачка с края на край.
            let p = flies[i].position
            force += SIMD2(max(0, 30 - p.x) - max(0, p.x - width + 30),
                           max(0, 30 - p.y) - max(0, p.y - height + 30)) * 1.2
            flies[i].velocity = (flies[i].velocity + force * dt) * exp(-dt * 1.3)
            let speed = simd_length(flies[i].velocity)
            if speed > 90 { flies[i].velocity *= 90 / speed }
            flies[i].position += flies[i].velocity * dt
            flies[i].position = simd_clamp(flies[i].position, .zero, SIMD2(width, height))
        }
    }

    private func moveMeteors(dt: Float, intensity: Float, supports: [NightSupport]) {
        for i in sparks.indices.reversed() {
            sparks[i].age += dt
            if sparks[i].age >= sparks[i].life {
                sparks.remove(at: i)
            } else {
                sparks[i].velocity.y -= 220 * dt
                sparks[i].position += sparks[i].velocity * dt
            }
        }
        for i in meteors.indices.reversed() {
            let before = meteors[i].position
            let after = before + meteors[i].velocity * dt
            var hit: (fraction: Float, point: SIMD2<Float>)?
            func intersect(_ surface: NightSupport) {
                guard before.y >= surface.y, after.y <= surface.y, before.y > after.y else { return }
                let fraction = (before.y - surface.y) / (before.y - after.y)
                let x = before.x + (after.x - before.x) * fraction
                guard x >= surface.left, x < surface.right, fraction < (hit?.fraction ?? 2) else { return }
                hit = (fraction, SIMD2(x, surface.y))
            }
            intersect(NightSupport(left: 0, right: width, y: 0))
            for support in supports { intersect(support) }
            if let hit {
                for _ in 0..<16 where sparks.count < 120 {
                    sparks.append(Particle(position: hit.point,
                        velocity: SIMD2(random(-130, 130), random(25, 150)),
                        phase: random(0, 2 * .pi), size: random(4, 8), life: random(0.45, 0.85)))
                }
                meteors.remove(at: i)
            } else if after.y < -30 || after.x < -100 {
                meteors.remove(at: i)
            } else {
                meteors[i].position = after
                meteors[i].age += dt
            }
        }
        nextMeteor -= dt
        if nextMeteor <= 0, meteors.count < 12 {
            meteors.append(Particle(position: SIMD2(random(width * 0.1, width + height * 0.35), height + 12),
                velocity: SIMD2(random(-340, -180), random(-500, -320)), phase: random(0, 2 * .pi), size: random(6, 9)))
            nextMeteor = random(0.65, 1.65) / intensity
        }
    }

    private func writeSprites() {
        sprites.removeAll(keepingCapacity: true)
        for (index, fly) in flies.enumerated() {
            let pulse = 0.4 + 0.6 * pow(0.5 + 0.5 * sin(time * 2.1 + fly.phase), 2)
            let tint = colorfulFireflies ? Self.fireflyPalette[index % Self.fireflyPalette.count] : SIMD3(0.86, 1, 0.32)
            sprites.append(Sprite(position: fly.position, size: fly.size, alpha: pulse, soft: 1,
                tintAmount: 1, tintRed: tint.x, tintGreen: tint.y, tintBlue: tint.z, glow: 1))
        }
        for meteor in meteors {
            sprites.append(Sprite(position: meteor.position, velocity: meteor.velocity, size: meteor.size,
                alpha: min(1, meteor.age * 6), soft: 1, tintAmount: 1,
                tintRed: 0.65, tintGreen: 0.82, tintBlue: 1, glow: 1, trail: 65))
        }
        for spark in sparks {
            sprites.append(Sprite(position: spark.position, size: spark.size,
                alpha: pow(max(0, 1 - spark.age / spark.life), 1.5), soft: 1,
                tintAmount: 1, tintRed: 0.78, tintGreen: 0.9, tintBlue: 1, glow: 1))
        }
    }

    private func clear() {
        flies.removeAll()
        meteors.removeAll()
        sparks.removeAll()
        sprites.removeAll()
        pointerAnchor = nil
        stillTime = 0
        remainder = 0
        nextMeteor = 0.3
    }

    private func random(_ low: Float, _ high: Float) -> Float {
        seed ^= seed << 13
        seed ^= seed >> 7
        seed ^= seed << 17
        return low + Float(seed >> 40) / Float(1 << 24) * (high - low)
    }
}
