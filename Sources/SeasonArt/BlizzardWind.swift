import simd

/// Непрерывные порывы и местные завихрения без случайных толчков на каждом кадре.
struct BlizzardWind {
    private(set) var amount: Float = 0
    private var time: Double = 0

    mutating func step(dt: Float, enabled: Bool) {
        guard dt.isFinite, dt > 0 else { return }
        let step = min(dt, 0.1)
        time += Double(step)
        let target: Float = enabled ? 1 : 0
        amount += (target - amount) * (1 - exp(-step / 0.9))
        if !enabled && amount < 0.0001 { amount = 0 }
    }

    func velocity(at position: SIMD2<Float>, phase: Float, depth: Float) -> SIMD2<Float> {
        guard amount > 0 else { return .zero }
        let t = Float(time)
        let gust = 40 * sin(t * 0.53) + 22 * sin(t * 0.97 + 1.1)
        let across = 18 * sin(position.y * 0.012 - t * 1.4 + phase * 0.2)
            + 12 * cos(position.x * 0.009 + position.y * 0.007 + t * 0.8)
        let lift = 12 * cos(position.x * 0.011 - t * 0.9 + phase * 0.15)
            + 6 * sin(position.y * 0.014 + t * 1.2)
        let response = amount * (0.4 + 0.6 * min(1, max(0, depth)))
        return SIMD2(gust + across, lift) * response
    }
}
