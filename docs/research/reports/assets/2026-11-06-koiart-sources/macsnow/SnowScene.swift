import AppKit
import SpriteKit

struct SnowCollisionEdge: Equatable {
    let xRange: ClosedRange<CGFloat>
    let y: CGFloat
    let windowID: CGWindowID
    let order: Int

    var key: String {
        "\(windowID)-\(Int(y / 8))"
    }
}

@MainActor
final class SnowScene: SKScene {
    private struct SnowflakeSizeTier {
        let scale: CGFloat
        let birthRateShare: CGFloat
        let speedMultiplier: CGFloat
        let alpha: CGFloat
    }

    private struct FallingSnowflake {
        let node: SKShapeNode
        let radius: CGFloat
        var velocity: CGVector
    }

    private struct BirdAgent {
        let node: SKSpriteNode
        var velocity: CGVector
        var baseScale: CGFloat
        var frameIndex: Int
        var nextFrameTime: TimeInterval
        var bobPhase: CGFloat
    }

    private struct FallingGift {
        let node: SKNode
        var velocity: CGVector
        var baseScale: CGFloat
    }

    private struct MovingPolarBear {
        let node: SKNode
        let body: SKNode
        var target: CGPoint
        var velocity: CGVector
        var facingDirection: CGFloat
        var bobPhase: CGFloat
        var stridePhase: CGFloat
        var isRunning: Bool
        var nextRunDecisionTime: TimeInterval
        var nextPawPrintTime: TimeInterval
        var nextTargetTime: TimeInterval
    }

    private struct MovingAnimal {
        let node: SKNode
        var target: CGPoint
        var velocity: CGVector
        var baseScale: CGFloat
        var cruiseSpeed: CGFloat
        var directionFlip: CGFloat
        var bobPhase: CGFloat
        var stridePhase: CGFloat
        var nextTargetTime: TimeInterval
    }

    private struct SantaFlight {
        let node: SKNode
        let sprite: SKSpriteNode?
        let textures: [SKTexture]
        let direction: CGFloat
        let speed: CGFloat
        let plowWidth: CGFloat
        let startX: CGFloat
        let endX: CGFloat
        let startY: CGFloat
        let endY: CGFloat
        let baseScale: CGFloat
        let depthPeak: CGFloat
        var targetY: CGFloat
        var verticalVelocity: CGFloat
        var nextYChange: TimeInterval
        var nextFrameChange: TimeInterval
        var frameIndex: Int
        var giftTime: TimeInterval
        var hasDroppedGift: Bool
        var moonSeeking: Bool
        var nextPlowTime: TimeInterval
    }

    private enum GroundAgentState {
        case idle
        case walk
        case run
        case sleep
    }

    private static let snowflakeSizeTiers: [SnowflakeSizeTier] = [
        SnowflakeSizeTier(scale: 0.42, birthRateShare: 0.20, speedMultiplier: 0.82, alpha: 0.62),
        SnowflakeSizeTier(scale: 0.62, birthRateShare: 0.24, speedMultiplier: 0.92, alpha: 0.74),
        SnowflakeSizeTier(scale: 0.82, birthRateShare: 0.24, speedMultiplier: 1.0, alpha: 0.84),
        SnowflakeSizeTier(scale: 1.08, birthRateShare: 0.20, speedMultiplier: 1.08, alpha: 0.9),
        SnowflakeSizeTier(scale: 1.38, birthRateShare: 0.12, speedMultiplier: 1.18, alpha: 0.95)
    ]

    private static let passiveSnowflakeTierCount = 1
    private let emitters = SnowScene.snowflakeSizeTiers.prefix(passiveSnowflakeTierCount).map { _ in SKEmitterNode() }
    private let largeFlakeRoot = SKNode()
    private let celestialRoot = SKNode()
    private let birdRoot = SKNode()
    private let groundDriftRoot = SKNode()
    private let seasonalRoot = SKNode()
    private let agentRoot = SKNode()
    private let santaRoot = SKNode()
    private let giftRoot = SKNode()
    private let accumulationRoot = SKNode()
    private let collapseRoot = SKNode()
    private var density: SnowDensity = .normal
    private var windStrength = 0.2
    private var windDirection: WindDirection = .right
    private var visualScale: VisualScale = .normal
    private var snowColorMode: SnowColorMode = .white
    private var isCelestialEffectsEnabled = true
    private var isAuroraEnabled = true
    private var isMoonEnabled = true
    private var areStarsEnabled = true
    private var areMeteorsEnabled = true
    private var moonPosition: CGPoint?
    private var areBirdsEnabled = true
    private var isSantaEnabled = true
    private var isSceneryEnabled = true
    private var areTreesEnabled = true
    private var isGiftTreeEnabled = true
    private var isSnowmanEnabled = true
    private var isHouseEnabled = true
    private var isReindeerEnabled = true
    private var isMooseEnabled = true
    private var isPolarBearEnabled = true
    private var isGroundAgentEnabled = true
    private var areGiftsEnabled = true
    private var winterObjectOptions = WinterObject.defaultOptions
    private var objectAmount: ObjectAmount = .normal
    private var santaStyle: SantaStyle = .big
    private var santaSpeed: SantaSpeed = .normal
    private var santaScale: SantaScale = .normal
    private var isRudolphEnabled = true
    private var randomWindMultiplier: Double = 1.0
    private var nextRandomWindChange: TimeInterval = 0
    private var collisionEdges: [SnowCollisionEdge] = []
    private var accumulationByEdgeKey: [String: CGFloat] = [:]
    private var edgeByKey: [String: SnowCollisionEdge] = [:]
    private var isAccumulationEnabled = true
    private var accumulationSpillMode: AccumulationSpillMode = .off
    private var accumulationRate: AccumulationRate = .normal
    private var accumulationStyle: AccumulationStyle = .layered
    private let maximumCollisionEdges = 32
    private let maximumCollapseNodes = 64
    private var currentSceneTime: TimeInterval = 0
    private var lastSpillByEdgeKey: [String: TimeInterval] = [:]
    private var lastSettlingCheck: TimeInterval = 0
    private var fallingLargeFlakes: [FallingSnowflake] = []
    private var lastUpdateTime: TimeInterval = 0
    private var lastBirdUpdateTime: TimeInterval = 0
    private var lastSantaUpdateTime: TimeInterval = 0
    private var largeFlakeSpawnCarry: CGFloat = 0
    private var nextMeteorTime: TimeInterval = 0
    private var nextSantaTime: TimeInterval = 0
    private var activeSanta: SantaFlight?
    private var birds: [BirdAgent] = []
    private var birdTextureCache: [String: SKTexture] = [:]
    private var fallingGifts: [FallingGift] = []
    private var groundAgentState: GroundAgentState = .idle
    private var groundAgent: SKNode?
    private var movingPolarBear: MovingPolarBear?
    private var movingAnimals: [MovingAnimal] = []
    private var groundAgentBaseY: CGFloat = 0
    private var groundAgentBobPhase: CGFloat = 0
    private var groundAgentVelocity: CGFloat = 24
    private var groundAgentTarget: CGPoint?
    private var groundAgentVelocityVector = CGVector.zero
    private var nextAgentStateChange: TimeInterval = 0
    private var lastAgentUpdateTime: TimeInterval = 0
    private var lastPolarBearUpdateTime: TimeInterval = 0
    private var lastMovingAnimalUpdateTime: TimeInterval = 0
    private var plantedTreeKeys: Set<String> = []
    private var nextSmoothingTime: TimeInterval = 30

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        anchorPoint = CGPoint(x: 0, y: 0)
        physicsWorld.gravity = CGVector(dx: 0, dy: -1.2)
        configureEmitters()
        celestialRoot.zPosition = -20
        groundDriftRoot.zPosition = 1
        accumulationRoot.zPosition = 8
        seasonalRoot.zPosition = 14
        agentRoot.zPosition = 16
        birdRoot.zPosition = 18
        giftRoot.zPosition = 20
        santaRoot.zPosition = 24
        largeFlakeRoot.zPosition = 30
        collapseRoot.zPosition = 32
        addChild(celestialRoot)
        addChild(birdRoot)
        addChild(largeFlakeRoot)
        addChild(groundDriftRoot)
        addChild(seasonalRoot)
        addChild(agentRoot)
        addChild(santaRoot)
        addChild(giftRoot)
        addChild(accumulationRoot)
        addChild(collapseRoot)
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    func setSnowEnabled(_ enabled: Bool) {
        isPaused = !enabled
        if enabled {
            lastUpdateTime = 0
            lastBirdUpdateTime = 0
            lastSantaUpdateTime = 0
            lastAgentUpdateTime = 0
            nextSantaTime = min(nextSantaTime, currentSceneTime)
        }
        updateEmitterBirthRates()
    }

    func apply(density: SnowDensity, windStrength: Double, windDirection: WindDirection) {
        self.density = density
        self.windStrength = windStrength
        self.windDirection = windDirection
        if windDirection != .random {
            randomWindMultiplier = windDirection.multiplier
        } else if randomWindMultiplier == 0 {
            randomWindMultiplier = Bool.random() ? -1 : 1
        }
        applyWind()
        updateEmitterBirthRates()
    }

    func setAccumulationEnabled(_ enabled: Bool) {
        guard enabled != isAccumulationEnabled else {
            return
        }

        isAccumulationEnabled = enabled
        if enabled {
            rebuildAccumulationNodes()
        } else {
            accumulationByEdgeKey.removeAll()
            edgeByKey.removeAll()
            accumulationRoot.removeAllChildren()
            collapseRoot.removeAllChildren()
        }
    }

    func setVisualScale(_ scale: VisualScale) {
        visualScale = scale
        applyVisualScale()
        configureSnowColors()
        rebuildGroundDrift()
        rebuildSeasonalObjects()
        rebuildAccumulationNodes()
    }

    func setSnowColorMode(_ mode: SnowColorMode) {
        snowColorMode = mode
        configureSnowColors()
    }

    func setCelestialEffectsEnabled(_ enabled: Bool) {
        isCelestialEffectsEnabled = enabled
        if enabled {
            rebuildCelestialEffects()
        } else {
            celestialRoot.removeAllChildren()
        }
    }

    func setCelestialItemOptions(aurora: Bool, moon: Bool, stars: Bool, meteors: Bool) {
        isAuroraEnabled = aurora
        isMoonEnabled = moon
        areStarsEnabled = stars
        areMeteorsEnabled = meteors
        rebuildCelestialEffects()
    }

    func setBirdsEnabled(_ enabled: Bool) {
        areBirdsEnabled = enabled
        if !enabled {
            birdRoot.removeAllChildren()
            birds.removeAll()
        }
    }

    func setSantaEnabled(_ enabled: Bool) {
        isSantaEnabled = enabled
        if enabled {
            nextSantaTime = min(nextSantaTime, currentSceneTime)
        } else {
            santaRoot.removeAllChildren()
            activeSanta = nil
        }
    }

    func setSceneryEnabled(_ enabled: Bool) {
        isSceneryEnabled = enabled
        if !enabled {
            movingPolarBear?.node.removeFromParent()
            movingPolarBear = nil
            movingAnimals.removeAll()
            agentRoot.children.filter { $0.name == "movingAnimal" }.forEach { $0.removeFromParent() }
            lastPolarBearUpdateTime = 0
            lastMovingAnimalUpdateTime = 0
        }
        rebuildSeasonalObjects()
    }

    func setSceneryItemOptions(trees: Bool, giftTree: Bool, snowman: Bool, house: Bool, reindeer: Bool, moose: Bool, polarBear: Bool) {
        areTreesEnabled = trees
        isGiftTreeEnabled = giftTree
        isSnowmanEnabled = snowman
        isHouseEnabled = house
        isReindeerEnabled = reindeer
        isMooseEnabled = moose
        isPolarBearEnabled = polarBear
        if !polarBear {
            movingPolarBear?.node.removeFromParent()
            movingPolarBear = nil
            lastPolarBearUpdateTime = 0
        }
        movingAnimals.removeAll()
        agentRoot.children.filter { $0.name == "movingAnimal" }.forEach { $0.removeFromParent() }
        lastMovingAnimalUpdateTime = 0
        rebuildSeasonalObjects()
    }

    func setWinterObjectOptions(_ options: [String: Bool]) {
        winterObjectOptions = WinterObject.defaultOptions.merging(options) { _, new in new }
        movingAnimals.removeAll()
        agentRoot.children.filter { $0.name == "movingAnimal" }.forEach { $0.removeFromParent() }
        lastMovingAnimalUpdateTime = 0
        rebuildSeasonalObjects()
    }

    func setObjectAmount(_ amount: ObjectAmount) {
        objectAmount = amount
        birds.removeAll()
        birdRoot.removeAllChildren()
        movingAnimals.removeAll()
        agentRoot.children.filter { $0.name == "movingAnimal" }.forEach { $0.removeFromParent() }
        rebuildCelestialEffects()
        rebuildSeasonalObjects()
    }

    func setGroundAgentEnabled(_ enabled: Bool) {
        isGroundAgentEnabled = enabled
        if !enabled {
            agentRoot.removeAllChildren()
            groundAgent = nil
        } else {
            setupGroundAgentIfNeeded()
        }
    }

    func setGiftsEnabled(_ enabled: Bool) {
        areGiftsEnabled = enabled
        if !enabled {
            giftRoot.removeAllChildren()
            fallingGifts.removeAll()
            seasonalRoot.children.filter { $0.name == "gift" }.forEach { $0.removeFromParent() }
        } else {
            rebuildSeasonalObjects()
        }
    }

    func setSantaOptions(style: SantaStyle, speed: SantaSpeed, scale: SantaScale, isRudolphEnabled: Bool) {
        santaStyle = style
        santaSpeed = speed
        santaScale = scale
        self.isRudolphEnabled = isRudolphEnabled
        nextSantaTime = min(nextSantaTime, currentSceneTime)
    }

    func setAccumulationSpillMode(_ mode: AccumulationSpillMode) {
        accumulationSpillMode = mode
    }

    func setAccumulationRate(_ rate: AccumulationRate) {
        accumulationRate = rate
        for key in accumulationByEdgeKey.keys {
            accumulationByEdgeKey[key] = min(accumulationByEdgeKey[key] ?? 0, rate.maximumHeight)
        }
        rebuildAccumulationNodes()
    }

    func setAccumulationStyle(_ style: AccumulationStyle) {
        accumulationStyle = style
        rebuildAccumulationNodes()
    }

    func clearAccumulation() {
        accumulationByEdgeKey.removeAll()
        edgeByKey.removeAll()
        lastSpillByEdgeKey.removeAll()
        accumulationRoot.removeAllChildren()
        collapseRoot.removeAllChildren()
        fallingLargeFlakes.removeAll()
        largeFlakeRoot.removeAllChildren()
        plantedTreeKeys.removeAll()
    }

    func clearDisplayContents() {
        emitters.forEach { $0.resetSimulation() }
        celestialRoot.removeAllChildren()
        birdRoot.removeAllChildren()
        largeFlakeRoot.removeAllChildren()
        groundDriftRoot.removeAllChildren()
        seasonalRoot.removeAllChildren()
        agentRoot.removeAllChildren()
        santaRoot.removeAllChildren()
        giftRoot.removeAllChildren()
        accumulationRoot.removeAllChildren()
        collapseRoot.removeAllChildren()

        moonPosition = nil
        collisionEdges.removeAll()
        accumulationByEdgeKey.removeAll()
        edgeByKey.removeAll()
        lastSpillByEdgeKey.removeAll()
        fallingLargeFlakes.removeAll()
        largeFlakeSpawnCarry = 0
        activeSanta = nil
        birds.removeAll()
        fallingGifts.removeAll()
        groundAgent = nil
        movingPolarBear = nil
        movingAnimals.removeAll()
        groundAgentTarget = nil
        plantedTreeKeys.removeAll()
    }

    func clearWindowTracking() {
        collisionEdges.removeAll()
        accumulationByEdgeKey.removeAll()
        edgeByKey.removeAll()
        lastSpillByEdgeKey.removeAll()
        accumulationRoot.removeAllChildren()
        collapseRoot.removeAllChildren()
        fallingLargeFlakes.removeAll()
        largeFlakeRoot.removeAllChildren()
        plantedTreeKeys.removeAll()
    }

    func updateCollisionEdges(_ edges: [SnowCollisionEdge]) {
        let limitedEdges = Array(edges.prefix(maximumCollisionEdges))
        let didChangeEdges = limitedEdges != collisionEdges

        if didChangeEdges {
            collisionEdges = limitedEdges
        }

        guard isAccumulationEnabled else {
            return
        }

        updateAccumulation(for: limitedEdges)
        rebuildAccumulationNodes()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        positionEmitters()
        rebuildCelestialEffects()
        birds.removeAll()
        birdRoot.removeAllChildren()
        rebuildGroundDrift()
        rebuildSeasonalObjects()
    }

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        currentSceneTime = currentTime
        guard !isPaused else {
            return
        }

