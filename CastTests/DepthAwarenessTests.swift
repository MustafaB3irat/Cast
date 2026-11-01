import XCTest
import ARKit
@testable import Cast

final class DepthAwarenessTests: XCTestCase {
    func testProjectionUsesCameraPoseAndImageCoordinates() throws {
        let intrinsics = simd_float3x3(SIMD3(100, 0, 0), SIMD3(0, 100, 0), SIMD3(50, 50, 1))
        var camera = matrix_identity_float4x4
        camera.columns.3 = [1, 2, 3, 1]
        let centre = try XCTUnwrap(DepthAwareness.worldPoint(pixel: [25, 25], depth: 2, resolution: [50, 50],
            imageResolution: [100, 100], intrinsics: intrinsics, camera: camera))
        XCTAssertEqual(centre, [1, 2, 1])
        let corner = try XCTUnwrap(DepthAwareness.worldPoint(pixel: [50, 0], depth: 2, resolution: [50, 50],
            imageResolution: [100, 100], intrinsics: intrinsics, camera: camera))
        XCTAssertEqual(corner, [2, 3, 1])
        XCTAssertNil(DepthAwareness.worldPoint(pixel: .zero, depth: .nan, resolution: [50, 50],
            imageResolution: [100, 100], intrinsics: intrinsics, camera: camera))
    }

    func testConfidenceFilterAndPaddedBufferRows() throws {
        var depth: CVPixelBuffer?, confidence: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 10, 6, kCVPixelFormatType_DepthFloat32, nil, &depth), kCVReturnSuccess)
        XCTAssertEqual(CVPixelBufferCreate(nil, 10, 6, kCVPixelFormatType_OneComponent8, nil, &confidence), kCVReturnSuccess)
        let d = try XCTUnwrap(depth), c = try XCTUnwrap(confidence)
        CVPixelBufferLockBaseAddress(d, []); CVPixelBufferLockBaseAddress(c, [])
        for y in 0..<6 {
            let row = CVPixelBufferGetBaseAddress(d)!.advanced(by: y * CVPixelBufferGetBytesPerRow(d)).assumingMemoryBound(to: Float.self)
            let confidences = CVPixelBufferGetBaseAddress(c)!.advanced(by: y * CVPixelBufferGetBytesPerRow(c)).assumingMemoryBound(to: UInt8.self)
            for x in 0..<10 { row[x] = 1; confidences[x] = x == 4 ? 2 : 0 }
        }
        CVPixelBufferUnlockBaseAddress(d, []); CVPixelBufferUnlockBaseAddress(c, [])
        let k = simd_float3x3(SIMD3(10, 0, 0), SIMD3(0, 10, 0), SIMD3(5, 3, 1))
        let points = DepthAwareness.points(depth: d, confidence: c, imageResolution: [10, 6], intrinsics: k, camera: matrix_identity_float4x4)
        XCTAssertEqual(points.count, 3)
        XCTAssertTrue(points.allSatisfy { abs($0.x + 0.1) < 0.001 && $0.z == -1 })
    }

    func testApproachNeedsRepeatedEvidenceAndHasCooldown() {
        var detector = ProximityReflex()
        XCTAssertNil(detector.observe(point: [0.4, 0.1, 0], actor: .zero, radius: 0.08, now: 0))
        XCTAssertNil(detector.observe(point: [0.35, 0.1, 0], actor: .zero, radius: 0.08, now: 0.1))
        XCTAssertNotNil(detector.observe(point: [0.30, 0.1, 0], actor: .zero, radius: 0.08, now: 0.2))
        XCTAssertNil(detector.observe(point: [0.25, 0.1, 0], actor: .zero, radius: 0.08, now: 0.3))
        XCTAssertNil(detector.observe(point: [0.20, 0.1, 0], actor: .zero, radius: 0.08, now: 0.4))
    }

    func testStaticRetreatingAndDiscontinuousSamplesDoNotTrigger() {
        for values: [Float] in [[0.2, 0.2, 0.2, 0.2], [0.2, 0.23, 0.26, 0.3], [0.6, 0.1, 0.6, 0.1]] {
            var detector = ProximityReflex()
            for (index, x) in values.enumerated() {
                XCTAssertNil(detector.observe(point: [x, 0.1, 0], actor: .zero, radius: 0.08, now: Double(index) * 0.1))
            }
        }
        var detector = ProximityReflex()
        _ = detector.observe(point: [0.4, 0.1, 0], actor: .zero, radius: 0.08, now: 0)
        _ = detector.observe(point: [0.35, 0.1, 0], actor: .zero, radius: 0.08, now: 0.1)
        XCTAssertNil(detector.observe(point: nil, actor: .zero, radius: 0.08, now: 0.2))
        XCTAssertNil(detector.observe(point: [0.2, 0.1, 0], actor: .zero, radius: 0.08, now: 0.3))
    }

    func testPhoneMovementAndActorMovementAreNotObstacleVelocity() {
        var detector = ProximityReflex()
        for i in 0..<4 {
            XCTAssertNil(detector.observe(point: [0.3, 0.1, 0], actor: [Float(i) * 0.02, 0, 0], radius: 0.08, now: Double(i) * 0.1))
        }
    }

    func testFloorAndIsolatedNoiseAreExcludedAndEscapeRouteSwept() {
        let floor: [SIMD3<Float>] = [[0.1, 0, 0], [0.11, 0.01, 0], [0.12, 0, 0]]
        XCTAssertNil(ProximityReflex.nearestCluster(points: floor + [[0.1, 0.1, 0]], feet: .zero, height: 0.12, radius: 0.08))
        let obstacle: [SIMD3<Float>] = [[0.2, 0.1, 0], [0.21, 0.11, 0], [0.22, 0.1, 0]]
        XCTAssertNotNil(ProximityReflex.nearestCluster(points: floor + obstacle, feet: .zero, height: 0.12, radius: 0.08))
        XCTAssertFalse(ProximityReflex.routeClear(points: obstacle, start: .zero, end: [0.4, 0, 0], radius: 0.08, height: 0.12))
        XCTAssertTrue(ProximityReflex.routeClear(points: obstacle + floor, start: .zero, end: [-0.2, 0, 0], radius: 0.08, height: 0.12))
    }
}
