import XCTest
import RealityKit
@testable import Cast

final class CommandTests: XCTestCase {
    @MainActor func testActionPosesAnimateAllBundledSkeletonsAndReset() throws {
        for name in ["Felipe", "Alfred", "Jojo", "Todd", "Iggy"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "usdz"))
            let entity = try Entity.load(contentsOf: url)
            var models: [ModelEntity] = []
            func collect(_ node: Entity) {
                if let model = node as? ModelEntity, !model.jointTransforms.isEmpty { models.append(model) }
                for child in node.children { collect(child) }
            }
            collect(entity)
            let rest = models.map { $0.jointTransforms }
            let animator = CharacterAnimator(entity)
            XCTAssertGreaterThan(animator.jointCount, 0, name)
            for action in ["wave", "dance", "move", "jump", "inspect", "spar", "startle"] {
                animator.applyPose(action: action, time: 0.5, duration: 3)
                let changed = zip(models, rest).contains { model, original in
                    zip(model.jointTransforms, original).contains { abs(simd_dot($0.rotation.vector, $1.rotation.vector)) < 0.9999 }
                }
                XCTAssertTrue(changed, "\(name): \(action) must move its skeleton")
                animator.update(action: action, time: 0, duration: 3)
                XCTAssertGreaterThan(animator.activeAnimationCount, 0, "\(name): \(action) must play an animation")
                animator.reset()
                XCTAssertEqual(animator.activeAnimationCount, 0)
                for (model, original) in zip(models, rest) {
                    for (pose, initial) in zip(model.jointTransforms, original) {
                        XCTAssertEqual(pose.matrix, initial.matrix)
                    }
                }
            }
        }
    }

    @MainActor func testBundledCharactersLoadWithGeometry() throws {
        for name in ["Felipe", "Alfred", "Jojo", "Todd", "Iggy"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "usdz"))
            let entity = try Entity.load(contentsOf: url)
            let bounds = entity.visualBounds(relativeTo: nil)
            XCTAssertEqual(bounds.extents.y, 0.12, accuracy: 0.005, name)
            XCTAssertEqual(bounds.min.y, 0, accuracy: 0.005, name)
            XCTAssertEqual(bounds.center.x, 0, accuracy: 0.005, name)
            XCTAssertEqual(bounds.center.z, 0, accuracy: 0.005, name)
            XCTAssertTrue(bounds.extents.x.isFinite && bounds.extents.y.isFinite && bounds.extents.z.isFinite)
        }
    }

    @MainActor func testDeletingCharacterPersistsAndClearsSelection() {
        let saved = UserDefaults.standard.data(forKey: "cast.roster")
        defer { UserDefaults.standard.set(saved, forKey: "cast.roster") }
        let scene = CastScene()
        XCTAssertTrue(scene.updateRoster(CastCharacter.defaults))
        let id = scene.roster[0].id
        scene.selectedID = id
        scene.removeCharacter(id)
        XCTAssertNil(scene.selectedID)
        XCTAssertFalse(scene.roster.contains { $0.id == id })
        XCTAssertFalse(CastScene().roster.contains { $0.id == id })
        scene.removeCharacter(scene.roster[0].id)
        XCTAssertTrue(scene.roster.isEmpty)
        XCTAssertFalse(scene.isPlaced)
    }

    @MainActor func testRosterCanGrowBeyondTwoAndRetainsIdentities() {
        let saved = UserDefaults.standard.data(forKey: "cast.roster")
        defer { UserDefaults.standard.set(saved, forKey: "cast.roster") }
        let scene = CastScene()
        let proposed = CastCharacter.defaults + [CastCharacter(name: "Pip", personality: "Curious", assetFilename: "bundle:Todd", colour: 0)]
        XCTAssertTrue(scene.updateRoster(proposed))
        XCTAssertEqual(CastScene().roster.map(\.id), proposed.map(\.id))
        XCTAssertTrue(scene.updateRoster([]))
        XCTAssertTrue(scene.roster.isEmpty)
    }

    @MainActor func testLiveSceneSnapshotIncludesPlacedCharacters() async throws {
        let saved = UserDefaults.standard.data(forKey: "cast.roster")
        defer { UserDefaults.standard.set(saved, forKey: "cast.roster") }
        let scene = CastScene()
        XCTAssertTrue(scene.updateRoster(CastCharacter.defaults))
        _ = scene.start()
        await Task.yield()
        let data = try XCTUnwrap(scene.snapshot().data(using: .utf8))
        let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let characters = try XCTUnwrap(snapshot["characters"] as? [[String: Any]])
        XCTAssertEqual(characters.count, CastCharacter.defaults.count)
        for character in CastCharacter.defaults {
            let entry = try XCTUnwrap(characters.first { $0["id"] as? String == character.id.uuidString })
            XCTAssertEqual(entry["name"] as? String, character.name)
            XCTAssertEqual(entry["personality"] as? String, character.personality)
            XCTAssertEqual((entry["position_stage_metres"] as? [Double])?.count, 3)
        }
    }

    @MainActor func testEditingRosterPreservesScaleAndRotation() async {
        let saved = UserDefaults.standard.data(forKey: "cast.roster")
        defer { UserDefaults.standard.set(saved, forKey: "cast.roster") }
        let scene = CastScene()
        XCTAssertTrue(scene.updateRoster([CastCharacter.defaults[0]]))
        _ = scene.start()
        await Task.yield()
        let id = scene.roster[0].id
        scene.select(id)
        XCTAssertEqual(scene.selectedID, id)
        scene.setScale(1.7)
        scene.setRotation(65)
        var renamed = scene.roster
        renamed[0].name = "Pip"
        XCTAssertTrue(scene.updateRoster(renamed))
        scene.select(id)
        XCTAssertEqual(scene.selectedScale, 1.7, accuracy: 0.001)
        XCTAssertEqual(scene.selectedRotation, 65, accuracy: 0.001)
        scene.setScale(100)
        XCTAssertEqual(scene.selectedScale, 10)
        scene.setScale(.nan)
        XCTAssertEqual(scene.selectedScale, 10)
        scene.removeSelected()
        XCTAssertFalse(scene.roster.contains { $0.id == id })
        XCTAssertNil(scene.selectedID)
    }

    func testNonverbalVoicesAreShortBoundedAndStableAfterRename() {
        var character = CastCharacter.defaults[0]
        for mood in CharacterVoice.moods {
            let samples = CharacterVoice.samples(character: character, mood: mood)
            XCTAssertGreaterThan(samples.count, 2400)
            XCTAssertLessThan(samples.count, 24000)
            XCTAssertGreaterThan(samples.map { abs(Int($0)) }.max() ?? 0, 1000)
            XCTAssertLessThan(samples.map { abs(Int($0)) }.max() ?? 32767, 30000)
            XCTAssertEqual(samples.last, 0)
            let wave = CharacterVoice.wav(character: character, mood: mood)
            XCTAssertEqual(String(data: wave.prefix(4), encoding: .utf8), "RIFF")
            XCTAssertEqual(wave.count, 44 + samples.count * 2)
        }
        let original = CharacterVoice.samples(character: character, mood: "curious")
        character.name = "Renamed"
        XCTAssertEqual(original, CharacterVoice.samples(character: character, mood: "curious"))
        character.assetFilename = "bundle:Todd"
        XCTAssertNotEqual(original, CharacterVoice.samples(character: character, mood: "curious"))
    }

    func testSceneAwarenessUsesHysteresisAndNoticesChanges() {
        let id = UUID()
        var awareness = SceneAwareness()
        XCTAssertEqual(awareness.observe(cameraDistances: [id: 1.2], pairDistances: [:], light: 600).count, 1)
        XCTAssertTrue(awareness.observe(cameraDistances: [id: 1.1], pairDistances: [:], light: 550).isEmpty)
        XCTAssertEqual(awareness.observe(cameraDistances: [id: 0.6], pairDistances: ["pair": 0.3], light: 100).count, 3)
        XCTAssertTrue(awareness.observe(cameraDistances: [id: 0.7], pairDistances: ["pair": 0.4], light: 220).isEmpty)
        XCTAssertEqual(awareness.observe(cameraDistances: [id: 1.1], pairDistances: ["pair": 0.6], light: 500).count, 2)
    }

    func testSceneReactionGateRespectsLiveBusyAndCooldown() {
        var gate = SceneReactionGate()
        XCTAssertFalse(gate.admit(now: 0, ready: false, busy: false))
        XCTAssertTrue(gate.admit(now: 0, ready: true, busy: false))
        XCTAssertFalse(gate.admit(now: 9, ready: true, busy: false))
        XCTAssertFalse(gate.admit(now: 10, ready: true, busy: true))
        XCTAssertTrue(gate.admit(now: 11, ready: true, busy: false))
    }

    func testDynamicExpressionChangesSoundAndRejectsInvalidValues() {
        let character = CastCharacter.defaults[0]
        let neutral = CharacterVoice.samples(character: character, mood: "curious")
        let excited = VoiceExpression(pitch: 1.3, pace: 1.4, energy: 1.1)
        XCTAssertTrue(excited.isValid)
        XCTAssertLessThan(CharacterVoice.samples(character: character, mood: "curious", expression: excited).count, neutral.count)
        let invalid = VoiceExpression(pitch: .infinity, pace: 1, energy: 1)
        XCTAssertFalse(invalid.isValid)
        XCTAssertEqual(CharacterVoice.samples(character: character, mood: "curious", expression: invalid), neutral)
        var command = CharacterCommand(characterIDs: [character.id], action: "wave", direction: nil, distance: nil, speech: "happy")
        command.expression = invalid
        XCTAssertNotNil(CommandValidation.error(for: command, roster: [character]))
        command.expression = excited
        XCTAssertNil(CommandValidation.error(for: command, roster: [character]))
    }

    @MainActor func testPhysicsBodyHasGravitySolidCollisionsAndContinuousDetection() {
        let entity = ModelEntity()
        let bounds = BoundingBox(min: [-0.08, 0, -0.06], max: [0.08, 0.22, 0.06])
        XCTAssertFalse(CharacterPhysics.overlaps(position: .zero, bounds: bounds, scale: 3, otherPosition: [1, 0, 0], otherBounds: bounds, otherScale: 1))
        XCTAssertTrue(CharacterPhysics.overlaps(position: .zero, bounds: bounds, scale: 10, otherPosition: [1, 0, 0], otherBounds: bounds, otherScale: 1))
        CharacterPhysics.configure(entity, bounds: bounds, scale: 1, mode: .dynamic)
        XCTAssertEqual(entity.physicsBody?.mode, .dynamic)
        XCTAssertEqual(entity.physicsBody?.isAffectedByGravity, true)
        XCTAssertEqual(entity.physicsBody?.isContinuousCollisionDetectionEnabled, true)
        XCTAssertEqual(entity.physicsBody?.isRotationLocked.x, true)
        XCTAssertEqual(entity.collision?.filter.mask, .all)
        XCTAssertEqual(entity.collision?.shapes.count, 1)
        XCTAssertGreaterThanOrEqual(entity.collision!.shapes[0].bounds.extents.x, bounds.extents.x)
        XCTAssertEqual(entity.physicsBody!.massProperties.mass, 0.35, accuracy: 0.001)
        CharacterPhysics.configure(entity, bounds: bounds, scale: 2, mode: .kinematic)
        XCTAssertEqual(entity.physicsBody!.massProperties.mass, 2.8, accuracy: 0.001)
        CharacterPhysics.configure(entity, bounds: bounds, scale: 10, mode: .kinematic)
        XCTAssertEqual(entity.physicsBody!.massProperties.mass, 350, accuracy: 0.01)
        XCTAssertEqual(entity.physicsBody?.mode, .kinematic)
        XCTAssertEqual(entity.physicsBody?.isContinuousCollisionDetectionEnabled, false)
    }

    @MainActor func testPlacementClearanceAccountsForScaleAndDifferentSurfaces() {
        let bounds = BoundingBox(min: [-0.08, 0, -0.06], max: [0.08, 0.22, 0.06])
        XCTAssertFalse(CharacterPhysics.overlaps(position: .zero, bounds: bounds, scale: 3, otherPosition: [1, 0, 0], otherBounds: bounds, otherScale: 1))
        XCTAssertTrue(CharacterPhysics.overlaps(position: .zero, bounds: bounds, scale: 10, otherPosition: [1, 0, 0], otherBounds: bounds, otherScale: 1))
        XCTAssertFalse(CharacterPhysics.overlaps(position: .zero, bounds: bounds, scale: 1, otherPosition: [0.3, 0, 0], otherBounds: bounds, otherScale: 1))
        XCTAssertTrue(CharacterPhysics.overlaps(position: .zero, bounds: bounds, scale: 2, otherPosition: [0.3, 0, 0], otherBounds: bounds, otherScale: 1))
        XCTAssertFalse(CharacterPhysics.overlaps(position: .zero, bounds: bounds, scale: 1, otherPosition: [0, 0.5, 0], otherBounds: bounds, otherScale: 1))
    }

    @MainActor func testWalkingMovesImportedCharacterHierarchy() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Felipe", withExtension: "usdz"))
        let model = try Entity.load(contentsOf: url)
        let stage = AnchorEntity(world: .zero)
        let root = ModelEntity()
        root.addChild(model); stage.addChild(root)
        CharacterPhysics.configure(root, bounds: model.visualBounds(relativeTo: root), scale: 1, mode: .kinematic)
        let before = model.visualBounds(relativeTo: stage).center
        for _ in 0..<120 {
            root.position = CharacterPhysics.walkingStep(from: root.position, toward: [0.3, 0, 0], deltaTime: 1 / 60)
        }
        let after = model.visualBounds(relativeTo: stage).center
        XCTAssertEqual(after.x - before.x, 0.3, accuracy: 0.002)
        XCTAssertEqual(after.y, before.y, accuracy: 0.0001)
        XCTAssertEqual(root.physicsBody?.mode, .kinematic)
    }

    @MainActor func testSupportRecoveryAllowsJumpButCatchesSmallFall() {
        let safe = SIMD3<Float>(0.4, 0.7, -0.2)
        XCTAssertFalse(CharacterPhysics.needsSupportRecovery(position: safe + [0, 0.15, 0], safePosition: safe))
        XCTAssertFalse(CharacterPhysics.needsSupportRecovery(position: safe - [0, 0.02, 0], safePosition: safe))
        XCTAssertTrue(CharacterPhysics.needsSupportRecovery(position: safe - [0, 0.09, 0], safePosition: safe))
        XCTAssertTrue(CharacterPhysics.needsSupportRecovery(position: [.nan, 0, 0], safePosition: safe))
    }

    @MainActor func testWalkingControllerReachesDestinationWithoutOvershooting() {
        for rate: Float in [30, 60, 120] {
            var position = SIMD3<Float>(-0.2, 0.75, 0)
            let destination = SIMD3<Float>(0.1, 0.75, 0.2)
            for _ in 0..<Int(rate * 4) {
                let next = CharacterPhysics.walkingStep(from: position, toward: destination, deltaTime: 1 / rate)
                XCTAssertEqual(next.y, 0.75)
                XCTAssertLessThanOrEqual(simd_distance(next, position), 0.18 / rate + 0.000001)
                position = next
            }
            XCTAssertLessThan(simd_distance(position, destination), 0.0011)
        }
        XCTAssertEqual(CharacterPhysics.walkingStep(from: .zero, toward: [1, 0, 0], deltaTime: .nan), .zero)
    }

    @MainActor func testWalkingImpulseIsBoundedAndDoesNotOverrideGravity() {
        let force = CharacterPhysics.driveImpulse(delta: [1, 2, 0], velocity: [-10, -20, 0], mass: 0.35, deltaTime: 1 / 60)
        XCTAssertEqual(force.y, 0)
        XCTAssertGreaterThan(force.x, 0)
        XCTAssertLessThanOrEqual(simd_length(force), 0.071)
        XCTAssertEqual(CharacterPhysics.driveImpulse(delta: .zero, velocity: .zero, mass: 1, deltaTime: 1 / 60), .zero)
    }

    func testMeetingStopsBeforeOverlapAndBoundsEachStep() {
        let target = InteractionRules.meetingTarget(from: .zero, to: [1, 0, 0], separation: 0.3)
        XCTAssertEqual(target, SIMD3<Float>(0.25, 0, 0))
        let near = InteractionRules.meetingTarget(from: .zero, to: [0.4, 0, 0], separation: 0.3)!
        XCTAssertEqual(near.x, 0.1, accuracy: 0.001)
        XCTAssertEqual(InteractionRules.meetingTarget(from: .zero, to: [0.2, 0, 0], separation: 0.3), .zero)
        XCTAssertNil(InteractionRules.meetingTarget(from: .zero, to: [0.4, 0.3, 0], separation: 0.3))
    }

    func testAutonomyCannotMoveWithoutPlayOrInitiateSparring() {
        let id = UUID()
        func command(_ action: String) -> CharacterCommand {
            CharacterCommand(characterIDs: [id], action: action, direction: nil, distance: nil, speech: nil)
        }
        XCTAssertFalse(InteractionRules.allows([command("explore")], playing: false))
        XCTAssertTrue(InteractionRules.allows([command("explore"), command("inspect")], playing: true))
        XCTAssertFalse(InteractionRules.allows([command("spar")], playing: true))
        XCTAssertTrue(InteractionRules.allows([command("wave")], playing: false))
        XCTAssertFalse(InteractionRules.allows(Array(repeating: command("wave"), count: 3), playing: true))
    }

    func testMeetRequiresTwoDistinctKnownCharacters() {
        let roster = CastCharacter.defaults
        XCTAssertNil(CommandValidation.error(for: CharacterCommand(characterIDs: roster.map(\.id), action: "meet", direction: nil, distance: nil, speech: nil), roster: roster))
        XCTAssertNotNil(CommandValidation.error(for: CharacterCommand(characterIDs: [roster[0].id], action: "meet", direction: nil, distance: nil, speech: nil), roster: roster))
    }

    func testRenamingPreservesIdentity() {
        var roster = CastCharacter.defaults
        let id = roster[0].id
        roster[0].name = "Pip"
        XCTAssertNil(CommandValidation.error(for: CharacterCommand(characterIDs: [id], action: "wave", direction: nil, distance: nil, speech: "Hello"), roster: roster))
    }
    func testUnknownAndDuplicateTargetsRejected() {
        let roster = CastCharacter.defaults
        XCTAssertNotNil(CommandValidation.error(for: CharacterCommand(characterIDs: [UUID()], action: "wave", direction: nil, distance: nil, speech: nil), roster: roster))
        XCTAssertNotNil(CommandValidation.error(for: CharacterCommand(characterIDs: [roster[0].id, roster[0].id], action: "spar", direction: nil, distance: nil, speech: nil), roster: roster))
    }
    func testMovementBoundsAndPairValidation() {
        let roster = CastCharacter.defaults
        for distance: Float in [-1, 0, 2, .nan, .infinity] {
            XCTAssertNotNil(CommandValidation.error(for: CharacterCommand(characterIDs: [roster[0].id], action: "move", direction: "right", distance: distance, speech: nil), roster: roster))
        }
        XCTAssertNotNil(CommandValidation.error(for: CharacterCommand(characterIDs: [roster[0].id], action: "spar", direction: nil, distance: nil, speech: nil), roster: roster))
        XCTAssertNil(CommandValidation.error(for: CharacterCommand(characterIDs: roster.map(\.id), action: "spar", direction: nil, distance: nil, speech: nil), roster: roster))
    }
    func testNamesMustBeDistinct() {
        var roster = CastCharacter.defaults
        roster[1].name = " MILO "
        XCTAssertFalse(CommandValidation.validNames(roster))
        roster[1].name = ""
        XCTAssertFalse(CommandValidation.validNames(roster))
    }
    func testWalkResolvesToRouteOrDirectedMovement() {
        let id = CastCharacter.defaults[0].id
        let roam = CharacterCommand(characterIDs: [id], action: "walk", direction: nil, distance: nil, speech: nil)
        XCTAssertNil(CommandValidation.error(for: roam, roster: CastCharacter.defaults))
        XCTAssertEqual(roam.resolvedMovement.action, "explore")
        let directed = CharacterCommand(characterIDs: [id], action: "walk", direction: "right", distance: nil, speech: "happy")
        XCTAssertNil(CommandValidation.error(for: directed, roster: CastCharacter.defaults))
        XCTAssertEqual(directed.resolvedMovement.action, "move")
        XCTAssertEqual(directed.resolvedMovement.direction, "right")
        XCTAssertEqual(directed.resolvedMovement.distance, 0.15)
        XCTAssertEqual(directed.resolvedMovement.speech, "happy")
    }

    func testWalkStillRejectsInvalidDirectionAndDistance() {
        let id = CastCharacter.defaults[0].id
        for (direction, distance): (String?, Float?) in [("up", nil), ("right", 20), (nil, -.infinity), ("left", .nan)] {
            let command = CharacterCommand(characterIDs: [id], action: "walk", direction: direction, distance: distance, speech: nil)
            XCTAssertNotNil(CommandValidation.error(for: command, roster: CastCharacter.defaults))
        }
    }

}
