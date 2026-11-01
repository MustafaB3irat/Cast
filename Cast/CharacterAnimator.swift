import Foundation

import RealityKit
import simd

/// Pose the imported skeletons without replacing meshes, fur materials or user transforms.
@MainActor final class CharacterAnimator {
    private struct Rig {
        let entity: ModelEntity
        let names: [String]
        let rest: [Transform]
        let jointOrientations: [simd_quatf]
    }
    private var rigs: [Rig] = []
    private var currentAction = "idle"
    private var playback: [AnimationPlaybackController] = []
    private var cache: [String: [AnimationResource]] = [:]
    var activeAnimationCount: Int { playback.count }
    var jointCount: Int { rigs.reduce(0) { $0 + $1.names.count } }

    init(_ root: Entity) {
        func visit(_ entity: Entity) {
            if let model = entity as? ModelEntity, !model.jointNames.isEmpty,
               model.jointNames.count == model.jointTransforms.count {
                var orientations: [String: simd_quatf] = [:]
                let world = model.orientation(relativeTo: root)
                let jointOrientations = zip(model.jointNames, model.jointTransforms).map { name, transform in
                    let parent = name.split(separator: "/").dropLast().joined(separator: "/")
                    let rotation = (orientations[parent] ?? world) * transform.rotation
                    orientations[name] = rotation
                    return rotation
                }
                rigs.append(Rig(entity: model, names: model.jointNames, rest: model.jointTransforms, jointOrientations: jointOrientations))
            }
            for child in entity.children { visit(child) }
        }
        visit(root)
    }

    func reset() {
        playback.forEach { $0.stop() }; playback.removeAll()
        currentAction = "idle"
        for rig in rigs { rig.entity.jointTransforms = rig.rest }
    }

    func update(action: String, time: Float, duration: Float) {
        guard action != currentAction else { return }
        reset()
        guard action != "idle", duration > 0 else { return }
        currentAction = action
        let key = "\(action):\(duration)"
        let resources: [AnimationResource]
        if let cached = cache[key] { resources = cached }
        else {
            resources = rigs.compactMap { rig in
                let frames = (0...Int(ceil(duration * 30))).map { frame in
                    JointTransforms(pose(rig, action: action, time: Float(frame) / 30, duration: duration))
                }
                let definition = SampledAnimation<JointTransforms>(jointNames: rig.names, frames: frames,
                    frameInterval: 1 / 30, bindTarget: .jointTransforms)
                return try? AnimationResource.generate(with: definition)
            }
            if resources.count == rigs.count { cache[key] = resources }
        }
        for (rig, resource) in zip(rigs, resources) {
            let controller = rig.entity.playAnimation(resource)
            controller.time = TimeInterval(max(0, time))
            playback.append(controller)
        }
    }

    // Also exposed internally for deterministic pose validation against the imported assets.
    func applyPose(action: String, time: Float, duration: Float) {
        for rig in rigs { rig.entity.jointTransforms = pose(rig, action: action, time: time, duration: duration) }
    }

    private func pose(_ rig: Rig, action: String, time: Float, duration: Float) -> [Transform] {
        // Ease both ends back into the authored resting pose.
        let blend = min(1, max(0, time / 0.2)) * min(1, max(0, (duration - time) / 0.25))
            var pose = rig.rest
            for index in pose.indices {
                let name = String(rig.names[index].split(separator: "/").last ?? "").lowercased().replacingOccurrences(of: ".", with: "_")
                let side: Float = name.hasSuffix("_l") ? 1 : -1
                var angle: Float = 0
                var axis = SIMD3<Float>(1, 0, 0)
                switch action {
                case "wave":
                    if name == "arm_upper_r" { angle = -1.7; axis = [0, 0, 1] }
                    if name == "arm_lower_r" { angle = -0.5 + sin(time * 12) * 0.45; axis = [0, 0, 1] }
                    if name == "hand_r" { angle = sin(time * 12) * 0.35; axis = [0, 0, 1] }
                case "dance":
                    if name.hasPrefix("arm_upper") { angle = side * (0.5 + sin(time * 7) * 0.4); axis = [0, 0, 1] }
                    if name.hasPrefix("arm_lower") { angle = 0.4 + sin(time * 7 + side) * 0.3 }
                    if name == "body_mid" { angle = sin(time * 7) * 0.15; axis = [0, 0, 1] }
                case "move":
                    if name.hasPrefix("leg_upper") { angle = sin(time * 12) * side * 0.35 }
                    if name.hasPrefix("arm_upper") { angle = -sin(time * 12) * side * 0.3 }
                case "jump":
                    if name.hasPrefix("arm_upper") { angle = side * 0.65; axis = [0, 0, 1] }
                    if name.hasPrefix("leg_lower") { angle = sin(min(time * 4, .pi)) * 0.35 }
                case "inspect":
                    if name == "body_upper" { angle = sin(time * 3) * 0.35; axis = [0, 1, 0] }
                case "spar":
                    if name.hasPrefix("arm_upper") { angle = 0.6 + sin(time * 8 + side * .pi / 2) * 0.4 }
                    if name.hasPrefix("arm_lower") { angle = 0.7 }
                default: break
                }
                pose[index].rotation = rig.rest[index].rotation * simd_quatf(angle: angle * blend, axis: rig.jointOrientations[index].inverse.act(axis))
            }
            return pose
    }
}
