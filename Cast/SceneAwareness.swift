import Foundation

/// Hysteresis prevents noisy AR distances from repeatedly retriggering reactions.
struct SceneAwareness {
    private var nearCamera: Set<UUID> = []
    private var neighbours: Set<String> = []
    private var known: Set<UUID> = []
    private var dim: Bool?

    mutating func observe(cameraDistances: [UUID: Float], pairDistances: [String: Float], light: Float?) -> [String] {
        var events: [String] = []
        let current = Set(cameraDistances.keys)
        for id in current.subtracting(known).sorted(by: { $0.uuidString < $1.uuidString }) {
            events.append("Character \(id.uuidString) has appeared in the scene.")
        }
        known = current
        nearCamera.formIntersection(current)
        for (id, distance) in cameraDistances.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            if distance < 0.65, !nearCamera.contains(id) {
                nearCamera.insert(id)
                events.append("The phone is close to character \(id.uuidString) (\(String(format: "%.2f", distance)) metres). This measures the phone, not a detected person.")
            } else if distance > 0.9, nearCamera.remove(id) != nil {
                events.append("The phone moved away from character \(id.uuidString).")
            }
        }
        neighbours.formIntersection(Set(pairDistances.keys))
        for (pair, distance) in pairDistances.sorted(by: { $0.key < $1.key }) {
            if distance < 0.35, !neighbours.contains(pair) {
                neighbours.insert(pair)
                events.append("Characters \(pair) are close together (\(String(format: "%.2f", distance)) metres).")
            } else if distance > 0.5 { neighbours.remove(pair) }
        }
        if let light {
            let next = light < 180 ? true : light > 400 ? false : dim
            if let previous = dim, let next, previous != next {
                events.append(next ? "ARKit estimates the room became dimmer." : "ARKit estimates the room became brighter.")
            }
            dim = next
        }
        return events
    }
}

struct SceneReactionGate {
    private var lastRequest: TimeInterval = -.infinity
    mutating func admit(now: TimeInterval, ready: Bool, busy: Bool) -> Bool {
        guard ready, !busy, now - lastRequest >= 10 else { return false }
        lastRequest = now
        return true
    }
}
