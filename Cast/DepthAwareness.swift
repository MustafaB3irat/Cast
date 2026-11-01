import ARKit
import CoreVideo
import simd

/// Raw (not temporally smoothed) depth keeps moving obstacles responsive.
/// Points stay on-device and are never included in API requests.
enum DepthAwareness {
    static func worldPoint(pixel: SIMD2<Float>, depth: Float, resolution: SIMD2<Float>,
                           imageResolution: SIMD2<Float>, intrinsics: simd_float3x3,
                           camera: simd_float4x4) -> SIMD3<Float>? {
        guard depth.isFinite, depth > 0.1, depth < 5, resolution.x > 0, resolution.y > 0,
              intrinsics[0, 0] > 0, intrinsics[1, 1] > 0 else { return nil }
        let image = pixel * imageResolution / resolution
        // Image coordinates are right/down; ARKit camera coordinates are right/up/-Z.
        let local = SIMD4<Float>((image.x - intrinsics[2, 0]) * depth / intrinsics[0, 0],
                                 -(image.y - intrinsics[2, 1]) * depth / intrinsics[1, 1], -depth, 1)
        let world = camera * local
        return [world.x, world.y, world.z]
    }

    static func points(frame: ARFrame) -> [SIMD3<Float>]? {
        guard let depth = frame.sceneDepth, let confidence = depth.confidenceMap else { return nil }
        return points(depth: depth.depthMap, confidence: confidence,
                      imageResolution: SIMD2(Float(frame.camera.imageResolution.width), Float(frame.camera.imageResolution.height)),
                      intrinsics: frame.camera.intrinsics, camera: frame.camera.transform)
    }

    static func points(depth: CVPixelBuffer, confidence: CVPixelBuffer, imageResolution: SIMD2<Float>,
                       intrinsics: simd_float3x3, camera: simd_float4x4) -> [SIMD3<Float>] {
        guard CVPixelBufferGetPixelFormatType(depth) == kCVPixelFormatType_DepthFloat32,
              CVPixelBufferGetPixelFormatType(confidence) == kCVPixelFormatType_OneComponent8 else { return [] }
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        CVPixelBufferLockBaseAddress(confidence, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly); CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
        guard let depthBase = CVPixelBufferGetBaseAddress(depth), let confidenceBase = CVPixelBufferGetBaseAddress(confidence) else { return [] }
        let width = CVPixelBufferGetWidth(depth), height = CVPixelBufferGetHeight(depth)
        let cw = CVPixelBufferGetWidth(confidence), ch = CVPixelBufferGetHeight(confidence)
        guard width > 0, height > 0, cw > 0, ch > 0 else { return [] }
        let depthStride = CVPixelBufferGetBytesPerRow(depth), confidenceStride = CVPixelBufferGetBytesPerRow(confidence)
        let resolution = SIMD2<Float>(Float(width), Float(height))
        var points: [SIMD3<Float>] = []
        points.reserveCapacity(3200)
        let step = max(2, width / 64)
        for y in stride(from: 0, to: height, by: step) {
            let row = depthBase.advanced(by: y * depthStride).assumingMemoryBound(to: Float.self)
            let confidenceRow = confidenceBase.advanced(by: (y * ch / height) * confidenceStride).assumingMemoryBound(to: UInt8.self)
            for x in stride(from: 0, to: width, by: step) {
                guard confidenceRow[x * cw / width] >= 1,
                      let point = worldPoint(pixel: [Float(x), Float(y)], depth: row[x], resolution: resolution,
                                             imageResolution: imageResolution, intrinsics: intrinsics, camera: camera) else { continue }
                points.append(point)
            }
        }
        return points
    }
}

/// No semantic claim: this tracks a nearby depth cluster, not a named person or foot.
struct ProximityReflex {
    struct Threat {
        let point: SIMD3<Float>
        let closingSpeed: Float
        let clearance: Float
    }
    private var previousPoint: SIMD3<Float>?
    private var previousTime: TimeInterval?
    private var evidence = 0
    private var cooldownUntil: TimeInterval = 0

    mutating func observe(point: SIMD3<Float>?, actor: SIMD3<Float>, radius: Float, now: TimeInterval) -> Threat? {
        guard let point, point.x.isFinite, point.y.isFinite, point.z.isFinite else {
            previousPoint = nil; previousTime = nil; evidence = 0; return nil
        }
        defer { previousPoint = point; previousTime = now }
        guard let previousPoint, let previousTime else { return nil }
        let dt = Float(now - previousTime)
        guard dt > 0.03, dt < 0.35, simd_distance(point, previousPoint) < 0.20 else { evidence = 0; return nil }
        let delta = SIMD2(point.x - actor.x, point.z - actor.z)
        let distance = simd_length(delta)
        guard distance > 0.001 else { return nil }
        let velocity = SIMD2(point.x - previousPoint.x, point.z - previousPoint.z) / dt
        let closing = -simd_dot(velocity, delta / distance)
        let clearance = distance - radius
        let predicted = clearance - max(0, closing) * 0.6
        // Require repeated approaching measurements. A static mug or one noisy pixel is not a threat.
        if closing > 0.06, clearance < 0.40, predicted < 0.10 { evidence += 1 }
        else { evidence = 0 }
        guard evidence >= 2, now >= cooldownUntil else { return nil }
        cooldownUntil = now + 2.5; evidence = 0
        return Threat(point: point, closingSpeed: closing, clearance: clearance)
    }

    static func nearestCluster(points: [SIMD3<Float>], feet: SIMD3<Float>, height: Float, radius: Float) -> SIMD3<Float>? {
        let nearby = points.filter {
            $0.y > feet.y + 0.025 && $0.y < feet.y + max(height, 0.25) &&
            simd_length(SIMD2($0.x - feet.x, $0.z - feet.z)) < radius + 0.45
        }.sorted {
            simd_length_squared(SIMD2($0.x - feet.x, $0.z - feet.z)) < simd_length_squared(SIMD2($1.x - feet.x, $1.z - feet.z))
        }
        guard let first = nearby.first else { return nil }
        let cluster = nearby.prefix(20).filter { simd_distance($0, first) < 0.08 }
        guard cluster.count >= 3 else { return nil }
        return cluster.reduce(.zero, +) / Float(cluster.count)
    }

    static func routeClear(points: [SIMD3<Float>], start: SIMD3<Float>, end: SIMD3<Float>, radius: Float, height: Float) -> Bool {
        let a = SIMD2(start.x, start.z), b = SIMD2(end.x, end.z), route = b - a
        let lengthSquared = simd_length_squared(route)
        return !points.contains { point in
            guard point.y > min(start.y, end.y) + 0.025, point.y < max(start.y, end.y) + max(height, 0.15) else { return false }
            let p = SIMD2(point.x, point.z)
            let t = lengthSquared > 0.000001 ? min(1, max(0, simd_dot(p - a, route) / lengthSquared)) : 0
            return simd_distance(p, a + route * t) < radius + 0.025
        }
    }
}
