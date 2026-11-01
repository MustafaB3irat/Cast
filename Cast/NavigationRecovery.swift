import Foundation
import simd

/// One short detour, preserving the original destination. The caller validates both legs.
enum NavigationRecovery {
    static func detour(from start: SIMD3<Float>, to goal: SIMD3<Float>, radius: Float,
                       clear: (SIMD3<Float>, SIMD3<Float>) -> Bool) -> SIMD3<Float>? {
        let delta = SIMD3<Float>(goal.x - start.x, 0, goal.z - start.z)
        let distance = simd_length(delta)
        guard distance.isFinite, distance > 0.025, radius.isFinite else { return nil }
        let forward = delta / distance
        let side = SIMD3<Float>(forward.z, 0, -forward.x)
        let width = min(0.35, max(0.10, radius * 2 + 0.04))
        for advance: Float in [0, min(distance / 2, 0.18)] {
            for sign: Float in [1, -1] {
                let waypoint = start + forward * advance + side * width * sign
                if clear(start, waypoint) && clear(waypoint, goal) { return waypoint }
            }
        }
        return nil
    }
}

/// Requires continuous evidence; repeated failures remain held for manual repositioning.
struct SupportRecovery {
    private var stableSince: TimeInterval?
    private var lastSample: TimeInterval?
    private(set) var attempts = 0

    mutating func observe(supported: Bool, now: TimeInterval) -> Bool {
        guard now.isFinite, attempts < 2 else { return false }
        if let lastSample, now < lastSample || now - lastSample > 0.25 { stableSince = nil }
        lastSample = now
        guard supported else { stableSince = nil; return false }
        if stableSince == nil { stableSince = now }
        guard now - (stableSince ?? now) >= 1 else { return false }
        stableSince = nil
        attempts += 1
        return true
    }
}