        updateRandomWindIfNeeded(at: currentTime)
        updateCelestialEffects(at: currentTime)
        updateBirds(at: currentTime)
        updateLargeFlakes(at: currentTime)
        updateSanta(at: currentTime)
        updateGifts(deltaTime: 1.0 / 60.0)
        updateGroundAgent(at: currentTime)
        updateMovingPolarBear(at: currentTime)
        updateMovingAnimals(at: currentTime)
        smoothAccumulationIfNeeded(at: currentTime)
        settleAccumulationIfNeeded(at: currentTime)
    }

    private var baseBirthRate: CGFloat {
        max(80, size.width / 18)
    }

    private var currentBirthRate: CGFloat {
        baseBirthRate * density.birthRateMultiplier
    }

    private var accumulationSizeContribution: CGFloat {
        1 - (Self.snowflakeSizeTiers.first?.birthRateShare ?? 0)
    }

    private var largeSnowflakeBirthRate: CGFloat {
        currentBirthRate * Self.snowflakeSizeTiers.dropFirst(Self.passiveSnowflakeTierCount).reduce(0) { $0 + $1.birthRateShare }
    }

    private var windMultiplier: Double {
        windDirection == .random ? randomWindMultiplier : windDirection.multiplier
    }

    private var directedWindStrength: Double {
        windStrength * windMultiplier
    }

    private func windDrift(_ scale: CGFloat) -> CGFloat {
        CGFloat(directedWindStrength) * scale
    }

    private func applyWind() {
        for emitter in emitters {
            emitter.xAcceleration = 40 * directedWindStrength
        }
        physicsWorld.gravity = CGVector(dx: directedWindStrength * 0.6, dy: -1.2)
    }

    private func updateRandomWindIfNeeded(at currentTime: TimeInterval) {
        guard windDirection == .random, currentTime >= nextRandomWindChange else {
            return
        }

        let direction = Bool.random() ? 1.0 : -1.0
        let strengthScale = Double.random(in: 0.45...1.15)
        randomWindMultiplier = direction * strengthScale
        nextRandomWindChange = currentTime + TimeInterval.random(in: 4.0...9.0)
        applyWind()
    }

    private func configureEmitters() {
        let texture = makeSnowTexture()
        for (index, emitter) in emitters.enumerated() {
            let tier = Self.snowflakeSizeTiers[index]
            emitter.particleTexture = texture
            emitter.particleBirthRate = currentBirthRate * tier.birthRateShare
            emitter.particleLifetime = 12
            emitter.particleLifetimeRange = 4
            emitter.particlePositionRange = CGVector(dx: size.width, dy: 0)
            emitter.emissionAngle = -.pi / 2
            emitter.emissionAngleRange = .pi / 16
            emitter.particleSpeed = 80 * tier.speedMultiplier
            emitter.particleSpeedRange = 28
            emitter.yAcceleration = -18
            emitter.particleAlpha = tier.alpha
            emitter.particleAlphaRange = 0.18
            emitter.particleScale = tier.scale
            emitter.particleScaleRange = 0
            emitter.particleColor = .white
            emitter.particleColorBlendFactor = 1
            emitter.particleBlendMode = .alpha
            addChild(emitter)
        }
        configureSnowColors()
        applyWind()
        positionEmitters()
        applyVisualScale()
        rebuildCelestialEffects()
        rebuildGroundDrift()
        rebuildSeasonalObjects()
    }

    private func applyVisualScale() {
        let scale = visualScale.value
        largeFlakeRoot.setScale(scale)
        birdRoot.setScale(1.0)
        groundDriftRoot.setScale(scale)
        seasonalRoot.setScale(scale)
        agentRoot.setScale(scale)
        accumulationRoot.setScale(scale)
        collapseRoot.setScale(scale)
        santaRoot.setScale(1.0)
        giftRoot.setScale(scale)
    }

    private func configureSnowColors() {
        let colors: [NSColor]
        switch snowColorMode {
        case .white:
            colors = [.white]
        case .cool:
            colors = [.white, NSColor(calibratedRed: 0.68, green: 0.86, blue: 1.0, alpha: 1)]
        case .warm:
            colors = [.white, NSColor(calibratedRed: 1.0, green: 0.9, blue: 0.72, alpha: 1)]
        case .mixed:
            colors = [.white, NSColor(calibratedRed: 0.72, green: 0.9, blue: 1.0, alpha: 1), NSColor(calibratedRed: 1.0, green: 0.92, blue: 0.74, alpha: 1)]
        case .customBlueGold:
            colors = [NSColor(calibratedRed: 0.55, green: 0.82, blue: 1.0, alpha: 1), NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.28, alpha: 1)]
        case .customRoseMint:
            colors = [NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.78, alpha: 1), NSColor(calibratedRed: 0.55, green: 1.0, blue: 0.84, alpha: 1)]
        }

        for (index, emitter) in emitters.enumerated() {
            emitter.particleColor = colors[index % colors.count]
        }
    }

    private func snowColor(alpha: CGFloat) -> NSColor {
        switch snowColorMode {
        case .white:
            NSColor.white.withAlphaComponent(alpha)
        case .cool:
            NSColor(calibratedRed: 0.78, green: 0.9, blue: 1.0, alpha: alpha)
        case .warm:
            NSColor(calibratedRed: 1.0, green: 0.92, blue: 0.78, alpha: alpha)
        case .mixed:
            Bool.random()
                ? NSColor(calibratedRed: 0.78, green: 0.9, blue: 1.0, alpha: alpha)
                : NSColor(calibratedRed: 1.0, green: 0.92, blue: 0.78, alpha: alpha)
        case .customBlueGold:
            Bool.random()
                ? NSColor(calibratedRed: 0.55, green: 0.82, blue: 1.0, alpha: alpha)
                : NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.28, alpha: alpha)
        case .customRoseMint:
            Bool.random()
                ? NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.78, alpha: alpha)
                : NSColor(calibratedRed: 0.55, green: 1.0, blue: 0.84, alpha: alpha)
        }
    }

    private func setupBirdsIfNeeded() {
        guard birds.isEmpty, size.width > 0, size.height > 0 else {
            return
        }

        let birdCount = max(4, Int((16.0 * objectAmount.multiplier).rounded()))
        for _ in 0..<birdCount {
            let bird = makeBird()
            bird.position = CGPoint(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: size.height * 0.58...max(size.height - 92, size.height * 0.59))
            )
            birdRoot.addChild(bird)
            let dx = CGFloat.random(in: -0.58...0.58)
            let dy = CGFloat.random(in: -0.32...0.32)
            birds.append(BirdAgent(
                node: bird,
                velocity: CGVector(
                    dx: abs(dx) < 0.18 ? (dx < 0 ? -0.18 : 0.18) : dx,
                    dy: abs(dy) < 0.08 ? (dy < 0 ? -0.08 : 0.08) : dy
                ),
                baseScale: CGFloat.random(in: 0.32...0.5),
                frameIndex: Int.random(in: 0..<8),
                nextFrameTime: currentSceneTime + TimeInterval.random(in: 0...0.2),
                bobPhase: CGFloat.random(in: 0...(.pi * 2))
            ))
        }
    }

    private func makeBird() -> SKSpriteNode {
        let bird = SKSpriteNode(texture: birdTexture(prefix: "bird", frame: 0))
        bird.setScale(0.42)
        bird.alpha = 0.78
        return bird
    }

    private func birdTexture(prefix: String, frame: Int) -> SKTexture? {
        let name = "\(prefix)\(frame + 1).xpm"
        if let cached = birdTextureCache[name] {
            return cached
        }
        guard let texture = XPMTextureCache.shared.texture(named: name) else {
            return nil
        }
        birdTextureCache[name] = texture
        return texture
    }

    private func birdTexturePrefix(for velocity: CGVector) -> String {
        let sx = abs(velocity.dx)
        let sy = abs(velocity.dy)
        if sx > sy * 1.7 {
            return "birdl"
        }
        if sy > sx * 1.7 {
            return "bird"
        }
        return "birdd"
    }

    private func updateBirds(at currentTime: TimeInterval) {
        guard isCelestialEffectsEnabled, areBirdsEnabled else {
            birdRoot.removeAllChildren()
            birds.removeAll()
            lastBirdUpdateTime = 0
            return
        }

        setupBirdsIfNeeded()
        let deltaTime: CGFloat
        if lastBirdUpdateTime > 0 {
            deltaTime = CGFloat(max(0, min(currentTime - lastBirdUpdateTime, 1.0 / 30.0)))
        } else {
            deltaTime = 1.0 / 60.0
        }
        lastBirdUpdateTime = currentTime
        let perception: CGFloat = 92
        let separationDistance: CGFloat = 22

        for index in birds.indices {
            var cohesion = CGVector.zero
            var alignment = CGVector.zero
            var separation = CGVector.zero
            var neighborCount: CGFloat = 0

            let position = birds[index].node.position
            for otherIndex in birds.indices where otherIndex != index {
                let other = birds[otherIndex]
                let dx = other.node.position.x - position.x
                let dy = other.node.position.y - position.y
                let distance = max(1, hypot(dx, dy))
                guard distance < perception else {
                    continue
                }

                cohesion.dx += other.node.position.x
                cohesion.dy += other.node.position.y
                alignment.dx += other.velocity.dx
                alignment.dy += other.velocity.dy
                if distance < separationDistance {
                    separation.dx -= dx / distance
                    separation.dy -= dy / distance
                }
                neighborCount += 1
            }

            if neighborCount > 0 {
                cohesion.dx = (cohesion.dx / neighborCount - position.x) * 0.0009
                cohesion.dy = (cohesion.dy / neighborCount - position.y) * 0.0009
                alignment.dx = (alignment.dx / neighborCount - birds[index].velocity.dx) * 0.035
                alignment.dy = (alignment.dy / neighborCount - birds[index].velocity.dy) * 0.035
                separation.dx *= 0.045
                separation.dy *= 0.045
            }

            let forceScale = deltaTime * 60
            birds[index].velocity.dx += (cohesion.dx + alignment.dx + separation.dx + CGFloat(directedWindStrength) * 0.002) * forceScale
            birds[index].velocity.dy += (cohesion.dy + alignment.dy + separation.dy) * forceScale
            birds[index].velocity.dx *= 0.986
            birds[index].velocity.dy *= 0.986
            let speed = hypot(birds[index].velocity.dx, birds[index].velocity.dy)
            if speed > 0.62 {
                birds[index].velocity.dx = birds[index].velocity.dx / speed * 0.62
                birds[index].velocity.dy = birds[index].velocity.dy / speed * 0.62
            }
            if abs(birds[index].velocity.dy) < 0.05 {
                birds[index].velocity.dy += sin(CGFloat(currentTime) * 1.7 + birds[index].bobPhase) * 0.018
            }
            birds[index].node.position.x += birds[index].velocity.dx * deltaTime * 60
            birds[index].node.position.y += birds[index].velocity.dy * deltaTime * 60
            birds[index].node.position.y += sin(CGFloat(currentTime) * 5.5 + birds[index].bobPhase) * 0.45

            if birds[index].node.position.x < -20 { birds[index].node.position.x = size.width + 20 }
            if birds[index].node.position.x > size.width + 20 { birds[index].node.position.x = -20 }
            birds[index].node.position.y = min(size.height - 80, max(size.height * 0.48, birds[index].node.position.y))
            let profile = depthProfile(at: birds[index].node.position.y, in: (size.height * 0.48)...max(size.height - 80, size.height * 0.5))
            let birdScale = birds[index].baseScale * (0.68 + profile.depth * 0.74) * visualScale.value
            birds[index].node.xScale = birdScale * (birds[index].velocity.dx >= 0 ? 1 : -1)
            birds[index].node.yScale = birdScale
            birds[index].node.alpha = 0.36 + profile.depth * 0.5
            birds[index].node.zPosition = 8 + profile.depth * 14
            birds[index].node.zRotation = max(-0.25, min(0.25, atan2(birds[index].velocity.dy, abs(birds[index].velocity.dx) + 0.01) * 0.45))
            if currentTime >= birds[index].nextFrameTime {
                birds[index].frameIndex = (birds[index].frameIndex + 1) % 8
                let prefix = birdTexturePrefix(for: birds[index].velocity)
                birds[index].node.texture = birdTexture(prefix: prefix, frame: birds[index].frameIndex)
                birds[index].nextFrameTime = currentTime + 0.075
            }
        }
    }

    private func updateLargeFlakes(at currentTime: TimeInterval) {
        let deltaTime: TimeInterval
        if lastUpdateTime > 0 {
            deltaTime = min(0.05, max(0, currentTime - lastUpdateTime))
        } else {
            deltaTime = 1.0 / 60.0
        }
        lastUpdateTime = currentTime

        spawnLargeFlakes(deltaTime: deltaTime)
        moveLargeFlakes(deltaTime: CGFloat(deltaTime))
    }

    private func spawnLargeFlakes(deltaTime: TimeInterval) {
        largeFlakeSpawnCarry += largeSnowflakeBirthRate * CGFloat(deltaTime)
        let spawnCount = min(6, Int(largeFlakeSpawnCarry))
        guard spawnCount > 0 else {
            return
        }

        largeFlakeSpawnCarry -= CGFloat(spawnCount)
        let largeTiers = Array(Self.snowflakeSizeTiers.dropFirst(Self.passiveSnowflakeTierCount))
        for _ in 0..<spawnCount {
            let tier = largeTiers.randomElement() ?? Self.snowflakeSizeTiers.last!
            spawnLargeFlake(tier: tier)
        }
    }

    private func spawnLargeFlake(tier: SnowflakeSizeTier) {
        guard fallingLargeFlakes.count < 180 else {
            return
        }

        let radius = 3 * tier.scale
        let node = SKShapeNode(circleOfRadius: radius)
        node.fillColor = snowColor(alpha: tier.alpha)
        node.strokeColor = snowColor(alpha: 0.22)
        node.lineWidth = 0.4
        node.position = CGPoint(
            x: CGFloat.random(in: 0...max(size.width, 1)),
            y: size.height + radius + 12
        )
        node.blendMode = .alpha
        largeFlakeRoot.addChild(node)

        let velocity = CGVector(
            dx: windDrift(55) + CGFloat.random(in: -18...18),
            dy: -CGFloat.random(in: 44...82) * tier.speedMultiplier
        )
        fallingLargeFlakes.append(FallingSnowflake(node: node, radius: radius, velocity: velocity))
    }

    private func moveLargeFlakes(deltaTime: CGFloat) {
        var retained: [FallingSnowflake] = []
        retained.reserveCapacity(fallingLargeFlakes.count)

        for var flake in fallingLargeFlakes {
            let previousPosition = flake.node.position
            flake.velocity.dx += windDrift(18) * deltaTime
            flake.velocity.dy -= 18 * deltaTime
            flake.node.position = CGPoint(
                x: previousPosition.x + flake.velocity.dx * deltaTime,
                y: previousPosition.y + flake.velocity.dy * deltaTime
            )

            if absorbLargeFlakeIfNeeded(flake, previousY: previousPosition.y) {
                continue
            }

            let position = flake.node.position
            if position.y < -40 || position.x < -80 || position.x > size.width + 80 {
                flake.node.removeFromParent()
            } else {
                retained.append(flake)
            }
        }

        fallingLargeFlakes = retained
    }

    private func absorbLargeFlakeIfNeeded(_ flake: FallingSnowflake, previousY: CGFloat) -> Bool {
        guard isAccumulationEnabled else {
            return false
        }

        let position = flake.node.position
        for edge in collisionEdges {
            guard
                edge.xRange.contains(position.x),
                previousY - flake.radius >= edge.y,
                position.y - flake.radius <= edge.y
            else {
                continue
            }

            let previousHeight = accumulationByEdgeKey[edge.key] ?? 2
            accumulationByEdgeKey[edge.key] = min(
                accumulationRate.maximumHeight,
                previousHeight + accumulationGrowth * 0.45
            )
            edgeByKey[edge.key] = edge
            flake.node.removeFromParent()
            trySpillAccumulation(edgeKey: edge.key)
            rebuildAccumulationNodes()
            return true
        }

        return false
    }

    private func rebuildCelestialEffects() {
        celestialRoot.removeAllChildren()
        moonPosition = nil
        guard isCelestialEffectsEnabled, size.width > 0, size.height > 0 else {
            return
        }

        if isAuroraEnabled {
            addAurora()
        }
        if isMoonEnabled {
            addMoon()
        }
        if areStarsEnabled {
            let starCount = max(12, Int((36.0 * objectAmount.multiplier).rounded()))
            for _ in 0..<starCount {
                addStar()
            }
        }
    }

    private func updateCelestialEffects(at currentTime: TimeInterval) {
        guard isCelestialEffectsEnabled else {
            return
        }

        if celestialRoot.children.isEmpty {
            rebuildCelestialEffects()
        }

        if areMeteorsEnabled, currentTime >= nextMeteorTime {
            nextMeteorTime = currentTime + TimeInterval.random(in: 5...12)
            addMeteor()
        }
    }

    private func addAurora() {
        for layer in 0..<3 {
            addAuroraLayer(offset: CGFloat(layer) * 18, alpha: 0.16 + CGFloat(layer) * 0.04)
        }
    }

    private func addAuroraLayer(offset: CGFloat, alpha: CGFloat) {
        let path = CGMutablePath()
        let baseY = size.height * 0.7 + offset
        let width = max(size.width, 1)
        let controls = (0..<8).map { index -> CGPoint in
            let progress = CGFloat(index) / 7
            return CGPoint(
                x: width * progress + progress * 24,
                y: baseY + sin(progress * .pi * 2.2 + offset * 0.04) * 28 + CGFloat.random(in: -18...18)
            )
        }
        let samples = steffenSamples(points: controls, samplesPerSegment: 12)
        guard let first = samples.first else { return }
        path.move(to: first)
        for point in samples.dropFirst() {
            path.addLine(to: CGPoint(x: point.x - (point.y - baseY) * 0.18, y: point.y))
        }

        let aurora = SKShapeNode(path: path)
        aurora.strokeColor = NSColor(calibratedRed: 0.35, green: 1.0, blue: 0.72, alpha: alpha)
        aurora.lineWidth = max(20, size.height * 0.038)
        aurora.lineCap = .round
        aurora.glowWidth = 26
        celestialRoot.addChild(aurora)
        let fade = SKAction.sequence([
            .fadeAlpha(to: 0.38, duration: 3.2),
            .fadeAlpha(to: 0.16, duration: 3.2)
        ])
        aurora.run(.repeatForever(fade))
    }

    private func steffenSamples(points: [CGPoint], samplesPerSegment: Int) -> [CGPoint] {
        guard points.count >= 2 else { return points }
        let slopes = zip(points.dropFirst(), points).map { next, current in
            (next.y - current.y) / max(1, next.x - current.x)
        }
        var tangents = Array(repeating: CGFloat.zero, count: points.count)
        tangents[0] = slopes[0]
        tangents[points.count - 1] = slopes[slopes.count - 1]
        if points.count > 2 {
            for index in 1..<(points.count - 1) {
                let left = slopes[index - 1]
                let right = slopes[index]
                tangents[index] = left * right <= 0 ? 0 : min(abs(left), abs(right)) * (left + right >= 0 ? 1 : -1)
            }
        }

        var result: [CGPoint] = []
        for index in 0..<(points.count - 1) {
            let p0 = points[index]
            let p1 = points[index + 1]
            let dx = max(1, p1.x - p0.x)
            for step in 0..<samplesPerSegment {
                let t = CGFloat(step) / CGFloat(samplesPerSegment)
                let h00 = 2 * t * t * t - 3 * t * t + 1
                let h10 = t * t * t - 2 * t * t + t
                let h01 = -2 * t * t * t + 3 * t * t
                let h11 = t * t * t - t * t
                result.append(CGPoint(
                    x: p0.x + dx * t,
                    y: h00 * p0.y + h10 * dx * tangents[index] + h01 * p1.y + h11 * dx * tangents[index + 1]
                ))
            }
        }
        result.append(points[points.count - 1])
        return result
    }

    private func addMoon() {
        let radius = 16 * visualScale.value
        let xRange = (size.width * 0.18)...(size.width * 0.86)
        let yRange = (size.height * 0.58)...(max(size.height - radius * 3, size.height * 0.6))
        let position = CGPoint(
            x: CGFloat.random(in: xRange),
            y: CGFloat.random(in: yRange)
        )
        moonPosition = position

        let halo = SKShapeNode(circleOfRadius: 34 * visualScale.value)
        halo.position = position
        halo.fillColor = NSColor(calibratedWhite: 1.0, alpha: 0.08)
        halo.strokeColor = .clear
        celestialRoot.addChild(halo)

        if let texture = XPMTextureCache.shared.texture(named: Bool.random() ? "moon1.xpm" : "moon2.xpm") {
            let moon = SKSpriteNode(texture: texture)
            moon.position = position
            moon.setScale(max(0.46, visualScale.value * 0.58))
            moon.alpha = 0.68
            celestialRoot.addChild(moon)
        } else {
            let moon = SKShapeNode(circleOfRadius: radius)
            moon.position = position
            moon.fillColor = NSColor(calibratedRed: 1.0, green: 0.96, blue: 0.78, alpha: 0.42)
            moon.strokeColor = .clear
            celestialRoot.addChild(moon)
        }
    }

    private func addStar() {
        let radius = CGFloat.random(in: 0.8...2.2) * visualScale.value
        let star = SKShapeNode(circleOfRadius: radius)
        star.position = CGPoint(
            x: CGFloat.random(in: 0...max(size.width, 1)),
            y: CGFloat.random(in: size.height * 0.45...max(size.height - 20, size.height * 0.46))
        )
        star.fillColor = NSColor(
            calibratedRed: CGFloat.random(in: 0.82...1.0),
            green: CGFloat.random(in: 0.82...1.0),
            blue: CGFloat.random(in: 0.9...1.0),
            alpha: CGFloat.random(in: 0.28...0.62)
        )
        star.strokeColor = .clear
        celestialRoot.addChild(star)
        let twinkle = SKAction.sequence([
            .fadeAlpha(to: CGFloat.random(in: 0.18...0.35), duration: TimeInterval.random(in: 0.8...1.8)),
            .fadeAlpha(to: CGFloat.random(in: 0.55...0.9), duration: TimeInterval.random(in: 0.8...1.8))
        ])
        star.run(.repeatForever(twinkle))
    }

    private func addMeteor() {
        let start = CGPoint(x: CGFloat.random(in: size.width * 0.15...size.width), y: size.height + 20)
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: -80, y: -38))
        let meteor = SKShapeNode(path: path)
        meteor.position = start
        meteor.strokeColor = NSColor.systemOrange.withAlphaComponent(0.75)
        meteor.lineWidth = 2.4
        meteor.glowWidth = 6
        celestialRoot.addChild(meteor)
        let duration = TimeInterval.random(in: 0.55...0.9)
        meteor.run(.sequence([
            .group([
                .moveBy(x: -260, y: -130, duration: duration),
                .fadeOut(withDuration: duration)
            ]),
            .removeFromParent()
        ]))
    }

    private func updateSanta(at currentTime: TimeInterval) {
        if var santa = activeSanta {
            let deltaTime: CGFloat
            if lastSantaUpdateTime > 0 {
                deltaTime = CGFloat(max(0.0, min(currentTime - lastSantaUpdateTime, 1.0 / 20.0)))
            } else {
                deltaTime = 1.0 / 60.0
            }
            lastSantaUpdateTime = currentTime
            updateActiveSanta(&santa, at: currentTime, deltaTime: deltaTime)
            activeSanta = santa.node.parent == nil ? nil : santa
        } else {
            lastSantaUpdateTime = 0
        }

        guard isSantaEnabled, currentTime >= nextSantaTime, activeSanta == nil else {
            return
        }

        spawnSanta()
    }

    private func spawnSanta() {
        let resolvedStyle = resolvedSantaStyle()
        let santa = makeSanta(style: resolvedStyle, includeRudolph: isRudolphEnabled)
        let startLeft = Bool.random()
        let startOffset = max(36, min(96, santa.plowWidth * 0.55))
        let startX = startLeft ? -startOffset : size.width + startOffset
        let endX = startLeft ? size.width + startOffset : -startOffset
        let startY = randomSantaY(moonSeeking: false)
        var endY = randomSantaY(moonSeeking: santa.moonSeeking)
        let yRange = santaYRange()
        if abs(endY - startY) < size.height * 0.18 {
            let offset = size.height * CGFloat.random(in: 0.20...0.34)
            endY = startY < (yRange.lowerBound + yRange.upperBound) * 0.5 ? startY + offset : startY - offset
            endY = min(yRange.upperBound, max(yRange.lowerBound, endY))
        }
        santa.node.position = CGPoint(x: startX, y: startY)
        let baseScale = min(1.0, visualScale.value * santaScale.multiplier)
        let farScale = santaPerspectiveScale(for: 0)
        santa.node.xScale = (startLeft ? 1 : -1) * baseScale * farScale
        santa.node.yScale = baseScale * farScale
        santa.node.alpha = 0.54
        santaRoot.addChild(santa.node)

        let speed = CGFloat.random(in: 78...112) * santaSpeed.multiplier
        activeSanta = SantaFlight(
            node: santa.node,
            sprite: santa.sprite,
            textures: santa.textures,
            direction: startLeft ? 1 : -1,
            speed: speed,
            plowWidth: santa.plowWidth,
            startX: startX,
            endX: endX,
            startY: startY,
            endY: endY,
            baseScale: baseScale,
            depthPeak: CGFloat.random(in: 0.72...1.0),
            targetY: randomSantaY(moonSeeking: santa.moonSeeking),
            verticalVelocity: CGFloat.random(in: -8...8),
            nextYChange: currentSceneTime + TimeInterval.random(in: 0.8...2.1),
            nextFrameChange: currentSceneTime,
            frameIndex: 0,
            giftTime: currentSceneTime + TimeInterval.random(in: 2.2...5.8),
            hasDroppedGift: false,
            moonSeeking: santa.moonSeeking,
            nextPlowTime: currentSceneTime
        )
        destroyAccumulation(near: santa.node.position, width: santa.plowWidth)
    }

    private func santaOverlapsMoon(_ santa: SKNode) -> Bool {
        guard let moonCenter = moonPosition else {
            return false
        }
        return hypot(santa.position.x - moonCenter.x, santa.position.y - moonCenter.y) < 64
    }

    private func updateActiveSanta(_ santa: inout SantaFlight, at currentTime: TimeInterval, deltaTime: CGFloat) {
        let progressDenominator = max(1, abs(santa.endX - santa.startX))
        let progress = min(1, max(0, abs(santa.node.position.x - santa.startX) / progressDenominator))
        let closeness = max(0, sin(progress * .pi)) * santa.depthPeak
        let perspectiveScale = santaPerspectiveScale(for: closeness)
        let speedPerspective = 0.74 + closeness * 0.34
        let windPush = CGFloat(directedWindStrength) * 18
        santa.node.position.x += (santa.direction * santa.speed * speedPerspective + windPush) * deltaTime

        let diagonalY = santa.startY + (santa.endY - santa.startY) * progress
        let depthLift = closeness * 34
        if currentTime >= santa.nextYChange {
            let yRange = santaYRange()
            let wanderingY = CGFloat.random(in: yRange.lowerBound...yRange.upperBound)
            santa.targetY = (diagonalY + depthLift) * 0.62 + wanderingY * 0.38
            santa.nextYChange = currentTime + TimeInterval.random(in: 0.6...1.9)
        }

        let naturalTargetY = (diagonalY + depthLift) * 0.72 + santa.targetY * 0.28
        let avoidance = santaAvoidanceTargetY(for: santa.node, naturalTargetY: naturalTargetY)
        let targetDelta = avoidance.y - santa.node.position.y
        santa.verticalVelocity += targetDelta * 0.026
        if avoidance.strength > 0 {
            santa.verticalVelocity += avoidance.strength * 0.9
        }
        santa.verticalVelocity *= 0.88
        santa.node.position.y += santa.verticalVelocity * deltaTime * 60
        santa.node.position.y += sin(CGFloat(currentTime) * 8.5) * 1.15 * santaScale.multiplier
        let yRange = santaYRange()
        santa.node.position.y = min(yRange.upperBound, max(yRange.lowerBound, santa.node.position.y))
        let facing = santa.direction >= 0 ? 1.0 : -1.0
        santa.node.xScale = facing * santa.baseScale * perspectiveScale
        santa.node.yScale = santa.baseScale * perspectiveScale
        santa.node.alpha = 0.5 + closeness * 0.36
        santa.node.zRotation = max(-0.08, min(0.08, santa.verticalVelocity * 0.0025))
        santa.node.zPosition = santaOverlapsMoon(santa.node) || closeness > 0.48 ? 24 : 6

        if currentTime >= santa.nextFrameChange, !santa.textures.isEmpty {
            santa.frameIndex = (santa.frameIndex + 1) % santa.textures.count
            santa.sprite?.texture = santa.textures[santa.frameIndex]
            santa.nextFrameChange = currentTime + 0.1
        }

        if !santa.hasDroppedGift, currentTime >= santa.giftTime {
            santa.hasDroppedGift = true
            dropGift(from: santa.node.position, horizontalVelocity: santa.direction * santa.speed)
        }

        if currentTime >= santa.nextPlowTime {
            destroyAccumulation(near: santa.node.position, width: santa.plowWidth)
            santa.nextPlowTime = currentTime + 0.22
        }

        let margin = max(140, santa.plowWidth * santaScale.multiplier * 1.8)
        if (santa.direction > 0 && santa.node.position.x > size.width + margin)
            || (santa.direction < 0 && santa.node.position.x < -margin) {
            santa.node.removeFromParent()
            activeSanta = nil
            nextSantaTime = currentTime + TimeInterval.random(in: 3...10)
        }
    }

    private func santaAvoidanceTargetY(for santaNode: SKNode, naturalTargetY: CGFloat) -> (y: CGFloat, strength: CGFloat) {
        guard let bear = movingPolarBear else {
            return (naturalTargetY, 0)
        }

        let santaPoint = convert(santaNode.position, from: santaRoot)
        let bearPoint = convert(bear.node.position, from: agentRoot)
        let horizontalDistance = abs(santaPoint.x - bearPoint.x)
        let verticalDistance = abs(santaPoint.y - bearPoint.y)
        let horizontalRadius = max(150, santaNode.calculateAccumulatedFrame().width * 0.75 + 80)
        let verticalRadius: CGFloat = 170
        guard horizontalDistance < horizontalRadius, verticalDistance < verticalRadius else {
            return (naturalTargetY, 0)
        }

        let yRange = santaYRange()
        let aboveBear = min(yRange.upperBound, bearPoint.y + 128)
        let belowBear = max(yRange.lowerBound, bearPoint.y - 96)
        let preferredY = aboveBear - santaPoint.y > 20 ? aboveBear : belowBear
        let horizontalStrength = 1 - horizontalDistance / horizontalRadius
        let verticalStrength = 1 - min(verticalDistance / verticalRadius, 1)
        let strength = max(0, min(1, horizontalStrength * 0.78 + verticalStrength * 0.22))
        let blendedY = naturalTargetY * (1 - strength) + preferredY * strength
        return (min(yRange.upperBound, max(yRange.lowerBound, blendedY)), strength)
    }

    private func resolvedSantaStyle() -> SantaStyle {
        if santaStyle != .random {
            return santaStyle
        }
        return [.medium, .big, .alt].randomElement() ?? .big
    }

    private func randomSantaY(moonSeeking: Bool) -> CGFloat {
        let yRange = santaYRange()
        if moonSeeking, isCelestialEffectsEnabled, let moonPosition {
            return min(yRange.upperBound, max(yRange.lowerBound, moonPosition.y + CGFloat.random(in: -54...50)))
        }
        return CGFloat.random(in: yRange.lowerBound...yRange.upperBound)
    }

    private func santaPerspectiveScale(for closeness: CGFloat) -> CGFloat {
        0.58 + min(1, max(0, closeness)) * 0.22
    }

    private func santaYRange() -> ClosedRange<CGFloat> {
        let minimumTopClearance: CGFloat = 72
        let lower = max(48, size.height * 0.36)
        let upper = min(size.height - minimumTopClearance, max(lower + 24, size.height * 0.88))
        return lower...upper
    }

    private func makeSanta(style: SantaStyle, includeRudolph: Bool) -> (node: SKNode, sprite: SKSpriteNode?, textures: [SKTexture], plowWidth: CGFloat, moonSeeking: Bool) {
        let root = SKNode()
        let baseName = santaResourceBase(style: style, includeRudolph: includeRudolph)
        let textures = (1...4).compactMap { XPMTextureCache.shared.texture(named: "\(baseName)\($0).xpm") }
        if let texture = textures.first {
            let sprite = SKSpriteNode(texture: texture)
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            let spriteScale = santaSpriteScale(for: texture.size())
            sprite.setScale(spriteScale)
            sprite.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: 1.6, duration: 0.16),
                .moveBy(x: 0, y: -1.6, duration: 0.16)
            ])))
            root.addChild(sprite)
            return (root, sprite, textures, max(texture.size().width * spriteScale, 120), Bool.random())
        }

        let profile = santaFallbackProfile(style)
        let sleighLength = CGFloat(42 + profile * 8)
        let sleigh = SKShapeNode(rect: CGRect(x: -sleighLength / 2, y: -8, width: sleighLength, height: 14), cornerRadius: 5)
        sleigh.fillColor = NSColor.systemRed.withAlphaComponent(0.86)
        sleigh.strokeColor = NSColor.white.withAlphaComponent(0.28)
        root.addChild(sleigh)

        let santa = SKShapeNode(circleOfRadius: 9)
        santa.position = CGPoint(x: -sleighLength * 0.18, y: 8)
        santa.fillColor = NSColor.white.withAlphaComponent(0.88)
        santa.strokeColor = .clear
        root.addChild(santa)

        let reindeerCount = max(0, min(4, profile))
        for index in 0..<reindeerCount {
            let deer = SKShapeNode(ellipseIn: CGRect(x: sleighLength / 2 + CGFloat(index * 20), y: -4, width: 16, height: 10))
            deer.fillColor = NSColor(calibratedRed: 0.46, green: 0.25, blue: 0.12, alpha: 0.78)
            deer.strokeColor = .clear
            deer.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: 2.4, duration: 0.12),
                .moveBy(x: 0, y: -2.4, duration: 0.12)
            ])))
            root.addChild(deer)
        }

        if reindeerCount > 0 {
            let nose = SKShapeNode(circleOfRadius: 2.4)
            nose.position = CGPoint(x: sleighLength / 2 + CGFloat(reindeerCount * 20), y: 2)
            nose.fillColor = .systemRed
            nose.strokeColor = .clear
            root.addChild(nose)
            nose.run(.repeatForever(.sequence([.fadeAlpha(to: 0.2, duration: 0.18), .fadeAlpha(to: 1, duration: 0.18)])))
        }

        return (root, nil, [], sleighLength + CGFloat(reindeerCount * 20), Bool.random())
    }

    private func santaResourceBase(style: SantaStyle, includeRudolph: Bool) -> String {
        switch (style, includeRudolph) {
        case (.regular, false): "RegularSanta"
        case (.regular, true): "RegularSantaRudolf"
        case (.medium, false): "MediumSanta"
        case (.medium, true): "MediumSantaRudolf"
        case (.big, false): "BigSanta"
        case (.big, true): "BigSantaRudolf"
        case (.alt, false): "AltSanta"
        case (.alt, true): "AltSantaRudolf"
        case (.random, _): santaResourceBase(style: resolvedSantaStyle(), includeRudolph: includeRudolph)
        }
    }

    private func santaSpriteScale(for textureSize: CGSize) -> CGFloat {
        let targetHeight = min(48, max(34, size.height * 0.052))
        guard textureSize.height > 0 else {
            return 1.2
        }
        return min(1.9, max(0.95, targetHeight / textureSize.height))
    }

    private func santaFallbackProfile(_ style: SantaStyle) -> Int {
        switch style {
        case .regular: 1
        case .medium: 2
        case .big: 4
        case .alt: 3
        case .random: Int.random(in: 0..<5)
        }
    }

    private func destroyAccumulation(near point: CGPoint, width: CGFloat = 160) {
        for (key, edge) in edgeByKey {
            let overlapsX = edge.xRange.overlaps((point.x - width * 0.5)...(point.x + width * 0.5))
            guard overlapsX, abs(edge.y - point.y) < 96, let height = accumulationByEdgeKey[key], height > 3 else {
                continue
            }
            emitDetailedSnowSpill(from: edge, height: height)
            accumulationByEdgeKey[key] = max(2, height * 0.45)
        }
        rebuildAccumulationNodes()
    }

    private func dropGift(from point: CGPoint, horizontalVelocity: CGFloat) {
        guard areGiftsEnabled else {
            return
        }
        guard point.x >= size.width * 0.3, point.x <= size.width * 0.7 || Bool.random() else {
            return
        }

        let gift = makeGiftNode(color: [.systemRed, .systemBlue, .systemGreen, .systemPurple].randomElement() ?? .systemRed)
        gift.position = point
        giftRoot.addChild(gift)
        fallingGifts.append(FallingGift(
            node: gift,
            velocity: CGVector(dx: horizontalVelocity * 0.18, dy: CGFloat.random(in: 34...72)),
            baseScale: CGFloat.random(in: 0.72...1.08)
        ))
    }

    private func updateGifts(deltaTime: CGFloat) {
        var retained: [FallingGift] = []
        retained.reserveCapacity(fallingGifts.count)

        for var gift in fallingGifts {
            gift.velocity.dy -= 180 * deltaTime
            gift.node.position.x += gift.velocity.dx * deltaTime
            gift.node.position.y += gift.velocity.dy * deltaTime
            let profile = depthProfile(at: gift.node.position.y, in: safeObjectYRange())
            let giftScale = gift.baseScale * (0.72 + profile.depth * 0.58) * visualScale.value
            gift.node.xScale = giftScale
            gift.node.yScale = giftScale
            gift.node.alpha = 0.55 + profile.depth * 0.4
            gift.node.zPosition = 11 + profile.depth * 15

            if giftLanded(gift) {
                gift.node.removeFromParent()
                gift.node.removeAllActions()
                gift.node.zRotation = 0
                seasonalRoot.addChild(gift.node)
            } else if gift.node.position.y < -40 {
                gift.node.removeFromParent()
            } else {
                gift.node.zRotation += 2.4 * deltaTime
                retained.append(gift)
            }
        }

        fallingGifts = retained
    }

    private func giftLanded(_ gift: FallingGift) -> Bool {
        if gift.node.position.y <= min(34, max(14, size.height * 0.035)) + 6 {
            return true
        }

        for edge in collisionEdges where edge.xRange.contains(gift.node.position.x) && gift.node.position.y <= edge.y + 8 {
            return true
        }
        return false
    }

    private func makeGiftNode(color: NSColor) -> SKNode {
        let gift = SKNode()
        let box = SKShapeNode(rect: CGRect(x: -7, y: -6, width: 14, height: 12), cornerRadius: 2)
        box.fillColor = color.withAlphaComponent(0.86)
        box.strokeColor = .clear
        gift.addChild(box)
        let ribbonV = SKShapeNode(rect: CGRect(x: -1, y: -6, width: 2, height: 12))
        ribbonV.fillColor = NSColor.white.withAlphaComponent(0.82)
        ribbonV.strokeColor = .clear
        gift.addChild(ribbonV)
        let ribbonH = SKShapeNode(rect: CGRect(x: -7, y: -1, width: 14, height: 2))
        ribbonH.fillColor = NSColor.white.withAlphaComponent(0.82)
        ribbonH.strokeColor = .clear
        gift.addChild(ribbonH)
        return gift
    }

    private func rebuildGroundDrift() {
        groundDriftRoot.removeAllChildren()
        guard size.width > 0 else {
            return
        }

        let baseHeight = min(34, max(14, size.height * 0.035))
        let rect = CGRect(x: -20, y: 0, width: size.width + 40, height: baseHeight)
        let base = SKShapeNode(path: groundDriftPath(in: rect, phase: 0))
        base.fillColor = NSColor.white.withAlphaComponent(0.72)
        base.strokeColor = NSColor.white.withAlphaComponent(0.32)
        base.lineWidth = 1
        base.blendMode = .alpha
        groundDriftRoot.addChild(base)

        let highlightRect = CGRect(x: 0, y: baseHeight * 0.45, width: size.width, height: baseHeight * 0.45)
        let highlight = SKShapeNode(path: groundDriftPath(in: highlightRect, phase: .pi / 6))
        highlight.fillColor = NSColor.white.withAlphaComponent(0.24)
        highlight.strokeColor = .clear
        highlight.blendMode = .alpha
        groundDriftRoot.addChild(highlight)

        addGroundClumps(baseHeight: baseHeight)
    }

    private func groundDriftPath(in rect: CGRect, phase: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        let segmentCount = max(6, Int(rect.width / 120))
        for index in stride(from: segmentCount, through: 0, by: -1) {
            let progress = CGFloat(index) / CGFloat(segmentCount)
            let x = rect.minX + rect.width * progress
            let wave = sin(progress * .pi * 4 + phase) * rect.height * 0.18
            let y = rect.minY + rect.height * 0.72 + wave
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.closeSubpath()
        return path
    }

    private func addGroundClumps(baseHeight: CGFloat) {
        let clumpCount = max(4, min(12, Int(size.width / 180)))
        for index in 0..<clumpCount {
            let progress = (CGFloat(index) + 0.45) / CGFloat(clumpCount)
            let radius = CGFloat(2 + (index % 4))
            let clump = SKShapeNode(circleOfRadius: radius)
            clump.position = CGPoint(
                x: size.width * progress,
                y: baseHeight * CGFloat(0.55 + 0.08 * CGFloat(index % 3))
            )
            clump.fillColor = NSColor.white.withAlphaComponent(0.4)
            clump.strokeColor = .clear
            clump.blendMode = .alpha
            groundDriftRoot.addChild(clump)
        }
    }

    private func rebuildSeasonalObjects() {
        seasonalRoot.removeAllChildren()
        guard size.width > 0, isSceneryEnabled else {
            return
        }

        if areTreesEnabled || isGiftTreeEnabled || isSnowmanEnabled {
            addRandomTrees()
        }
        if isHouseEnabled {
            addScenerySprite(named: "huis4.xpm", at: randomObjectPoint(yBias: 0.12), scale: 0.5)
        }
        addWinterSceneryObjects()
        if areGiftsEnabled {
            let giftCount = max(1, Int((2.0 * objectAmount.multiplier).rounded()))
            for index in 0..<giftCount {
                addGift(at: randomObjectPoint(yBias: 0.05), color: index.isMultiple(of: 2) ? .systemRed : .systemBlue)
            }
        }
        setupGroundAgentIfNeeded()
        setupMovingPolarBearIfNeeded()
        setupMovingAnimalsIfNeeded()
    }

    private func addRandomTrees() {
        var treeAssets: [(String?, CGFloat)] = []
        if areTreesEnabled {
            treeAssets.append(contentsOf: [
                (nil, 0.9),
                (nil, 0.7),
                ("snowtree.xpm", 0.42),
                ("extratree.xpm", 0.46),
                ("tannenbaum.xpm", 0.44),
                ("tree-1_100px.xpm", 0.36)
            ])
        }
        if isGiftTreeEnabled {
            treeAssets.append(("gifttree.xpm", 0.48))
        }
        if isSnowmanEnabled {
            treeAssets.append(("snowman.xpm", 0.55))
        }
        guard !treeAssets.isEmpty else {
            return
        }
        let count = max(2, Int((CGFloat(treeAssets.count) * objectAmount.multiplier).rounded()))
        for index in 0..<min(count, treeAssets.count) {
            let item = treeAssets[index]
            let point = randomObjectPoint(yBias: CGFloat.random(in: 0.02...0.18))
            if let name = item.0 {
                addScenerySprite(named: name, at: point, scale: item.1)
            } else {
                addTree(at: point, scale: item.1)
            }
        }
    }

    private func randomObjectPoint(yBias: CGFloat = 0.0) -> CGPoint {
        let xPadding = max(36, size.width * 0.06)
        let yRange = safeObjectYRange()
        let biasedLower = min(yRange.upperBound, yRange.lowerBound + (yRange.upperBound - yRange.lowerBound) * yBias)
        return CGPoint(
            x: CGFloat.random(in: xPadding...max(xPadding + 1, size.width - xPadding)),
            y: CGFloat.random(in: biasedLower...yRange.upperBound)
        )
    }

    private func safeObjectYRange() -> ClosedRange<CGFloat> {
        let lower = max(56, size.height * 0.08)
        let upper = min(size.height - 92, max(lower + 24, size.height * 0.42))
        return lower...upper
    }

    private func updateGroundAgent(at currentTime: TimeInterval) {
        guard isGroundAgentEnabled else {
            agentRoot.removeAllChildren()
            groundAgent = nil
            lastAgentUpdateTime = 0
            return
        }
        setupGroundAgentIfNeeded()
        guard let groundAgent, var target = groundAgentTarget else {
            lastAgentUpdateTime = 0
            return
        }

        let deltaTime: CGFloat
        if lastAgentUpdateTime > 0 {
            deltaTime = CGFloat(max(0, min(currentTime - lastAgentUpdateTime, 1.0 / 20.0)))
        } else {
            deltaTime = 1.0 / 60.0
        }
        lastAgentUpdateTime = currentTime

        if currentTime >= nextAgentStateChange {
            groundAgentState = [.idle, .walk, .run, .sleep].randomElement() ?? .walk
            nextAgentStateChange = currentTime + TimeInterval.random(in: 5...14)
        }

        let speedMultiplier: CGFloat
        switch groundAgentState {
        case .idle: speedMultiplier = 0
        case .walk: speedMultiplier = 1
        case .run: speedMultiplier = 2.1
        case .sleep: speedMultiplier = 0
        }

        var toTarget = CGVector(dx: target.x - groundAgent.position.x, dy: target.y - groundAgent.position.y)
        var distance = max(1, hypot(toTarget.dx, toTarget.dy))
        if distance < 24 || isNearWindowCliff(groundAgent.position) {
            target = randomObjectPoint(yBias: CGFloat.random(in: 0.05...0.5))
            groundAgentTarget = target
            toTarget = CGVector(dx: target.x - groundAgent.position.x, dy: target.y - groundAgent.position.y)
            distance = max(1, hypot(toTarget.dx, toTarget.dy))
        }
        let baseSpeed: CGFloat = 30 * speedMultiplier
        let desired = CGVector(dx: toTarget.dx / distance * baseSpeed, dy: toTarget.dy / distance * baseSpeed)
        let smoothing = min(1, deltaTime * (groundAgentState == .run ? 5.2 : 3.8))
        groundAgentVelocityVector.dx += (desired.dx - groundAgentVelocityVector.dx) * smoothing
        groundAgentVelocityVector.dy += (desired.dy - groundAgentVelocityVector.dy) * smoothing
        groundAgent.position.x += groundAgentVelocityVector.dx * deltaTime
        groundAgent.position.y += groundAgentVelocityVector.dy * deltaTime
        let bobAmplitude: CGFloat
        let bobSpeed: CGFloat
        switch groundAgentState {
        case .idle:
            bobAmplitude = 0.7
            bobSpeed = 1.8
        case .walk:
            bobAmplitude = 2.2
            bobSpeed = 6.0
        case .run:
            bobAmplitude = 4.0
            bobSpeed = 10.5
        case .sleep:
            bobAmplitude = 0.35
            bobSpeed = 1.0
        }
        let yRange = safeObjectYRange()
        groundAgent.position.x = min(size.width - 28, max(28, groundAgent.position.x))
        groundAgent.position.y = min(yRange.upperBound, max(yRange.lowerBound, groundAgent.position.y))
        let profile = depthProfile(at: groundAgent.position.y, in: yRange)
        groundAgent.position.x += groundAgentVelocityVector.dx * profile.parallaxDrift * deltaTime
        groundAgent.position.y += abs(sin(CGFloat(currentTime) * bobSpeed + groundAgentBobPhase)) * bobAmplitude * profile.motionScale
        if abs(groundAgentVelocityVector.dx) > 0.2 {
            groundAgent.xScale = (groundAgentVelocityVector.dx >= 0 ? 1 : -1) * profile.scale
        }
        groundAgent.yScale = profile.scale

        groundAgent.alpha = (groundAgentState == .sleep ? 0.5 : 0.62) + profile.depth * 0.34
        groundAgent.zPosition = 12 + profile.depth * 13
    }

    private func setupGroundAgentIfNeeded() {
        guard isGroundAgentEnabled, groundAgent == nil, size.width > 90 else {
            return
        }

        let agent = SKNode()
        agent.position = randomObjectPoint(yBias: 0.15)
        groundAgentBaseY = agent.position.y
        groundAgentTarget = randomObjectPoint(yBias: 0.35)
        groundAgentVelocityVector = CGVector(dx: CGFloat.random(in: -12...12), dy: CGFloat.random(in: -10...10))
        groundAgentBobPhase = CGFloat.random(in: 0...(.pi * 2))
        addPolarBearBody(to: agent)
        agentRoot.addChild(agent)
        groundAgent = agent
        groundAgentState = .walk
    }

    private func setupMovingPolarBearIfNeeded() {
        guard isSceneryEnabled, isPolarBearEnabled, movingPolarBear == nil, size.width > 120, size.height > 120 else {
            return
        }

        let node = SKNode()
        node.name = "movingPolarBear"
        let body = makePolarBearNode(scale: 1.18)
        body.name = "polarBearBody"
        node.addChild(body)
        let start = randomPolarBearPoint()
        let target = randomPolarBearPoint(awayFrom: start)
        node.position = start
        node.zPosition = 18
        node.xScale = target.x >= start.x ? -abs(node.xScale) : abs(node.xScale)
        agentRoot.addChild(node)
        movingPolarBear = MovingPolarBear(
            node: node,
            body: body,
            target: target,
            velocity: .zero,
            facingDirection: target.x >= start.x ? 1 : -1,
            bobPhase: CGFloat.random(in: 0...(.pi * 2)),
            stridePhase: CGFloat.random(in: 0...(.pi * 2)),
            isRunning: Bool.random(),
            nextRunDecisionTime: currentSceneTime + TimeInterval.random(in: 3...7),
            nextPawPrintTime: currentSceneTime + TimeInterval.random(in: 0.4...0.9),
            nextTargetTime: currentSceneTime + TimeInterval.random(in: 8...16)
        )
    }

    private func setupMovingAnimalsIfNeeded() {
        guard isSceneryEnabled, movingAnimals.isEmpty, size.width > 120, size.height > 120 else {
            return
        }
        if isReindeerEnabled {
            addMovingAnimal(named: "rendier.xpm", scale: 0.48)
        }
        if isMooseEnabled {
            addMovingAnimal(named: "eland.xpm", scale: 0.45)
        }
        if isWinterObjectEnabled(.penguin) {
            addMovingAnimal(node: makePenguinNode(), scale: 0.82, speed: CGFloat.random(in: 18...30), directionFlip: 1)
        }
        if isWinterObjectEnabled(.arcticFox) {
            addMovingAnimal(node: makeArcticFoxNode(), scale: 0.72, speed: CGFloat.random(in: 38...56), directionFlip: 1)
        }
        if isWinterObjectEnabled(.seal) {
            addMovingAnimal(node: makeSealNode(), scale: 0.76, speed: CGFloat.random(in: 14...24), directionFlip: 1)
        }
        if isWinterObjectEnabled(.huskySled) {
            addMovingAnimal(node: makeHuskySledNode(), scale: 0.74, speed: CGFloat.random(in: 32...48), directionFlip: 1)
        }
        if isWinterObjectEnabled(.skier) {
            addMovingAnimal(node: makeSkierNode(), scale: 0.7, speed: CGFloat.random(in: 42...62), directionFlip: 1)
        }
        if isWinterObjectEnabled(.snowboarder) {
            addMovingAnimal(node: makeSnowboarderNode(), scale: 0.7, speed: CGFloat.random(in: 40...60), directionFlip: 1)
        }
        if isWinterObjectEnabled(.wolf) {
            addMovingAnimal(node: makeWolfSilhouetteNode(), scale: 0.72, speed: CGFloat.random(in: 30...44), directionFlip: 1)
        }
        if isWinterObjectEnabled(.rollingSnowball) {
            addMovingAnimal(node: makeRollingSnowballNode(), scale: 0.86, speed: CGFloat.random(in: 24...38), directionFlip: 1)
        }
    }

    private func addMovingAnimal(named name: String, scale: CGFloat) {
        guard let texture = XPMTextureCache.shared.texture(named: name) else {
            return
        }
        let sprite = SKSpriteNode(texture: texture)
        sprite.name = "movingAnimal"
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        sprite.setScale(scale)
        sprite.alpha = 0.9
        addMovingAnimal(node: sprite, scale: scale, speed: name == "eland.xpm" ? CGFloat.random(in: 22...34) : CGFloat.random(in: 26...42), directionFlip: name == "eland.xpm" ? -1 : 1)
    }

    private func addMovingAnimal(node: SKNode, scale: CGFloat, speed: CGFloat, directionFlip: CGFloat) {
        node.name = "movingAnimal"
        let start = randomObjectPoint(yBias: CGFloat.random(in: 0.1...0.45))
        let target = randomObjectPoint(yBias: CGFloat.random(in: 0.1...0.55))
        node.position = start
        node.setScale(scale)
        node.xScale = (target.x >= start.x ? abs(node.xScale) : -abs(node.xScale)) * directionFlip
        node.alpha = 0.9
        agentRoot.addChild(node)
        movingAnimals.append(MovingAnimal(
            node: node,
            target: target,
            velocity: CGVector(dx: CGFloat.random(in: -16...16), dy: CGFloat.random(in: -12...12)),
            baseScale: scale,
            cruiseSpeed: speed,
            directionFlip: directionFlip,
            bobPhase: CGFloat.random(in: 0...(.pi * 2)),
            stridePhase: CGFloat.random(in: 0...(.pi * 2)),
            nextTargetTime: currentSceneTime + TimeInterval.random(in: 4...10)
        ))
    }

    private func updateMovingAnimals(at currentTime: TimeInterval) {
        guard isSceneryEnabled else {
            movingAnimals.removeAll()
            agentRoot.children.filter { $0.name == "movingAnimal" }.forEach { $0.removeFromParent() }
            lastMovingAnimalUpdateTime = 0
            return
        }
        setupMovingAnimalsIfNeeded()
        guard !movingAnimals.isEmpty else {
            lastMovingAnimalUpdateTime = 0
            return
        }

        let deltaTime: CGFloat
        if lastMovingAnimalUpdateTime > 0 {
            deltaTime = CGFloat(max(0, min(currentTime - lastMovingAnimalUpdateTime, 1.0 / 20.0)))
        } else {
            deltaTime = 1.0 / 60.0
        }
        lastMovingAnimalUpdateTime = currentTime

        let yRange = safeObjectYRange()
        for index in movingAnimals.indices {
            var animal = movingAnimals[index]
            var toTarget = CGVector(dx: animal.target.x - animal.node.position.x, dy: animal.target.y - animal.node.position.y)
            var distance = max(1, hypot(toTarget.dx, toTarget.dy))
            if distance < 24 || currentTime >= animal.nextTargetTime {
                animal.target = randomObjectPoint(yBias: CGFloat.random(in: 0.08...0.58))
                animal.nextTargetTime = currentTime + TimeInterval.random(in: 3.5...9.5)
                toTarget = CGVector(dx: animal.target.x - animal.node.position.x, dy: animal.target.y - animal.node.position.y)
                distance = max(1, hypot(toTarget.dx, toTarget.dy))
            }

            let profile = depthProfile(at: animal.node.position.y, in: yRange)
            let distanceEase = min(1, max(0.35, distance / 140))
            let speed = animal.cruiseSpeed * profile.speedScale * distanceEase
            let desired = CGVector(dx: toTarget.dx / distance * speed, dy: toTarget.dy / distance * speed)
            let smoothing = min(1, deltaTime * 4.4)
            animal.velocity.dx += (desired.dx - animal.velocity.dx) * smoothing
            animal.velocity.dy += (desired.dy - animal.velocity.dy) * smoothing
            let movementSpeed = hypot(animal.velocity.dx, animal.velocity.dy)
            animal.stridePhase += max(0.03, movementSpeed * 0.42 * profile.motionScale * deltaTime)
            animal.node.position.x += animal.velocity.dx * deltaTime
            animal.node.position.y += animal.velocity.dy * deltaTime
            animal.node.position.x += animal.velocity.dx * profile.parallaxDrift * deltaTime
            animal.node.position.x = min(size.width - 42, max(42, animal.node.position.x))
            animal.node.position.y = min(yRange.upperBound, max(yRange.lowerBound, animal.node.position.y))
            animal.node.position.y += abs(sin(animal.stridePhase + animal.bobPhase)) * 1.4 * profile.motionScale
            let perspectiveScale = animal.baseScale * profile.scale
            animal.node.xScale = (animal.velocity.dx >= 0 ? abs(perspectiveScale) : -abs(perspectiveScale)) * animal.directionFlip
            animal.node.yScale = perspectiveScale
            animal.node.alpha = profile.alpha
            animal.node.zPosition = 11 + profile.depth * 14
            let bodySway = sin(animal.stridePhase) * 0.018 * profile.motionScale
            animal.node.zRotation = max(-0.08, min(0.08, atan2(animal.velocity.dy, abs(animal.velocity.dx) + 0.01) * 0.14 + bodySway))
            movingAnimals[index] = animal
        }
    }

    private func updateMovingPolarBear(at currentTime: TimeInterval) {
        guard isSceneryEnabled, isPolarBearEnabled else {
            movingPolarBear?.node.removeFromParent()
            movingPolarBear = nil
            lastPolarBearUpdateTime = 0
            return
        }

        setupMovingPolarBearIfNeeded()
        guard var bear = movingPolarBear else {
            lastPolarBearUpdateTime = 0
            return
        }
        let deltaTime: CGFloat
        if lastPolarBearUpdateTime > 0 {
            deltaTime = CGFloat(max(0, min(currentTime - lastPolarBearUpdateTime, 1.0 / 20.0)))
        } else {
            deltaTime = 1.0 / 60.0
        }
        lastPolarBearUpdateTime = currentTime

        var toTarget = CGVector(
            dx: bear.target.x - bear.node.position.x,
            dy: bear.target.y - bear.node.position.y
        )
        var distance = max(1, hypot(toTarget.dx, toTarget.dy))
        if distance < 26 || currentTime >= bear.nextTargetTime {
            bear.target = randomPolarBearPoint(awayFrom: bear.node.position)
            bear.nextTargetTime = currentTime + TimeInterval.random(in: 7...15)
            toTarget = CGVector(dx: bear.target.x - bear.node.position.x, dy: bear.target.y - bear.node.position.y)
            distance = max(1, hypot(toTarget.dx, toTarget.dy))
        }

        if currentTime >= bear.nextRunDecisionTime {
            bear.isRunning = distance > 150 && Bool.random()
            bear.nextRunDecisionTime = currentTime + TimeInterval.random(in: bear.isRunning ? 2.0...4.8 : 3.0...7.0)
        }

        let yRange = polarBearYRange()
        let profile = depthProfile(at: bear.node.position.y, in: yRange)
        let speed: CGFloat = (bear.isRunning ? 62 : 31) * profile.speedScale
        if abs(toTarget.dx) > 8 {
            bear.facingDirection = toTarget.dx >= 0 ? 1 : -1
        }
        let approach = min(1, max(0.28, distance / 150))
        let desired = CGVector(dx: toTarget.dx / distance * speed * approach, dy: toTarget.dy / distance * speed * approach)
        let smoothing = min(1, deltaTime * (bear.isRunning ? 8.6 : 6.2))
        bear.velocity.dx += (desired.dx - bear.velocity.dx) * smoothing
        bear.velocity.dy += (desired.dy - bear.velocity.dy) * smoothing
        if bear.velocity.dx * bear.facingDirection < 0 {
            bear.velocity.dx *= 0.2
        }
        let movementSpeed = hypot(bear.velocity.dx, bear.velocity.dy)
        bear.stridePhase += max(0.04, movementSpeed * (bear.isRunning ? 0.72 : 0.48) * profile.motionScale * deltaTime)
        let stride = sin(bear.stridePhase)
        let secondaryStride = sin(bear.stridePhase + .pi)
        let leap = bear.isRunning ? pow(max(0, sin(bear.stridePhase)), 0.62) : abs(stride)
        bear.node.position.x += bear.velocity.dx * deltaTime
        bear.node.position.y += bear.velocity.dy * deltaTime
        bear.node.position.x += bear.velocity.dx * profile.parallaxDrift * deltaTime

        bear.node.position.x = min(size.width - 42, max(42, bear.node.position.x))
        bear.node.position.y = min(yRange.upperBound, max(yRange.lowerBound, bear.node.position.y))
        bear.body.position.y = leap * (bear.isRunning ? 7.2 : 2.3) * profile.motionScale + sin(CGFloat(currentTime) * 1.4 + bear.bobPhase) * 0.35
        bear.body.position.x = secondaryStride * (bear.isRunning ? 1.8 : 0.9)
        let perspectiveScale = profile.scale
        bear.node.xScale = bear.facingDirection >= 0 ? -perspectiveScale : perspectiveScale
        bear.node.yScale = perspectiveScale
        bear.node.alpha = profile.alpha
        bear.node.zPosition = 13 + profile.depth * 15
        bear.body.xScale = 1.0 + leap * (bear.isRunning ? 0.045 : 0.018)
        bear.body.yScale = 1.0 - leap * (bear.isRunning ? 0.04 : 0.018)
        bear.body.zRotation = max(-0.1, min(0.1, stride * (bear.isRunning ? 0.07 : 0.035) + bear.velocity.dy * 0.002))
        bear.node.zRotation = max(-0.045, min(0.045, bear.velocity.dy * 0.002 + stride * (bear.isRunning ? 0.018 : 0.0)))
        if movementSpeed > 8, currentTime >= bear.nextPawPrintTime {
            addPolarBearPawPrint(at: bear.node.position, facingRight: bear.facingDirection >= 0, phase: stride)
            bear.nextPawPrintTime = currentTime + TimeInterval.random(in: bear.isRunning ? 0.18...0.34 : 0.35...0.7)
        }
        movingPolarBear = bear
    }

    private func addPolarBearPawPrint(at point: CGPoint, facingRight: Bool, phase: CGFloat) {
        let print = SKShapeNode(ellipseIn: CGRect(x: -2.4, y: -1.2, width: 4.8, height: 2.4))
        let side = phase >= 0 ? 1.0 : -1.0
        let direction: CGFloat = facingRight ? 1 : -1
        print.position = CGPoint(x: point.x - direction * 16, y: point.y - 2 + side * 2.2)
        print.fillColor = NSColor.black.withAlphaComponent(0.16)
        print.strokeColor = .clear
        print.zPosition = 2
        agentRoot.addChild(print)
        print.run(.sequence([
            .group([
                .fadeOut(withDuration: 2.8),
                .scale(to: 1.35, duration: 2.8)
            ]),
            .removeFromParent()
        ]))
    }

    private func randomPolarBearPoint(awayFrom point: CGPoint? = nil) -> CGPoint {
        let xPadding = max(48, size.width * 0.08)
        let yRange = polarBearYRange()
        var candidate = CGPoint(
            x: CGFloat.random(in: xPadding...max(xPadding + 1, size.width - xPadding)),
            y: CGFloat.random(in: yRange.lowerBound...yRange.upperBound)
        )
        if let point, abs(candidate.x - point.x) < size.width * 0.28 {
            candidate.x = point.x < size.width * 0.5
                ? CGFloat.random(in: max(size.width * 0.55, xPadding)...max(size.width - xPadding, xPadding + 1))
                : CGFloat.random(in: xPadding...max(size.width * 0.45, xPadding + 1))
        }
        return candidate
    }

    private func polarBearYRange() -> ClosedRange<CGFloat> {
        safeObjectYRange()
    }

    private func polarBearDepth(at y: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        let span = max(1, range.upperBound - range.lowerBound)
        let normalized = (y - range.lowerBound) / span
        return max(0, min(1, 1 - normalized))
    }

    private func depthProfile(at y: CGFloat, in range: ClosedRange<CGFloat>) -> (depth: CGFloat, scale: CGFloat, speedScale: CGFloat, motionScale: CGFloat, alpha: CGFloat, parallaxDrift: CGFloat) {
        let depth = polarBearDepth(at: y, in: range)
        let easedDepth = depth * depth * (3 - 2 * depth)
        return (
            depth: easedDepth,
            scale: 0.58 + easedDepth * 0.82,
            speedScale: 0.62 + easedDepth * 0.76,
            motionScale: 0.7 + easedDepth * 0.72,
            alpha: 0.42 + easedDepth * 0.56,
            parallaxDrift: -0.08 + easedDepth * 0.18
        )
    }

    private func isNearWindowCliff(_ point: CGPoint) -> Bool {
        let probeX = point.x + (groundAgentVelocity >= 0 ? 34 : -34)
        for edge in collisionEdges {
            let verticalDistance = abs(edge.y - point.y)
            if verticalDistance < 18, edge.xRange.contains(probeX) {
                return true
            }
        }
        return false
    }

    private func addTree(at point: CGPoint, scale: CGFloat) {
        if let texture = XPMTextureCache.shared.texture(named: "tree.xpm") {
            let tree = SKSpriteNode(texture: texture)
            tree.position = point
            tree.setScale(scale * 0.52)
            seasonalRoot.addChild(tree)
            return
        }

        let tree = SKNode()
        tree.position = point
        tree.setScale(scale)

        let trunk = SKShapeNode(rect: CGRect(x: -3, y: 0, width: 6, height: 12), cornerRadius: 1)
        trunk.fillColor = NSColor.brown.withAlphaComponent(0.8)
        trunk.strokeColor = .clear
        tree.addChild(trunk)

        for level in 0..<3 {
            let width = CGFloat(38 - level * 8)
            let y = CGFloat(8 + level * 14)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: y + 24))
            path.addLine(to: CGPoint(x: -width / 2, y: y))
            path.addLine(to: CGPoint(x: width / 2, y: y))
            path.closeSubpath()
            let branch = SKShapeNode(path: path)
            branch.fillColor = NSColor.systemGreen.withAlphaComponent(0.78)
            branch.strokeColor = NSColor.systemGreen.withAlphaComponent(0.28)
            tree.addChild(branch)
        }

        let star = SKShapeNode(circleOfRadius: 3)
        star.position = CGPoint(x: 0, y: 72)
        star.fillColor = NSColor.systemYellow.withAlphaComponent(0.9)
        star.strokeColor = .clear
        tree.addChild(star)
        seasonalRoot.addChild(tree)
    }

    private func addScenerySprite(named name: String, at point: CGPoint, scale: CGFloat) {
        guard let texture = XPMTextureCache.shared.texture(named: name) else {
            return
        }
        let sprite = SKSpriteNode(texture: texture)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        sprite.position = point
        sprite.setScale(scale)
        sprite.alpha = 0.9
        sprite.zPosition = 8
        seasonalRoot.addChild(sprite)
    }

    private func addGift(at point: CGPoint, color: NSColor) {
        guard areGiftsEnabled else {
            return
        }
        let gift = SKNode()
        gift.name = "gift"
        gift.position = point
        let box = SKShapeNode(rect: CGRect(x: -7, y: 0, width: 14, height: 12), cornerRadius: 2)
        box.fillColor = color.withAlphaComponent(0.82)
        box.strokeColor = .clear
        gift.addChild(box)

        let ribbon = SKShapeNode(rect: CGRect(x: -1, y: 0, width: 2, height: 12))
        ribbon.fillColor = NSColor.white.withAlphaComponent(0.8)
        ribbon.strokeColor = .clear
        gift.addChild(ribbon)
        seasonalRoot.addChild(gift)
    }

    private func addWinterSceneryObjects() {
        let baseCount = max(6, Int((12.0 * objectAmount.multiplier).rounded()))
        let makers: [(WinterObject, (CGPoint) -> Void)] = [
            (.igloo, addIgloo),
            (.icicles, addIcicleCluster),
            (.iceFishingHole, addIceFishingHole),
            (.lampPost, addLampPost),
            (.snowMound, addSnowMound),
            (.icePatch, addIcePatch),
            (.mailbox, addMailbox),
            (.signPost, addSignPost),
            (.hotCocoa, addHotCocoa),
            (.lantern, addLantern),
            (.candyCane, addCandyCane),
            (.winterFence, addWinterFence),
            (.skiLift, addSkiLift),
            (.owl, addOwl),
            (.snowAngel, addSnowAngel),
            (.snowShovel, addSnowShovel),
            (.mittens, addMittens),
            (.scarf, addScarf),
            (.woolHat, addWoolHat),
            (.wreath, addWreath),
            (.stocking, addStocking),
            (.bells, addBellPair),
            (.christmasLights, addChristmasLights),
            (.toyTrain, addToyTrain),
            (.chimneySmoke, addChimneySmoke),
            (.snowballStack, addSnowballStack)
        ].filter { isWinterObjectEnabled($0.0) }
        let selectedMakers = makers.shuffled()
        for index in 0..<min(baseCount, selectedMakers.count) {
            selectedMakers[index].1(randomObjectPoint(yBias: CGFloat.random(in: 0.02...0.32)))
        }
        if isWinterObjectEnabled(.frostCrystals) {
            addFrostCorner()
        }
    }

    private func isWinterObjectEnabled(_ object: WinterObject) -> Bool {
        winterObjectOptions[object.rawValue] ?? true
    }

    private func addIgloo(at point: CGPoint) {
        let node = SKNode()
        node.position = point
        node.setScale(visualScale.value * 0.78)
        let domePath = CGMutablePath()
        domePath.move(to: CGPoint(x: -28, y: 0))
        domePath.addQuadCurve(to: CGPoint(x: 28, y: 0), control: CGPoint(x: 0, y: 36))
        domePath.closeSubpath()
        let dome = SKShapeNode(path: domePath)
        dome.fillColor = NSColor(calibratedRed: 0.86, green: 0.94, blue: 1.0, alpha: 0.78)
        dome.strokeColor = NSColor.white.withAlphaComponent(0.55)
        dome.lineWidth = 1
        node.addChild(dome)
        for y in stride(from: CGFloat(8), through: 24, by: 8) {
            let line = SKShapeNode(rect: CGRect(x: -24 + y * 0.25, y: y, width: 48 - y * 0.5, height: 1), cornerRadius: 0.5)
            line.fillColor = NSColor.white.withAlphaComponent(0.38)
            line.strokeColor = .clear
            node.addChild(line)
        }
        let door = SKShapeNode(ellipseIn: CGRect(x: -9, y: -1, width: 18, height: 17))
        door.fillColor = NSColor(calibratedWhite: 0.18, alpha: 0.48)
        door.strokeColor = NSColor.white.withAlphaComponent(0.25)
        node.addChild(door)
        seasonalRoot.addChild(node)
    }

    private func addIcicleCluster(at point: CGPoint) {
        let node = SKNode()
        node.position = CGPoint(x: point.x, y: min(size.height - 24, point.y + CGFloat.random(in: 80...180)))
        node.setScale(visualScale.value)
        for index in 0..<5 {
            let length = CGFloat.random(in: 14...34)
            let x = CGFloat(index - 2) * CGFloat.random(in: 5...9)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x - 3, y: 0))
            path.addLine(to: CGPoint(x: x + 3, y: 0))
            path.addLine(to: CGPoint(x: x, y: -length))
            path.closeSubpath()
            let icicle = SKShapeNode(path: path)
            icicle.fillColor = NSColor(calibratedRed: 0.82, green: 0.93, blue: 1.0, alpha: 0.66)
            icicle.strokeColor = NSColor.white.withAlphaComponent(0.5)
            node.addChild(icicle)
        }
        seasonalRoot.addChild(node)
    }

    private func addIceFishingHole(at point: CGPoint) {
        let node = SKNode()
        node.position = point
        node.setScale(visualScale.value)
        let hole = SKShapeNode(ellipseIn: CGRect(x: -18, y: -4, width: 36, height: 13))
        hole.fillColor = NSColor(calibratedRed: 0.05, green: 0.22, blue: 0.32, alpha: 0.62)
        hole.strokeColor = NSColor.white.withAlphaComponent(0.34)
        node.addChild(hole)
        let rod = SKShapeNode(rect: CGRect(x: 10, y: 2, width: 2, height: 34), cornerRadius: 1)
        rod.fillColor = NSColor.brown.withAlphaComponent(0.72)
        rod.strokeColor = .clear
        rod.zRotation = -0.48
        node.addChild(rod)
        let line = SKShapeNode(rect: CGRect(x: 15, y: 0, width: 1, height: 24))
        line.fillColor = NSColor.white.withAlphaComponent(0.42)
        line.strokeColor = .clear
        node.addChild(line)
        seasonalRoot.addChild(node)
    }

    private func addLampPost(at point: CGPoint) {
        let node = SKNode()
        node.position = point
        node.setScale(visualScale.value * 0.85)
        let post = SKShapeNode(rect: CGRect(x: -2, y: 0, width: 4, height: 48), cornerRadius: 1)
        post.fillColor = NSColor(calibratedWhite: 0.16, alpha: 0.72)
        post.strokeColor = .clear
        node.addChild(post)
        let glow = SKShapeNode(circleOfRadius: 18)
        glow.position = CGPoint(x: 0, y: 50)
        glow.fillColor = NSColor.systemYellow.withAlphaComponent(0.14)
        glow.strokeColor = .clear
        node.addChild(glow)
        let lamp = SKShapeNode(circleOfRadius: 6)
        lamp.position = glow.position
        lamp.fillColor = NSColor.systemYellow.withAlphaComponent(0.76)
        lamp.strokeColor = NSColor.white.withAlphaComponent(0.4)
        node.addChild(lamp)
        seasonalRoot.addChild(node)
    }

    private func addSnowMound(at point: CGPoint) {
        let mound = SKShapeNode(ellipseIn: CGRect(x: -28, y: -2, width: 56, height: 16))
        mound.position = point
        mound.fillColor = NSColor.white.withAlphaComponent(0.64)
        mound.strokeColor = NSColor.white.withAlphaComponent(0.32)
        mound.setScale(visualScale.value)
        seasonalRoot.addChild(mound)
    }

    private func addIcePatch(at point: CGPoint) {
        let patch = SKShapeNode(ellipseIn: CGRect(x: -32, y: -3, width: 64, height: 13))
        patch.position = point
        patch.fillColor = NSColor(calibratedRed: 0.54, green: 0.83, blue: 1.0, alpha: 0.24)
        patch.strokeColor = NSColor.white.withAlphaComponent(0.28)
        patch.setScale(visualScale.value)
        seasonalRoot.addChild(patch)
    }

    private func addMailbox(at point: CGPoint) {
        let node = SKNode()
        node.position = point
        node.setScale(visualScale.value * 0.75)
        let post = SKShapeNode(rect: CGRect(x: -2, y: 0, width: 4, height: 18), cornerRadius: 1)
        post.fillColor = NSColor.brown.withAlphaComponent(0.65)
        post.strokeColor = .clear
        node.addChild(post)
        let box = SKShapeNode(rect: CGRect(x: -14, y: 18, width: 28, height: 14), cornerRadius: 5)
        box.fillColor = NSColor.systemRed.withAlphaComponent(0.72)
        box.strokeColor = NSColor.white.withAlphaComponent(0.32)
        node.addChild(box)
        seasonalRoot.addChild(node)
    }

    private func addSignPost(at point: CGPoint) {
        let node = SKNode()
        node.position = point
        node.setScale(visualScale.value * 0.78)
        let post = SKShapeNode(rect: CGRect(x: -2, y: 0, width: 4, height: 38), cornerRadius: 1)
        post.fillColor = NSColor.brown.withAlphaComponent(0.72)
        post.strokeColor = .clear
        node.addChild(post)
        let sign = SKShapeNode(rect: CGRect(x: -24, y: 28, width: 48, height: 14), cornerRadius: 2)
        sign.fillColor = NSColor(calibratedRed: 0.58, green: 0.28, blue: 0.12, alpha: 0.74)
        sign.strokeColor = NSColor.white.withAlphaComponent(0.22)
        node.addChild(sign)
        seasonalRoot.addChild(node)
    }

    private func addHotCocoa(at point: CGPoint) {
        let node = SKNode()
        node.position = point
        node.setScale(visualScale.value * 0.65)
        let mug = SKShapeNode(rect: CGRect(x: -8, y: 0, width: 16, height: 14), cornerRadius: 3)
        mug.fillColor = NSColor.systemRed.withAlphaComponent(0.78)
        mug.strokeColor = NSColor.white.withAlphaComponent(0.24)
        node.addChild(mug)
        let handle = SKShapeNode(ellipseIn: CGRect(x: 6, y: 3, width: 10, height: 8))
        handle.fillColor = .clear
        handle.strokeColor = NSColor.systemRed.withAlphaComponent(0.68)
        handle.lineWidth = 2
        node.addChild(handle)
        for x in [-4, 0, 4] {
            let steam = SKShapeNode(rect: CGRect(x: CGFloat(x), y: 17, width: 1, height: 10), cornerRadius: 0.5)
            steam.fillColor = NSColor.white.withAlphaComponent(0.28)
            steam.strokeColor = .clear
            node.addChild(steam)
        }
        seasonalRoot.addChild(node)
    }

    private func addLantern(at point: CGPoint) {
        let node = SKNode()
        node.position = point
        node.setScale(visualScale.value * 0.7)
        let frame = SKShapeNode(rect: CGRect(x: -8, y: 0, width: 16, height: 22), cornerRadius: 3)
        frame.fillColor = NSColor(calibratedWhite: 0.12, alpha: 0.54)
        frame.strokeColor = NSColor.white.withAlphaComponent(0.18)
        node.addChild(frame)
        let light = SKShapeNode(circleOfRadius: 7)
        light.position = CGPoint(x: 0, y: 10)
        light.fillColor = NSColor.systemYellow.withAlphaComponent(0.58)
        light.strokeColor = .clear
        node.addChild(light)
        seasonalRoot.addChild(node)
    }

    private func addCandyCane(at point: CGPoint) {
        let node = SKNode()
        node.position = point
        node.setScale(visualScale.value * 0.72)
        let cane = SKShapeNode(rect: CGRect(x: -2, y: 0, width: 4, height: 34), cornerRadius: 2)
        cane.fillColor = NSColor.white.withAlphaComponent(0.82)
        cane.strokeColor = NSColor.systemRed.withAlphaComponent(0.6)
        cane.lineWidth = 1.4
        node.addChild(cane)
        for y in stride(from: CGFloat(4), through: 28, by: 8) {
            let stripe = SKShapeNode(rect: CGRect(x: -3, y: y, width: 6, height: 3), cornerRadius: 1)
            stripe.fillColor = NSColor.systemRed.withAlphaComponent(0.72)
            stripe.strokeColor = .clear
            node.addChild(stripe)
        }
        seasonalRoot.addChild(node)
    }

    private func addWinterFence(at point: CGPoint) {
        let node = SKNode()
        node.position = point
        node.setScale(visualScale.value * 0.8)
        for x in stride(from: CGFloat(-30), through: 30, by: 15) {
            let post = SKShapeNode(rect: CGRect(x: x - 2, y: 0, width: 4, height: 22), cornerRadius: 1)
            post.fillColor = NSColor.brown.withAlphaComponent(0.52)
            post.strokeColor = .clear
            node.addChild(post)
        }
        for y in [7, 16] as [CGFloat] {
            let rail = SKShapeNode(rect: CGRect(x: -34, y: y, width: 68, height: 3), cornerRadius: 1)
            rail.fillColor = NSColor.brown.withAlphaComponent(0.44)
            rail.strokeColor = .clear
            node.addChild(rail)
        }
        seasonalRoot.addChild(node)
    }

    private func addSkiLift(at point: CGPoint) {
        let node = SKNode()
        node.position = CGPoint(x: point.x, y: min(size.height - 90, max(point.y + 70, size.height * 0.36)))
        node.setScale(visualScale.value * 0.78)
        let cable = SKShapeNode(rect: CGRect(x: -42, y: 30, width: 84, height: 1), cornerRadius: 0.5)
        cable.fillColor = NSColor.white.withAlphaComponent(0.32)
        cable.strokeColor = .clear
        node.addChild(cable)
        let hanger = SKShapeNode(rect: CGRect(x: -1, y: 10, width: 2, height: 20), cornerRadius: 0.5)
        hanger.fillColor = NSColor.white.withAlphaComponent(0.45)
        hanger.strokeColor = .clear
        node.addChild(hanger)
        let chair = SKShapeNode(rect: CGRect(x: -14, y: 4, width: 28, height: 6), cornerRadius: 2)
        chair.fillColor = NSColor.systemBlue.withAlphaComponent(0.52)
        chair.strokeColor = NSColor.white.withAlphaComponent(0.22)
        node.addChild(chair)
        seasonalRoot.addChild(node)
    }

    private func addOwl(at point: CGPoint) {
        let node = SKNode()
        node.position = CGPoint(x: point.x, y: point.y + 22)
        node.setScale(visualScale.value * 0.68)
        let body = SKShapeNode(ellipseIn: CGRect(x: -10, y: 0, width: 20, height: 25))
        body.fillColor = NSColor(calibratedWhite: 0.52, alpha: 0.72)
        body.strokeColor = NSColor.white.withAlphaComponent(0.22)
        node.addChild(body)
        for x in [-4, 4] as [CGFloat] {
            let eye = SKShapeNode(circleOfRadius: 2.5)
            eye.position = CGPoint(x: x, y: 17)
            eye.fillColor = NSColor.systemYellow.withAlphaComponent(0.78)
            eye.strokeColor = .clear
            node.addChild(eye)
        }
        let perch = SKShapeNode(rect: CGRect(x: -16, y: -1, width: 32, height: 3), cornerRadius: 1)
        perch.fillColor = NSColor.brown.withAlphaComponent(0.5)
        perch.strokeColor = .clear
        node.addChild(perch)
        seasonalRoot.addChild(node)
    }

    private func addSnowAngel(at point: CGPoint) {
        let node = SKNode()
        node.position = point
        node.setScale(visualScale.value * 0.8)
        let body = SKShapeNode(ellipseIn: CGRect(x: -5, y: -2, width: 10, height: 22))
        body.fillColor = NSColor.white.withAlphaComponent(0.34)
        body.strokeColor = NSColor.white.withAlphaComponent(0.28)
        node.addChild(body)
        for x in [-16, 8] as [CGFloat] {
            let wing = SKShapeNode(ellipseIn: CGRect(x: x, y: 2, width: 16, height: 22))
            wing.fillColor = NSColor.white.withAlphaComponent(0.24)
            wing.strokeColor = NSColor.white.withAlphaComponent(0.18)
            node.addChild(wing)
        }
        seasonalRoot.addChild(node)
    }

    private func addSnowShovel(at point: CGPoint) {
        let node = SKNode()
        node.position = point
        node.setScale(visualScale.value * 0.75)
        let handle = SKShapeNode(rect: CGRect(x: -1, y: 4, width: 2, height: 40), cornerRadius: 1)
        handle.fillColor = NSColor.brown.withAlphaComponent(0.68)
        handle.strokeColor = .clear
        handle.zRotation = -0.42
        node.addChild(handle)
        let blade = SKShapeNode(rect: CGRect(x: -9, y: 0, width: 18, height: 10), cornerRadius: 3)
        blade.fillColor = NSColor.systemBlue.withAlphaComponent(0.55)
        blade.strokeColor = NSColor.white.withAlphaComponent(0.25)
        node.addChild(blade)
        seasonalRoot.addChild(node)
    }

    private func addMittens(at point: CGPoint) {
        let node = SKNode()
        node.position = point
        node.setScale(visualScale.value * 0.62)
        for x in [-7, 7] as [CGFloat] {
            let mitten = SKShapeNode(ellipseIn: CGRect(x: x - 6, y: 0, width: 12, height: 16))
            mitten.fillColor = NSColor.systemRed.withAlphaComponent(0.72)
            mitten.strokeColor = NSColor.white.withAlphaComponent(0.2)
            node.addChild(mitten)
        }
        seasonalRoot.addChild(node)
    }

    private func addScarf(at point: CGPoint) {
        let node = SKNode()
        node.position = point
        node.setScale(visualScale.value * 0.7)
        let wrap = SKShapeNode(rect: CGRect(x: -18, y: 8, width: 36, height: 6), cornerRadius: 3)
        wrap.fillColor = NSColor.systemPurple.withAlphaComponent(0.7)
        wrap.strokeColor = .clear
        node.addChild(wrap)
        let tail = SKShapeNode(rect: CGRect(x: 9, y: -8, width: 7, height: 20), cornerRadius: 2)
        tail.fillColor = NSColor.systemPurple.withAlphaComponent(0.64)
        tail.strokeColor = .clear
        node.addChild(tail)
        seasonalRoot.addChild(node)
    }

    private func addWoolHat(at point: CGPoint) {
        let node = SKNode()
        node.position = point
        node.setScale(visualScale.value * 0.72)
        let cap = SKShapeNode(ellipseIn: CGRect(x: -12, y: 0, width: 24, height: 15))
        cap.fillColor = NSColor.systemBlue.withAlphaComponent(0.72)
        cap.strokeColor = NSColor.white.withAlphaComponent(0.2)
        node.addChild(cap)
        let pom = SKShapeNode(circleOfRadius: 4)
        pom.position = CGPoint(x: 0, y: 16)
        pom.fillColor = NSColor.white.withAlphaComponent(0.82)
        pom.strokeColor = .clear
        node.addChild(pom)
        seasonalRoot.addChild(node)
    }

    private func addWreath(at point: CGPoint) {
        let wreath = SKShapeNode(ellipseIn: CGRect(x: -13, y: 0, width: 26, height: 26))
        wreath.position = point
        wreath.fillColor = .clear
        wreath.strokeColor = NSColor.systemGreen.withAlphaComponent(0.72)
        wreath.lineWidth = 5
        wreath.setScale(visualScale.value * 0.68)
        seasonalRoot.addChild(wreath)
        let berry = SKShapeNode(circleOfRadius: 3)
        berry.position = CGPoint(x: point.x + 7, y: point.y + 8)
        berry.fillColor = NSColor.systemRed.withAlphaComponent(0.78)
        berry.strokeColor = .clear
        seasonalRoot.addChild(berry)
    }

    private func addStocking(at point: CGPoint) {
        let node = SKNode()
        node.position = point
        node.setScale(visualScale.value * 0.65)
        let leg = SKShapeNode(rect: CGRect(x: -7, y: 8, width: 12, height: 20), cornerRadius: 3)
        leg.fillColor = NSColor.systemRed.withAlphaComponent(0.72)
        leg.strokeColor = .clear
        node.addChild(leg)
        let foot = SKShapeNode(rect: CGRect(x: -7, y: 0, width: 20, height: 10), cornerRadius: 4)
        foot.fillColor = NSColor.systemRed.withAlphaComponent(0.72)
        foot.strokeColor = .clear
        node.addChild(foot)
        seasonalRoot.addChild(node)
    }

    private func addBellPair(at point: CGPoint) {
        let node = SKNode()
        node.position = point
        node.setScale(visualScale.value * 0.62)
        for x in [-6, 6] as [CGFloat] {
            let bell = SKShapeNode(ellipseIn: CGRect(x: x - 5, y: 0, width: 10, height: 12))
            bell.fillColor = NSColor.systemYellow.withAlphaComponent(0.72)
            bell.strokeColor = NSColor.white.withAlphaComponent(0.2)
            node.addChild(bell)
        }
        seasonalRoot.addChild(node)
    }

    private func addChristmasLights(at point: CGPoint) {
        let node = SKNode()
        node.position = CGPoint(x: point.x, y: point.y + 28)
        node.setScale(visualScale.value * 0.75)
        let cord = SKShapeNode(rect: CGRect(x: -34, y: 8, width: 68, height: 1), cornerRadius: 0.5)
        cord.fillColor = NSColor(calibratedWhite: 0.12, alpha: 0.38)
        cord.strokeColor = .clear
        node.addChild(cord)
        let colors: [NSColor] = [.systemRed, .systemGreen, .systemBlue, .systemYellow]
        for index in 0..<6 {
            let bulb = SKShapeNode(circleOfRadius: 3)
            bulb.position = CGPoint(x: -28 + CGFloat(index) * 11, y: 5)
            bulb.fillColor = colors[index % colors.count].withAlphaComponent(0.78)
            bulb.strokeColor = .clear
            node.addChild(bulb)
        }
        seasonalRoot.addChild(node)
    }

    private func addToyTrain(at point: CGPoint) {
        let node = SKNode()
        node.position = point
        node.setScale(visualScale.value * 0.58)
        for index in 0..<4 {
            let car = SKShapeNode(rect: CGRect(x: CGFloat(index * 22), y: 6, width: 18, height: 12), cornerRadius: 3)
            car.fillColor = [NSColor.systemRed, .systemBlue, .systemGreen, .systemOrange][index].withAlphaComponent(0.72)
            car.strokeColor = NSColor.white.withAlphaComponent(0.2)
            node.addChild(car)
            let wheel = SKShapeNode(circleOfRadius: 2.5)
            wheel.position = CGPoint(x: CGFloat(index * 22 + 9), y: 4)
            wheel.fillColor = NSColor.black.withAlphaComponent(0.42)
            wheel.strokeColor = .clear
            node.addChild(wheel)
        }
        seasonalRoot.addChild(node)
    }

    private func addChimneySmoke(at point: CGPoint) {
        let node = SKNode()
        node.position = CGPoint(x: point.x, y: point.y + 28)
        node.setScale(visualScale.value * 0.7)
        let chimney = SKShapeNode(rect: CGRect(x: -5, y: 0, width: 10, height: 18), cornerRadius: 1)
        chimney.fillColor = NSColor.brown.withAlphaComponent(0.56)
        chimney.strokeColor = .clear
        node.addChild(chimney)
        for index in 0..<3 {
            let puff = SKShapeNode(circleOfRadius: CGFloat(5 + index * 2))
            puff.position = CGPoint(x: CGFloat(index * 6 - 5), y: CGFloat(24 + index * 12))
            puff.fillColor = NSColor.white.withAlphaComponent(0.16)
            puff.strokeColor = .clear
            node.addChild(puff)
        }
        seasonalRoot.addChild(node)
    }

    private func addSnowballStack(at point: CGPoint) {
        let node = SKNode()
        node.position = point
        node.setScale(visualScale.value * 0.72)
        for index in 0..<3 {
            let ball = SKShapeNode(circleOfRadius: CGFloat(7 - index))
            ball.position = CGPoint(x: CGFloat(index * 10), y: CGFloat(index * 4))
            ball.fillColor = NSColor.white.withAlphaComponent(0.74)
            ball.strokeColor = NSColor.white.withAlphaComponent(0.28)
            node.addChild(ball)
        }
        seasonalRoot.addChild(node)
    }

    private func addFrostCorner() {
        let node = SKNode()
        node.position = CGPoint(x: size.width - 44, y: size.height - 56)
        node.alpha = 0.42
        for index in 0..<6 {
            let ray = SKShapeNode(rect: CGRect(x: 0, y: 0, width: CGFloat.random(in: 14...32), height: 1), cornerRadius: 0.5)
            ray.fillColor = NSColor(calibratedRed: 0.82, green: 0.94, blue: 1.0, alpha: 0.42)
            ray.strokeColor = .clear
            ray.zRotation = CGFloat(index) * .pi / 6
            node.addChild(ray)
        }
        seasonalRoot.addChild(node)
    }

    private func makePenguinNode() -> SKNode {
        let node = SKNode()
        let body = SKShapeNode(ellipseIn: CGRect(x: -10, y: 0, width: 20, height: 28))
        body.fillColor = NSColor.black.withAlphaComponent(0.82)
        body.strokeColor = .clear
        node.addChild(body)
        let belly = SKShapeNode(ellipseIn: CGRect(x: -6, y: 4, width: 12, height: 18))
        belly.fillColor = NSColor.white.withAlphaComponent(0.86)
        belly.strokeColor = .clear
        node.addChild(belly)
        let beak = SKShapeNode(rect: CGRect(x: 7, y: 18, width: 8, height: 4), cornerRadius: 1)
        beak.fillColor = NSColor.systemOrange.withAlphaComponent(0.86)
        beak.strokeColor = .clear
        node.addChild(beak)
        return node
    }

    private func makeArcticFoxNode() -> SKNode {
        let node = SKNode()
        let body = SKShapeNode(ellipseIn: CGRect(x: -17, y: 4, width: 34, height: 13))
        body.fillColor = NSColor.white.withAlphaComponent(0.82)
        body.strokeColor = NSColor.white.withAlphaComponent(0.28)
        node.addChild(body)
        let head = SKShapeNode(ellipseIn: CGRect(x: 11, y: 10, width: 13, height: 11))
        head.fillColor = NSColor.white.withAlphaComponent(0.84)
        head.strokeColor = .clear
        node.addChild(head)
        let tail = SKShapeNode(ellipseIn: CGRect(x: -28, y: 8, width: 15, height: 8))
        tail.fillColor = NSColor.white.withAlphaComponent(0.72)
        tail.strokeColor = .clear
        node.addChild(tail)
        return node
    }

    private func makeSealNode() -> SKNode {
        let node = SKNode()
        let body = SKShapeNode(ellipseIn: CGRect(x: -20, y: 0, width: 40, height: 16))
        body.fillColor = NSColor(calibratedWhite: 0.72, alpha: 0.72)
        body.strokeColor = NSColor.white.withAlphaComponent(0.25)
        node.addChild(body)
        let head = SKShapeNode(circleOfRadius: 8)
        head.position = CGPoint(x: 18, y: 10)
        head.fillColor = NSColor(calibratedWhite: 0.76, alpha: 0.78)
        head.strokeColor = .clear
        node.addChild(head)
        return node
    }

    private func makeHuskySledNode() -> SKNode {
        let node = SKNode()
        for index in 0..<2 {
            let dog = SKShapeNode(ellipseIn: CGRect(x: CGFloat(index * 18), y: 5, width: 16, height: 9))
            dog.fillColor = index == 0 ? NSColor.white.withAlphaComponent(0.78) : NSColor.gray.withAlphaComponent(0.72)
            dog.strokeColor = .clear
            node.addChild(dog)
        }
        let sled = SKShapeNode(rect: CGRect(x: -28, y: 0, width: 24, height: 6), cornerRadius: 2)
        sled.fillColor = NSColor.brown.withAlphaComponent(0.68)
        sled.strokeColor = NSColor.white.withAlphaComponent(0.2)
        node.addChild(sled)
        return node
    }

    private func makeSkierNode() -> SKNode {
        let node = SKNode()
        let body = SKShapeNode(rect: CGRect(x: -4, y: 10, width: 8, height: 15), cornerRadius: 3)
        body.fillColor = NSColor.systemBlue.withAlphaComponent(0.76)
        body.strokeColor = .clear
        node.addChild(body)
        let head = SKShapeNode(circleOfRadius: 4)
        head.position = CGPoint(x: 0, y: 28)
        head.fillColor = NSColor.white.withAlphaComponent(0.82)
        head.strokeColor = .clear
        node.addChild(head)
        for y in [0, 4] as [CGFloat] {
            let ski = SKShapeNode(rect: CGRect(x: -16, y: y, width: 34, height: 2), cornerRadius: 1)
            ski.fillColor = NSColor.white.withAlphaComponent(0.74)
            ski.strokeColor = .clear
            ski.zRotation = -0.12
            node.addChild(ski)
        }
        return node
    }

    private func makeSnowboarderNode() -> SKNode {
        let node = SKNode()
        let board = SKShapeNode(rect: CGRect(x: -18, y: 0, width: 36, height: 4), cornerRadius: 2)
        board.fillColor = NSColor.systemPurple.withAlphaComponent(0.72)
        board.strokeColor = .clear
        node.addChild(board)
        let body = SKShapeNode(rect: CGRect(x: -5, y: 6, width: 10, height: 16), cornerRadius: 4)
        body.fillColor = NSColor.systemGreen.withAlphaComponent(0.76)
        body.strokeColor = .clear
        body.zRotation = -0.18
        node.addChild(body)
        let head = SKShapeNode(circleOfRadius: 4)
        head.position = CGPoint(x: 2, y: 25)
        head.fillColor = NSColor.white.withAlphaComponent(0.82)
        head.strokeColor = .clear
        node.addChild(head)
        return node
    }

    private func makeWolfSilhouetteNode() -> SKNode {
        let node = SKNode()
        let body = SKShapeNode(ellipseIn: CGRect(x: -20, y: 6, width: 38, height: 12))
        body.fillColor = NSColor.black.withAlphaComponent(0.46)
        body.strokeColor = .clear
        node.addChild(body)
        let head = SKShapeNode(ellipseIn: CGRect(x: 14, y: 13, width: 13, height: 10))
        head.fillColor = NSColor.black.withAlphaComponent(0.48)
        head.strokeColor = .clear
        node.addChild(head)
        let tail = SKShapeNode(rect: CGRect(x: -28, y: 12, width: 14, height: 4), cornerRadius: 2)
        tail.fillColor = NSColor.black.withAlphaComponent(0.42)
        tail.strokeColor = .clear
        tail.zRotation = 0.45
        node.addChild(tail)
        return node
    }

    private func makeRollingSnowballNode() -> SKNode {
        let node = SKNode()
        let ball = SKShapeNode(circleOfRadius: 12)
        ball.fillColor = NSColor.white.withAlphaComponent(0.76)
        ball.strokeColor = NSColor.white.withAlphaComponent(0.34)
        ball.lineWidth = 1
        node.addChild(ball)
        let swirl = SKShapeNode(rect: CGRect(x: -7, y: -1, width: 14, height: 2), cornerRadius: 1)
        swirl.fillColor = NSColor(calibratedWhite: 0.78, alpha: 0.35)
        swirl.strokeColor = .clear
        node.addChild(swirl)
        node.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 1.4)))
        return node
    }

    private func makePolarBearNode(scale: CGFloat) -> SKNode {
        if let texture = XPMTextureCache.shared.texture(named: "polarbear.xpm") {
            let bear = SKSpriteNode(texture: texture)
            bear.name = "polarBear"
            bear.anchorPoint = CGPoint(x: 0.5, y: 0)
            bear.setScale(scale * 1.15)
            bear.zPosition = 9
            let shadow = SKShapeNode(ellipseIn: CGRect(x: -24, y: -2, width: 48, height: 9))
            shadow.fillColor = NSColor.black.withAlphaComponent(0.22)
            shadow.strokeColor = .clear
            shadow.zPosition = -1
            bear.addChild(shadow)
            return bear
        }

        let bear = SKNode()
        bear.name = "polarBear"
        bear.setScale(scale)
        bear.zPosition = 9
        addPolarBearBody(to: bear)
        return bear
    }

    private func addPolarBear(at point: CGPoint, scale: CGFloat) {
        let bear = makePolarBearNode(scale: scale)
        bear.position = point
        seasonalRoot.addChild(bear)
    }

    private func addPolarBearBody(to bear: SKNode) {
        let body = SKShapeNode(ellipseIn: CGRect(x: -18, y: 0, width: 36, height: 18))
        body.fillColor = NSColor.white.withAlphaComponent(0.78)
        body.strokeColor = NSColor.white.withAlphaComponent(0.3)
        bear.addChild(body)

        let head = SKShapeNode(ellipseIn: CGRect(x: 12, y: 9, width: 16, height: 13))
        head.fillColor = NSColor.white.withAlphaComponent(0.82)
        head.strokeColor = .clear
        bear.addChild(head)

        for x in [-10, 8] {
            let leg = SKShapeNode(rect: CGRect(x: CGFloat(x), y: -3, width: 5, height: 8), cornerRadius: 2)
            leg.fillColor = NSColor.white.withAlphaComponent(0.72)
            leg.strokeColor = .clear
            bear.addChild(leg)
        }

        let nose = SKShapeNode(circleOfRadius: 1.4)
        nose.position = CGPoint(x: 27, y: 15)
        nose.fillColor = NSColor.black.withAlphaComponent(0.55)
        nose.strokeColor = .clear
        bear.addChild(nose)
    }

    private func updateAccumulation(for edges: [SnowCollisionEdge]) {
        let activeKeys = Set(edges.map(\.key))
        let removedKeys = Set(accumulationByEdgeKey.keys).subtracting(activeKeys)
        for key in removedKeys {
            if let edge = edgeByKey[key], let height = accumulationByEdgeKey[key], height > 2 {
                emitTriggeredSpill(from: edge, height: height)
            }
            lastSpillByEdgeKey.removeValue(forKey: key)
            plantedTreeKeys.remove(key)
        }

        accumulationByEdgeKey = accumulationByEdgeKey.filter { activeKeys.contains($0.key) }
        edgeByKey = edgeByKey.filter { activeKeys.contains($0.key) }

        for edge in edges {
            let previousHeight = accumulationByEdgeKey[edge.key] ?? 2
            if
                let previousEdge = edgeByKey[edge.key],
                previousEdge != edge,
                previousHeight >= accumulationRate.maximumHeight * 0.55
            {
                emitEdgeLeak(from: previousEdge, height: previousHeight, intensity: 0.55)
            }
            accumulationByEdgeKey[edge.key] = min(accumulationRate.maximumHeight, previousHeight + accumulationGrowth)
            edgeByKey[edge.key] = edge
            spawnTreeIfNeeded(on: edge)
            trySpillAccumulation(edgeKey: edge.key)
        }
    }

    private var accumulationGrowth: CGFloat {
        accumulationRate.growth * accumulationSizeContribution
    }

    private func spawnTreeIfNeeded(on edge: SnowCollisionEdge) {
        guard
            let height = accumulationByEdgeKey[edge.key],
            height >= min(20, accumulationRate.maximumHeight * 0.86),
            !plantedTreeKeys.contains(edge.key)
        else {
            return
        }

        plantedTreeKeys.insert(edge.key)
        let tree = SKNode()
        tree.position = CGPoint(x: (edge.xRange.lowerBound + edge.xRange.upperBound) / 2, y: edge.y + height)
        tree.setScale(0.25)
        addSaplingBody(to: tree)
        seasonalRoot.addChild(tree)
        tree.run(.sequence([
            .scale(to: 0.48 * visualScale.value, duration: 3.5),
            .scale(to: 0.72 * visualScale.value, duration: 5.0),
            .scale(to: 0.95 * visualScale.value, duration: 7.0)
        ]))
    }

    private func addSaplingBody(to tree: SKNode) {
        if let texture = XPMTextureCache.shared.texture(named: "snowtree.xpm") ?? XPMTextureCache.shared.texture(named: "tree-1_100px.xpm") {
            let sprite = SKSpriteNode(texture: texture)
            sprite.setScale(0.42)
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
            tree.addChild(sprite)
            return
        }

        let trunk = SKShapeNode(rect: CGRect(x: -2, y: 0, width: 4, height: 10), cornerRadius: 1)
        trunk.fillColor = NSColor.brown.withAlphaComponent(0.72)
        trunk.strokeColor = .clear
        tree.addChild(trunk)
        for level in 0..<3 {
            let width = CGFloat(22 - level * 4)
            let y = CGFloat(6 + level * 9)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: y + 16))
            path.addLine(to: CGPoint(x: -width / 2, y: y))
            path.addLine(to: CGPoint(x: width / 2, y: y))
            path.closeSubpath()
            let branch = SKShapeNode(path: path)
            branch.fillColor = NSColor.systemGreen.withAlphaComponent(0.74)
            branch.strokeColor = .clear
            tree.addChild(branch)
        }
    }

    private func smoothAccumulationIfNeeded(at currentTime: TimeInterval) {
        guard currentTime >= nextSmoothingTime else {
            return
        }

        nextSmoothingTime = currentTime + 30
        guard Double.random(in: 0...1) < 0.3 else {
            return
        }

        var didChange = false
        for (key, height) in accumulationByEdgeKey {
            guard height > 3 else { continue }
            let target = min(accumulationRate.maximumHeight, max(3, height * CGFloat.random(in: 0.3...1.0)))
            accumulationByEdgeKey[key] = target
            didChange = true
        }

        if didChange {
            rebuildAccumulationNodes()
        }
    }

    private func trySpillAccumulation(edgeKey: String) {
        guard
            accumulationSpillMode != .off,
            let edge = edgeByKey[edgeKey],
            let height = accumulationByEdgeKey[edgeKey],
            height >= accumulationRate.maximumHeight * 0.88
        else {
            return
        }

        let lastSpill = lastSpillByEdgeKey[edgeKey] ?? 0
        guard currentSceneTime - lastSpill > spillCooldown(for: edge) else {
            return
        }

        lastSpillByEdgeKey[edgeKey] = currentSceneTime
        let mode = resolvedSpillMode
        emitSpill(mode: mode, from: edge, height: height)
        accumulationByEdgeKey[edgeKey] = remainingAccumulationHeight(after: mode, currentHeight: height)
    }

    private func rebuildAccumulationNodes() {
        accumulationRoot.removeAllChildren()
        guard isAccumulationEnabled else {
            return
        }

        for edge in collisionEdges {
            guard let height = accumulationByEdgeKey[edge.key], height > 0 else {
                continue
            }

            let width = max(0, edge.xRange.upperBound - edge.xRange.lowerBound)
            guard width > 0 else {
                continue
            }

            let inset = min(10, width * 0.04)
            let cappedWidth = max(0, width - inset * 2)
            guard cappedWidth > 0 else {
                continue
            }

            let rect = CGRect(
                x: edge.xRange.lowerBound + inset,
                y: edge.y,
                width: cappedWidth,
                height: height
            )
            addAccumulationDrift(in: rect, edgeKey: edge.key)
        }
    }

    private func addAccumulationDrift(in rect: CGRect, edgeKey: String) {
        if accumulationStyle != .soft {
            let shadowRect = CGRect(
                x: rect.minX,
                y: rect.minY - 1,
                width: rect.width,
                height: max(2, rect.height * 0.35)
            )
            let shadow = SKShapeNode(path: roundedDriftPath(in: shadowRect, crownScale: 0.2, phase: 0))
            shadow.fillColor = NSColor(calibratedWhite: 0.72, alpha: 0.22)
            shadow.strokeColor = .clear
            shadow.blendMode = .alpha
            accumulationRoot.addChild(shadow)
        }

        let main = SKShapeNode(path: roundedDriftPath(in: rect, crownScale: mainCrownScale, phase: phase(for: edgeKey)))
        main.fillColor = NSColor.white.withAlphaComponent(mainAlpha)
        main.strokeColor = NSColor.white.withAlphaComponent(accumulationStyle == .soft ? 0.35 : 0.58)
        main.lineWidth = 1
        main.blendMode = .alpha
        accumulationRoot.addChild(main)

        if accumulationStyle != .soft {
            let highlightRect = CGRect(
                x: rect.minX + min(8, rect.width * 0.04),
                y: rect.minY + rect.height * 0.55,
                width: max(0, rect.width - min(16, rect.width * 0.08)),
                height: max(2, rect.height * 0.28)
            )
            if highlightRect.width > 0 {
                let highlight = SKShapeNode(path: roundedDriftPath(in: highlightRect, crownScale: 0.55, phase: phase(for: edgeKey) + .pi / 5))
                highlight.fillColor = NSColor.white.withAlphaComponent(accumulationStyle == .detailed ? 0.42 : 0.32)
                highlight.strokeColor = .clear
                highlight.blendMode = .alpha
                accumulationRoot.addChild(highlight)
            }
        }

        if accumulationStyle != .soft {
            addAccumulationClumps(in: rect, edgeKey: edgeKey)
        }
    }

    private var mainCrownScale: CGFloat {
        switch accumulationStyle {
        case .soft: 0.28
        case .layered: 0.45
        case .detailed: 0.58
        }
    }

    private var mainAlpha: CGFloat {
        switch accumulationStyle {
        case .soft: 0.72
        case .layered: 0.84
        case .detailed: 0.88
        }
    }

    private func roundedDriftPath(in rect: CGRect, crownScale: CGFloat, phase: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let crown = min(rect.height * crownScale, 9)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - crown))

        let segmentCount = max(3, min(10, Int(rect.width / 80)))
        for index in stride(from: segmentCount, through: 0, by: -1) {
            let progress = CGFloat(index) / CGFloat(segmentCount)
            let x = rect.minX + rect.width * progress
            let wave = sin(progress * .pi * 3 + phase) * crown * 0.35
            let y = rect.maxY - crown + crown * 0.5 + wave
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }

    private func addAccumulationClumps(in rect: CGRect, edgeKey: String) {
        guard rect.height >= 6, rect.width >= 80 else {
            return
        }

        let seed = abs(edgeKey.hashValue)
        let clumpLimit = accumulationStyle == .detailed ? 8 : 5
        let clumpDivisor: CGFloat = accumulationStyle == .detailed ? 120 : 170
        let clumpCount = min(clumpLimit, max(1, Int(rect.width / clumpDivisor)))
        for index in 0..<clumpCount {
            let progressSeed = CGFloat((seed / max(index + 1, 1)) % 100) / 100
            let progress = min(0.92, max(0.08, (CGFloat(index) + 0.45 + progressSeed * 0.25) / CGFloat(clumpCount)))
            let radius = min(5, max(2, rect.height * CGFloat(0.13 + progressSeed * 0.08)))
            let clump = SKShapeNode(circleOfRadius: radius)
            clump.position = CGPoint(
                x: rect.minX + rect.width * progress,
                y: rect.minY + rect.height * CGFloat(0.62 + progressSeed * 0.18)
            )
            clump.fillColor = NSColor.white.withAlphaComponent(0.5)
            clump.strokeColor = NSColor.white.withAlphaComponent(0.22)
            clump.lineWidth = 0.5
            clump.blendMode = .alpha
            accumulationRoot.addChild(clump)
        }
    }

    private func phase(for edgeKey: String) -> CGFloat {
        CGFloat(abs(edgeKey.hashValue % 628)) / 100
    }

    private func emitOverflowSpill(from edge: SnowCollisionEdge, height: CGFloat) {
        emitIcicleSpill(from: edge, height: height, intensity: 0.72)
        emitEdgeLeak(from: edge, height: height, intensity: 0.8)
        emitPowderSpill(from: edge, height: height * 0.55, particleLimit: 18)
    }

    private func emitAvalancheSpill(from edge: SnowCollisionEdge, height: CGFloat) {
        emitIcicleSpill(from: edge, height: height, intensity: 1.0)
        emitCollapsedSnow(from: edge, height: height)
        emitDetailedSnowSpill(from: edge, height: height)
        emitEdgeLeak(from: edge, height: height, intensity: 1.0)
    }

    private func emitTriggeredSpill(from edge: SnowCollisionEdge, height: CGFloat) {
        if accumulationSpillMode == .off {
            emitCollapsedSnow(from: edge, height: height)
        } else {
            emitSpill(mode: resolvedSpillMode, from: edge, height: height)
        }
    }

    private var resolvedSpillMode: AccumulationSpillMode {
        if accumulationSpillMode == .random {
            [.overflow, .avalanche, .detailed, .edgeLeak].randomElement() ?? .detailed
        } else {
            accumulationSpillMode
        }
    }

    private func emitSpill(mode: AccumulationSpillMode, from edge: SnowCollisionEdge, height: CGFloat) {
        switch mode {
        case .off:
            break
        case .overflow:
            emitOverflowSpill(from: edge, height: height)
        case .avalanche:
            emitAvalancheSpill(from: edge, height: height)
        case .detailed:
            emitIcicleSpill(from: edge, height: height, intensity: 0.9)
            emitDetailedSnowSpill(from: edge, height: height)
            emitPowderSpill(from: edge, height: height * 0.45, particleLimit: 16)
        case .edgeLeak:
            emitEdgeLeak(from: edge, height: height, intensity: 1.0)
        case .random:
            emitSpill(mode: resolvedSpillMode, from: edge, height: height)
        }
    }

    private func remainingAccumulationHeight(after mode: AccumulationSpillMode, currentHeight: CGFloat) -> CGFloat {
        switch mode {
        case .off:
            currentHeight
        case .overflow:
            max(2, currentHeight * 0.72)
        case .edgeLeak:
            max(2, currentHeight * 0.82)
        case .avalanche:
            max(2, currentHeight * 0.22)
        case .detailed:
            max(2, currentHeight * 0.35)
        case .random:
            max(2, currentHeight * 0.45)
        }
    }

    private func spillCooldown(for edge: SnowCollisionEdge) -> TimeInterval {
        let width = max(1, edge.xRange.upperBound - edge.xRange.lowerBound)
        if width < 180 {
            return 4.4
        }
        if width < 360 {
            return 3.6
        }
        return 3.0
    }

    private func spillDurationScale(forWidth width: CGFloat) -> CGFloat {
        if width < 180 {
            return 1.45
        }
        if width < 360 {
            return 1.22
        }
        return 1.0
    }

    private func emitIcicleSpill(from edge: SnowCollisionEdge, height: CGFloat, intensity: CGFloat) {
        let width = max(0, edge.xRange.upperBound - edge.xRange.lowerBound)
        guard width > 24, height >= accumulationRate.maximumHeight * 0.62 else {
            return
        }

        let heightRatio = min(1.0, max(0.0, height / max(accumulationRate.maximumHeight, 1)))
        let count = min(9, max(2, Int(width / 95) + Int(heightRatio * 3)))
        let durationScale = spillDurationScale(forWidth: width)
        let peakX = edge.xRange.lowerBound + width * CGFloat.random(in: 0.35...0.65)

        for _ in 0..<count {
            let spread = width * CGFloat.random(in: 0.08...0.38)
            let x = min(edge.xRange.upperBound - 4, max(edge.xRange.lowerBound + 4, peakX + CGFloat.random(in: -spread...spread)))
            let length = CGFloat.random(in: 18...54) * (0.55 + heightRatio * 1.15) * intensity
            let topWidth = CGFloat.random(in: 4...9) * (0.7 + heightRatio * 0.8)
            let bottomWidth = max(1.4, topWidth * CGFloat.random(in: 0.18...0.36))
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -topWidth * 0.5, y: 0))
            path.addLine(to: CGPoint(x: topWidth * 0.5, y: 0))
            path.addLine(to: CGPoint(x: bottomWidth * 0.5, y: -length))
            path.addLine(to: CGPoint(x: 0, y: -length - CGFloat.random(in: 3...9) * heightRatio))
            path.addLine(to: CGPoint(x: -bottomWidth * 0.5, y: -length))
            path.closeSubpath()

            let icicle = SKShapeNode(path: path)
            icicle.position = CGPoint(x: x, y: edge.y + height * CGFloat.random(in: 0.65...1.0))
            icicle.fillColor = NSColor.white.withAlphaComponent(0.78 + heightRatio * 0.14)
            icicle.strokeColor = NSColor(calibratedRed: 0.78, green: 0.9, blue: 1.0, alpha: 0.42)
            icicle.lineWidth = 0.7
            icicle.blendMode = .alpha
            collapseRoot.addChild(icicle)
            trimCollapseNodesIfNeeded()

            let drop = min(360, max(120, edge.y + length * CGFloat.random(in: 1.1...1.9)))
            let drift = CGFloat.random(in: -14...14) + windDrift(20)
            let duration = TimeInterval(CGFloat.random(in: 1.8...3.4) * durationScale * (0.85 + heightRatio * 0.35))
            let fall = SKAction.moveBy(x: drift, y: -drop, duration: duration)
            fall.timingMode = .easeIn
            let rotate = SKAction.rotate(byAngle: CGFloat.random(in: -0.18...0.18), duration: duration)
            let fade = SKAction.fadeOut(withDuration: duration)
            icicle.run(.sequence([.group([fall, rotate, fade]), .removeFromParent()]))
        }
    }

    private func emitCollapsedSnow(from edge: SnowCollisionEdge, height: CGFloat) {
        let width = max(0, edge.xRange.upperBound - edge.xRange.lowerBound)
        guard width > 0 else {
            return
        }
        let durationScale = spillDurationScale(forWidth: width)

        let segmentCount = min(8, max(2, Int(width / 120)))
        let segmentWidth = width / CGFloat(segmentCount)

        for index in 0..<segmentCount {
            let segmentHeight = max(3, height * CGFloat.random(in: 0.45...0.9))
            let originX = edge.xRange.lowerBound + CGFloat(index) * segmentWidth
            let rect = CGRect(
                x: originX,
                y: edge.y,
                width: max(10, segmentWidth * CGFloat.random(in: 0.55...0.95)),
                height: segmentHeight
            )
            let node = SKShapeNode(rect: rect, cornerRadius: min(5, segmentHeight / 2))
            node.fillColor = NSColor.white.withAlphaComponent(0.78)
            node.strokeColor = NSColor.white.withAlphaComponent(0.35)
            node.lineWidth = 1
            node.blendMode = .alpha
            collapseRoot.addChild(node)
            trimCollapseNodesIfNeeded()

            let fallDistance = min(max(edge.y + segmentHeight, 70), 220)
            let drift = CGFloat.random(in: -22...22) + windDrift(32)
            let duration = TimeInterval(CGFloat.random(in: 1.35...2.25) * durationScale)
            let fall = SKAction.moveBy(x: drift, y: -fallDistance, duration: duration)
            fall.timingMode = .easeIn
            let fade = SKAction.fadeOut(withDuration: duration)
            node.run(.sequence([.group([fall, fade]), .removeFromParent()]))
        }
    }

    private func emitDetailedSnowSpill(from edge: SnowCollisionEdge, height: CGFloat) {
        let width = max(0, edge.xRange.upperBound - edge.xRange.lowerBound)
        guard width > 0 else {
            return
        }
        let durationScale = spillDurationScale(forWidth: width)

        let sheetCount = min(10, max(3, Int(width / 90)))
        let particleCount = min(42, max(18, Int(width / 18)))
        let sheetWidth = width / CGFloat(sheetCount)

        for index in 0..<sheetCount {
            let originX = edge.xRange.lowerBound + CGFloat(index) * sheetWidth
            let segmentHeight = max(5, height * CGFloat.random(in: 0.35...0.72))
            let rect = CGRect(
                x: originX + CGFloat.random(in: -3...3),
                y: edge.y + CGFloat.random(in: -1...2),
                width: max(12, sheetWidth * CGFloat.random(in: 0.45...0.85)),
                height: segmentHeight
            )
            let sheet = SKShapeNode(path: roundedDriftPath(in: rect, crownScale: 0.4, phase: CGFloat(index)))
            sheet.fillColor = NSColor.white.withAlphaComponent(0.78)
            sheet.strokeColor = NSColor.white.withAlphaComponent(0.38)
            sheet.lineWidth = 0.8
            sheet.blendMode = .alpha
            collapseRoot.addChild(sheet)
            trimCollapseNodesIfNeeded()

            let fallDistance = min(max(edge.y + height, 110), 340)
            let drift = CGFloat.random(in: -32...32) + windDrift(42)
            let duration = TimeInterval(CGFloat.random(in: 1.55...2.75) * durationScale)
            let fall = SKAction.moveBy(x: drift, y: -fallDistance, duration: duration)
            fall.timingMode = .easeIn
            let rotate = SKAction.rotate(byAngle: CGFloat.random(in: -0.35...0.35), duration: duration)
            let fade = SKAction.fadeOut(withDuration: duration)
            sheet.run(.sequence([.group([fall, rotate, fade]), .removeFromParent()]))
        }

        for index in 0..<particleCount {
            let radius = CGFloat.random(in: 1.5...4.8)
            let flake = SKShapeNode(circleOfRadius: radius)
            flake.position = CGPoint(
                x: edge.xRange.lowerBound + width * CGFloat(index) / CGFloat(max(particleCount - 1, 1)) + CGFloat.random(in: -8...8),
                y: edge.y + height * CGFloat.random(in: 0.15...0.95)
            )
            flake.fillColor = NSColor.white.withAlphaComponent(CGFloat.random(in: 0.55...0.92))
            flake.strokeColor = NSColor.white.withAlphaComponent(0.24)
            flake.lineWidth = 0.4
            flake.blendMode = .alpha
            collapseRoot.addChild(flake)
            trimCollapseNodesIfNeeded()

            let duration = TimeInterval(CGFloat.random(in: 1.35...3.0) * durationScale)
            let fall = SKAction.moveBy(
                x: CGFloat.random(in: -52...52) + windDrift(48),
                y: -CGFloat.random(in: 90...300),
                duration: duration
            )
            fall.timingMode = .easeIn
            let scale = SKAction.scale(to: CGFloat.random(in: 0.35...0.8), duration: duration)
            let fade = SKAction.fadeOut(withDuration: duration)
            flake.run(.sequence([.group([fall, scale, fade]), .removeFromParent()]))
        }
    }

    private func emitEdgeLeak(from edge: SnowCollisionEdge, height: CGFloat, intensity: CGFloat) {
        let width = max(0, edge.xRange.upperBound - edge.xRange.lowerBound)
        guard width > 36 else {
            return
        }
        let durationScale = spillDurationScale(forWidth: width)

        let sideCount = min(8, max(2, Int(width / 170)))
        let leakWidth = min(52, width * 0.18)
        let leftEdge = SnowCollisionEdge(
            xRange: edge.xRange.lowerBound...(edge.xRange.lowerBound + leakWidth),
            y: edge.y,
            windowID: edge.windowID,
            order: edge.order
        )
        let rightEdge = SnowCollisionEdge(
            xRange: (edge.xRange.upperBound - leakWidth)...edge.xRange.upperBound,
            y: edge.y,
            windowID: edge.windowID,
            order: edge.order
        )

        for leakEdge in [leftEdge, rightEdge] {
            for index in 0..<sideCount {
                let radius = CGFloat.random(in: 1.8...4.4) * max(0.65, intensity)
                let flake = SKShapeNode(circleOfRadius: radius)
                let progress = CGFloat(index) / CGFloat(max(sideCount - 1, 1))
                flake.position = CGPoint(
                    x: leakEdge.xRange.lowerBound + (leakEdge.xRange.upperBound - leakEdge.xRange.lowerBound) * progress + CGFloat.random(in: -3...3),
                    y: leakEdge.y + height * CGFloat.random(in: 0.15...0.85)
                )
                flake.fillColor = NSColor.white.withAlphaComponent(CGFloat.random(in: 0.58...0.88))
                flake.strokeColor = .clear
                flake.blendMode = .alpha
                collapseRoot.addChild(flake)
                trimCollapseNodesIfNeeded()

                let outward = leakEdge.xRange.lowerBound == edge.xRange.lowerBound ? CGFloat.random(in: -28...(-8)) : CGFloat.random(in: 8...28)
                let duration = TimeInterval(CGFloat.random(in: 1.25...2.45) * durationScale)
                let fall = SKAction.moveBy(
                    x: outward + windDrift(38),
                    y: -CGFloat.random(in: 65...210) * max(0.7, intensity),
                    duration: duration
                )
                fall.timingMode = .easeIn
                let fade = SKAction.fadeOut(withDuration: duration)
                flake.run(.sequence([.group([fall, fade]), .removeFromParent()]))
            }
        }
    }

    private func emitPowderSpill(from edge: SnowCollisionEdge, height: CGFloat, particleLimit: Int) {
        let width = max(0, edge.xRange.upperBound - edge.xRange.lowerBound)
        guard width > 0 else {
            return
        }
        let durationScale = spillDurationScale(forWidth: width)

        let particleCount = min(particleLimit, max(8, Int(width / 34)))
        for _ in 0..<particleCount {
            let flake = SKShapeNode(circleOfRadius: CGFloat.random(in: 1.0...2.8))
            flake.position = CGPoint(
                x: CGFloat.random(in: edge.xRange.lowerBound...edge.xRange.upperBound),
                y: edge.y + CGFloat.random(in: 0...max(4, height))
            )
            flake.fillColor = NSColor.white.withAlphaComponent(CGFloat.random(in: 0.38...0.72))
            flake.strokeColor = .clear
            flake.blendMode = .alpha
            collapseRoot.addChild(flake)
            trimCollapseNodesIfNeeded()

            let duration = TimeInterval(CGFloat.random(in: 1.05...2.0) * durationScale)
            let burst = SKAction.moveBy(
                x: CGFloat.random(in: -28...28) + windDrift(32),
                y: -CGFloat.random(in: 38...140),
                duration: duration
            )
            burst.timingMode = .easeIn
            let fade = SKAction.fadeOut(withDuration: duration)
            flake.run(.sequence([.group([burst, fade]), .removeFromParent()]))
        }
    }

    private func settleAccumulationIfNeeded(at currentTime: TimeInterval) {
        guard accumulationSpillMode != .off, isAccumulationEnabled, currentTime - lastSettlingCheck > 3.5 else {
            return
        }

        lastSettlingCheck = currentTime
        for (key, height) in accumulationByEdgeKey {
            guard
                height >= accumulationRate.maximumHeight * 0.62,
                let edge = edgeByKey[key]
            else {
                continue
            }

            let chance = min(0.22, Double(height / max(accumulationRate.maximumHeight, 1)) * 0.13)
            guard Double.random(in: 0...1) < chance else {
                continue
            }

            emitEdgeLeak(from: edge, height: height, intensity: 0.45)
            emitPowderSpill(from: edge, height: height * 0.3, particleLimit: 10)
            accumulationByEdgeKey[key] = max(2, height * 0.88)
        }

        rebuildAccumulationNodes()
    }

    private func trimCollapseNodesIfNeeded() {
        while collapseRoot.children.count > maximumCollapseNodes {
            collapseRoot.children.first?.removeFromParent()
        }
    }

    private func positionEmitters() {
        for emitter in emitters {
            emitter.position = CGPoint(x: size.width / 2, y: size.height + 12)
            emitter.particlePositionRange = CGVector(dx: size.width, dy: 0)
        }
        updateEmitterBirthRates()
    }

    private func updateEmitterBirthRates() {
        for (index, emitter) in emitters.enumerated() {
            let tier = Self.snowflakeSizeTiers[index]
            emitter.particleBirthRate = isPaused ? 0 : currentBirthRate * tier.birthRateShare
        }
        if isPaused {
            largeFlakeSpawnCarry = 0
        }
    }

    private func makeSnowTexture() -> SKTexture {
        let image = NSImage(size: NSSize(width: 6, height: 6))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 6, height: 6)).fill()
        image.unlockFocus()
        return SKTexture(image: image)
    }
}
