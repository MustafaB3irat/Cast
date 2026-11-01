import Foundation
import simd

enum InteractionRules {
    static let passiveActions: Set<String> = ["speak", "wave", "face_each_other"]
    static let playActions: Set<String> = passiveActions.union(["meet", "explore", "inspect", "dance", "jump"])

    static func allows(_ actions: [CharacterCommand], playing: Bool) -> Bool {
        let allowed = playing ? playActions : passiveActions
        return actions.count <= 2 && actions.allSatisfy { allowed.contains($0.action) }
    }

    static func meetingTarget(from start: SIMD3<Float>, to other: SIMD3<Float>, separation: Float) -> SIMD3<Float>? {
        guard abs(start.y - other.y) < 0.08 else { return nil }
        let delta = SIMD3<Float>(other.x - start.x, 0, other.z - start.z)
        let distance = simd_length(delta)
        guard distance > separation + 0.015 else { return start }
        return start + delta / distance * min(0.25, distance - separation)
    }
}
