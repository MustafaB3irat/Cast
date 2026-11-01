import RealityKit
import simd

@MainActor enum CharacterPhysics {
    static let scaleRange: ClosedRange<Float> = 0.25...10

    static let characters = CollisionGroup(rawValue: 1 << 8)

    static func configure(_ entity: ModelEntity, bounds: BoundingBox, scale: Float, mode: PhysicsBodyMode) {
        // A conservative convex envelope includes limbs; labels aren't part of the body.
        let size = simd_max(bounds.extents + SIMD3<Float>(0.02, 0.004, 0.02), SIMD3<Float>(repeating: 0.025))
        let shape = ShapeResource.generateBox(size: size).offsetBy(translation: bounds.center + [0, 0.002, 0])
        entity.collision = CollisionComponent(shapes: [shape], filter: CollisionFilter(group: characters, mask: .all))
        let material = PhysicsMaterialResource.generate(friction: 0.35, restitution: 0.08)
        var body = PhysicsBodyComponent(shapes: [shape], mass: mass(scale: scale), material: material, mode: mode)
        body.isAffectedByGravity = true
        body.isRotationLocked = (true, true, true)
        body.isContinuousCollisionDetectionEnabled = mode == .dynamic
        body.linearDamping = 0.5
        body.angularDamping = 0.9
        entity.physicsBody = body
        entity.physicsMotion = PhysicsMotionComponent()
    }

    static func mass(scale: Float) -> Float { 0.35 * pow(max(scaleRange.lowerBound, min(scaleRange.upperBound, scale)), 3) }

    /// Circular horizontal envelope stays conservative when the avatar rotates.
    static func overlaps(position: SIMD3<Float>, bounds: BoundingBox, scale: Float,
                         otherPosition: SIMD3<Float>, otherBounds: BoundingBox, otherScale: Float) -> Bool {
        let bottom = position.y + bounds.min.y * scale
        let top = position.y + bounds.max.y * scale
        let otherBottom = otherPosition.y + otherBounds.min.y * otherScale
        let otherTop = otherPosition.y + otherBounds.max.y * otherScale
        guard bottom < otherTop + 0.005, top > otherBottom - 0.005 else { return false }
        let radius = simd_length(SIMD2(bounds.extents.x, bounds.extents.z)) * scale / 2 + 0.008
        let otherRadius = simd_length(SIMD2(otherBounds.extents.x, otherBounds.extents.z)) * otherScale / 2 + 0.008
        return simd_length(SIMD2(position.x - otherPosition.x, position.z - otherPosition.z)) < radius + otherRadius
    }

    static func needsSupportRecovery(position: SIMD3<Float>, safePosition: SIMD3<Float>) -> Bool {
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite else { return true }
        return position.y < safePosition.y - 0.08
    }

    /// A bounded locomotion step; the caller validates support and swept clearance.
    static func walkingStep(from position: SIMD3<Float>, toward target: SIMD3<Float>, deltaTime: Float) -> SIMD3<Float> {
        let delta = SIMD3<Float>(target.x - position.x, 0, target.z - position.z)
        let distance = simd_length(delta)
        guard distance > 0.001, deltaTime.isFinite, deltaTime > 0 else { return position }
        return position + delta / distance * min(distance, 0.18 * min(deltaTime, 0.05))
    }

    /// Velocity correction through impulses keeps dynamic collisions and gravity active.
    static func driveImpulse(delta: SIMD3<Float>, velocity: SIMD3<Float>, mass: Float, deltaTime: Float) -> SIMD3<Float> {
        let horizontal = SIMD3<Float>(delta.x, 0, delta.z)
        let distance = simd_length(horizontal)
        let desired = distance > 0.005 ? horizontal / distance * min(0.20, distance * 4) : .zero
        let correction = desired - SIMD3<Float>(velocity.x, 0, velocity.z)
        let limit = 12 * max(0, min(deltaTime, 0.05))
        let length = simd_length(correction)
        return (length > limit && length > 0 ? correction / length * limit : correction) * mass
    }

    static func drive(_ entity: ModelEntity, delta: SIMD3<Float>, deltaTime: Float) {
        guard entity.physicsBody?.mode == .dynamic else { return }
        let impulse = driveImpulse(delta: delta, velocity: entity.physicsMotion?.linearVelocity ?? .zero,
                                   mass: entity.physicsBody?.massProperties.mass ?? mass(scale: entity.scale.x), deltaTime: deltaTime)
        entity.applyLinearImpulse(impulse, relativeTo: nil)
    }
}
