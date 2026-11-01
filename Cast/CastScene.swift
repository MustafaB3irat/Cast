import SwiftUI
import RealityKit
import ARKit
import Combine

struct CastCamera: UIViewRepresentable {
    let controller: CastScene
    func makeUIView(context: Context) -> ARView { controller.start() }
    func updateUIView(_ view: ARView, context: Context) {}
}

@MainActor final class CastScene: NSObject, ObservableObject, @preconcurrency ARSessionDelegate, UIGestureRecognizerDelegate {
    @Published var roster: [CastCharacter]
    @Published var status = "Empty scene"
    @Published var isPlaced = false
    @Published var tracking = false
    @Published private(set) var isPlaying = false
    var usesLiveDirector = false
    private(set) var autonomyRevision = 0
    var autonomyInterrupted: (() -> Void)?
    private var lastPlayDecision: TimeInterval = 0
    private var playTurn = 0
    @Published var showingSpawn = false
    @Published var selectedID: UUID?
    @Published var selectedScale: Float = 1
    @Published var selectedRotation: Float = 0
    @Published var movingSelection = false
    private var pendingPosition: SIMD3<Float>?
    private var dragTarget: UUID?
    private var dragOffset = SIMD3<Float>.zero
    private var gestureScale: Float = 1
    private var gestureRotation: Float = 0
    var placedRoster: [CastCharacter] { roster.filter { actors[$0.id] != nil } }
    var selectedName: String { roster.first { $0.id == selectedID }?.name ?? "Character" }
    var speak: ((String, CastCharacter, VoiceExpression) -> Void)?
    var sceneEvent: ((String) -> Void)?
    private var awareness = SceneAwareness()
    private var lastObservation: TimeInterval = 0
    private var view: ARView?
    private var stage: AnchorEntity?
    private var actors: [UUID: Actor] = [:]
    private var collisionSubscription: Cancellable?
    private var planeBodies: [UUID: AnchorEntity] = [:]
    private var lastCollisionSound: TimeInterval = 0
    private var previousTime: TimeInterval?
    private var movementDeltaTime: Float = 1 / 60

    @MainActor private final class Actor {
        let root: ModelEntity
        let model: Entity
        var home: SIMD3<Float>
        var bodyBounds = BoundingBox(min: [-0.09, 0, -0.09], max: [0.09, 0.22, 0.09])
        var sparPartner: UUID?
        var meetingPartner: UUID?
        var lastPathCheck: TimeInterval = 0
        var lastImpulse: TimeInterval = 0
        var lastPosition: SIMD3<Float>?
        var travelSpeed: Float = 0
        var stalledTime: Float = 0
        var walking = false
        var suspended = false
        var target: SIMD3<Float>?
        var action = "idle"
        var started: TimeInterval = 0
        var ends: TimeInterval = 0
        let animator: CharacterAnimator
        var clip: AnimationPlaybackController?
        init(root: ModelEntity, model: Entity, home: SIMD3<Float>) { self.root = root; self.model = model; self.home = home; animator = CharacterAnimator(model) }
    }

    override init() {
        if let data = UserDefaults.standard.data(forKey: "cast.roster"),
           let saved = try? JSONDecoder().decode([CastCharacter].self, from: data), CommandValidation.validNames(saved) {
            roster = saved
        } else { roster = CastCharacter.defaults }
        super.init()
    }

    func updateRoster(_ proposed: [CastCharacter]) -> Bool {
        guard CommandValidation.validNames(proposed) else { return false }
        autonomyRevision += 1
        autonomyInterrupted?()
        roster = proposed.map { var c = $0; c.name = c.name.trimmingCharacters(in: .whitespacesAndNewlines); return c }
        if let data = try? JSONEncoder().encode(roster) { UserDefaults.standard.set(data, forKey: "cast.roster") }
        if stage != nil { rebuildCharacters() }
        return true
    }

    func stageImportedAsset(_ url: URL) throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard ["usdz", "reality"].contains(url.pathExtension.lowercased()) else { throw CocoaError(.fileReadUnsupportedScheme) }
        let directory = URL.applicationSupportDirectory.appending(path: "CastAssets")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = UUID().uuidString + "." + url.pathExtension.lowercased()
        let target = directory.appending(path: filename)
        try FileManager.default.copyItem(at: url, to: target)
        do { _ = try Entity.load(contentsOf: target) } catch { try? FileManager.default.removeItem(at: target); throw error }
        return filename
    }

    func importAsset(_ url: URL, for id: UUID) throws {
        let filename = try stageImportedAsset(url)
        var updated = roster
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].assetFilename = filename
        _ = updateRoster(updated)
    }

    func start() -> ARView {
        if let view { return view }
        let supported = ARWorldTrackingConfiguration.isSupported
        let view = ARView(frame: .zero, cameraMode: supported ? .ar : .nonAR, automaticallyConfigureSession: false)
        self.view = view
        // Lift indirect light without changing camera exposure or washing out textures.
        view.environment.lighting.intensityExponent = 0.6
        installEditingGestures(on: view)
        guard supported else {
            Task { @MainActor in self.showSimulatorPreview() }
            return view
        }
        view.session.delegate = self
        view.session.delegateQueue = .main
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        // A soft camera-relative fill keeps faces readable in dim rooms. Offset the
        // direction so the avatars retain shape instead of looking evenly unlit.
        let fillAnchor = AnchorEntity(.camera)
        let fill = DirectionalLight()
        fill.light.intensity = 1400
        fill.light.color = .white
        fill.look(at: .zero, from: [-1, 2, 2], relativeTo: nil)
        fillAnchor.addChild(fill)
        view.scene.addAnchor(fillAnchor)
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) { config.sceneReconstruction = .mesh }
        view.environment.sceneUnderstanding.options.insert(.occlusion)
        view.environment.sceneUnderstanding.options.insert(.collision)
        view.environment.sceneUnderstanding.options.insert(.physics)
        view.environment.sceneUnderstanding.options.insert(.receivesLighting)
        collisionSubscription = view.scene.subscribe(to: CollisionEvents.Began.self) { [weak self] event in
            self?.didCollide(event)
        }
        view.session.run(config)
        return view
    }

    private func installEditingGestures(on view: ARView) {
        let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(rotate(_:)))
        tap.require(toFail: pan)
        tap.require(toFail: pinch)
        tap.require(toFail: rotation)
        for gesture in [tap, pan, pinch, rotation] {
            gesture.delegate = self
            view.addGestureRecognizer(gesture)
        }
    }

    private func showSimulatorPreview() {
        guard let view else { return }
        view.environment.background = .color(.init(white: 0.14, alpha: 1))
        let root = AnchorEntity(world: .zero)
        stage = root
        view.scene.addAnchor(root)
        rebuildCharacters()
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 45
        camera.look(at: [0, 0.13, 0], from: [0, 0.48, 1.8], relativeTo: nil)
        root.addChild(camera)
        let light = DirectionalLight()
        light.light.intensity = 3000
        light.look(at: .zero, from: [1, 2, 2], relativeTo: nil)
        root.addChild(light)
        status = "Character preview · use an iPhone for AR"
    }

    private func surfacePosition(at point: CGPoint) -> SIMD3<Float>? {
        guard tracking, let view,
              let hit = view.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal).first else {
            status = "Move your phone slowly to scan this surface, then try again."
            return nil
        }
        let p = hit.worldTransform.columns.3
        return [p.x, p.y, p.z]
    }

    private func character(at point: CGPoint) -> UUID? {
        guard let view else { return nil }
        for hit in view.hitTest(point, query: .all, mask: CharacterPhysics.characters) {
            var entity: Entity? = hit.entity
            while let current = entity {
                if let id = actors.first(where: { $0.value.root === current })?.key { return id }
                entity = current.parent
            }
        }
        return nil
    }

    @objc private func tap(_ recognizer: UITapGestureRecognizer) {
        guard let view else { return }
        let point = recognizer.location(in: view)
        if movingSelection {
            if let position = surfacePosition(at: point), let id = selectedID, let actor = actors[id] {
                guard reposition(actor, to: position) else { return }
                movingSelection = false
                status = "Moved \(selectedName)"
            }
            return
        }
        if let id = character(at: point) { select(id); return }
        guard let position = surfacePosition(at: point) else { return }
        pendingPosition = position
        showingSpawn = true
    }

    func cancelSpawn() { pendingPosition = nil; showingSpawn = false }

    func spawnSaved(_ id: UUID) -> Bool {
        guard let character = roster.first(where: { $0.id == id }), actors[id] == nil else { return false }
        return place(character)
    }

    func resolvedSpawnName(_ name: String, asset: String) -> String {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed.isEmpty else { return typed }
        var candidate = asset
        var suffix = 2
        while roster.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).compare(candidate, options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == .orderedSame }) {
            candidate = "\(asset) \(suffix)"
            suffix += 1
        }
        return candidate
    }

    @discardableResult func spawn(name: String, asset: String) -> Bool {
        let character = CastCharacter(name: resolvedSpawnName(name, asset: asset), personality: "Playful and curious", assetFilename: "bundle:" + asset, colour: roster.count % 2)
        guard CommandValidation.validNames(roster + [character]) else { return false }
        return place(character)
    }

    private func place(_ character: CastCharacter) -> Bool {
        guard let position = pendingPosition, tracking, let view else { return false }
        if stage == nil {
            let root = AnchorEntity(world: .zero)
            view.scene.addAnchor(root)
            stage = root
        }
        let wasNew = !roster.contains(where: { $0.id == character.id })
        if wasNew { roster.append(character) }
        let root = ModelEntity()
        root.position = position + [0, 0.008, 0]
        if let camera = view.session.currentFrame?.camera.transform {
            root.orientation = simd_quatf(angle: atan2(camera.columns.3.x - position.x, camera.columns.3.z - position.z), axis: [0, 1, 0])
        }
        actors[character.id] = Actor(root: root, model: Entity(), home: position)
        isPlaced = true
        _ = updateRoster(roster)
        if let actor = actors[character.id], !hasRoom(for: actor, at: actor.root.position, scale: actor.root.scale.x) {
            actors.removeValue(forKey: character.id)?.root.removeFromParent()
            if wasNew { _ = updateRoster(roster.filter { $0.id != character.id }) }
            isPlaced = !actors.isEmpty
            status = "There isn’t enough room here. Tap a clearer spot."
            return false
        }
        select(character.id)
        cancelSpawn()
        return true
    }

    func select(_ id: UUID) {
        guard let actor = actors[id] else { return }
        stopAll()
        if let previous = selectedID, let old = actors[previous], previous != id { setDynamic(old) }
        selectedID = id
        updateSelectionIndicators()
        setMode(actor, to: .kinematic)
        actor.root.physicsMotion = PhysicsMotionComponent()
        selectedScale = actor.root.scale.x
        let forward = actor.root.orientation.act(SIMD3<Float>(0, 0, 1))
        selectedRotation = atan2(forward.x, forward.z) * 180 / .pi
        movingSelection = false
        status = "\(selectedName) selected"
    }

    func deselect() {
        if let id = selectedID, let actor = actors[id] { setDynamic(actor) }
        selectedID = nil; movingSelection = false
        updateSelectionIndicators()
    }
    func beginMove() { stopAll(); movingSelection = true; status = "Moving \(selectedName)" }
    func setScale(_ value: Float) {
        guard value.isFinite, let id = selectedID, let actor = actors[id] else { return }
        let scale = min(3, max(0.25, value))
        guard scale < actor.root.scale.x || hasRoom(for: actor, at: actor.root.position, scale: scale) else { status = "Move this character away from the others before enlarging it."; return }
        selectedScale = scale
        actor.root.scale = SIMD3(repeating: scale)
        CharacterPhysics.configure(actor.root, bounds: actor.bodyBounds, scale: scale, mode: .kinematic)
    }
    func setRotation(_ degrees: Float) {
        guard degrees.isFinite, let id = selectedID, let actor = actors[id] else { return }
        guard environmentHasRoom(actor, at: actor.root.position, scale: actor.root.scale.x) else {
            status = "Move the character clear of the nearby surface before rotating."; return
        }
        selectedRotation = degrees.truncatingRemainder(dividingBy: 360)
        actor.root.orientation = simd_quatf(angle: selectedRotation * .pi / 180, axis: [0, 1, 0])
    }
    func removeCharacter(_ id: UUID) {
        stopAll()
        if selectedID == id { deselect() }
        actors.removeValue(forKey: id)?.root.removeFromParent()
        _ = updateRoster(roster.filter { $0.id != id })
        isPlaced = !actors.isEmpty
        status = "Character removed"
    }

    func removeSelected() {
        guard let id = selectedID else { return }
        removeCharacter(id)
    }

    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        guard let view else { return }
        if gesture.state == .began {
            let point = gesture.location(in: view)
            let translation = gesture.translation(in: view)
            dragTarget = character(at: CGPoint(x: point.x - translation.x, y: point.y - translation.y))
            if let id = dragTarget {
                select(id)
                if let actor = actors[id], let hit = surfacePosition(at: CGPoint(x: point.x - translation.x, y: point.y - translation.y)) {
                    let delta = actor.root.position(relativeTo: nil) - hit
                    dragOffset = [delta.x, 0, delta.z]
                } else { dragOffset = .zero }
            }
        }
        defer { if [.ended, .cancelled, .failed].contains(gesture.state) { dragTarget = nil } }
        guard let id = dragTarget, let actor = actors[id],
              let position = surfacePosition(at: gesture.location(in: view)) else { return }
        stopAll()
        _ = reposition(actor, to: position + dragOffset)
    }
    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began {
            guard selectForGesture(gesture) else { return }
            stopAll(); gestureScale = selectedScale
        }
        guard tracking || !ARWorldTrackingConfiguration.isSupported else { return }
        setScale(gestureScale * Float(gesture.scale))
    }
    @objc private func rotate(_ gesture: UIRotationGestureRecognizer) {
        if gesture.state == .began {
            guard selectForGesture(gesture) else { return }
            stopAll(); gestureRotation = selectedRotation
        }
        guard tracking || !ARWorldTrackingConfiguration.isSupported else { return }
        setRotation(gestureRotation - Float(gesture.rotation) * 180 / .pi)
    }
    private func targetForGesture(_ gesture: UIGestureRecognizer) -> UUID? {
        guard let view else { return nil }
        if let id = character(at: gesture.location(in: view)) { return id }
        for index in 0..<gesture.numberOfTouches {
            if let id = character(at: gesture.location(ofTouch: index, in: view)) { return id }
        }
        return nil
    }

    private func selectForGesture(_ gesture: UIGestureRecognizer) -> Bool {
        if selectedID != nil { return true }
        guard let id = targetForGesture(gesture) else { return false }
        select(id)
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let pan = gestureRecognizer as? UIPanGestureRecognizer, let view {
            let point = pan.location(in: view)
            let translation = pan.translation(in: view)
            return character(at: CGPoint(x: point.x - translation.x, y: point.y - translation.y)) != nil
        }
        if gestureRecognizer is UIPinchGestureRecognizer || gestureRecognizer is UIRotationGestureRecognizer {
            return selectedID != nil || targetForGesture(gestureRecognizer) != nil
        }
        return true
    }

    private func updateSelectionIndicators() {
        for (id, actor) in actors { actor.root.findEntity(named: "Selection outline")?.isEnabled = id == selectedID }
    }

    private func selectionIndicator(bounds: BoundingBox) -> Entity {
        let outline = Entity()
        outline.name = "Selection outline"
        let width = max(0.08, bounds.extents.x + 0.04)
        let depth = max(0.08, bounds.extents.z + 0.04)
        let material = UnlitMaterial(color: .systemOrange)
        for sign: Float in [-1, 1] {
            let horizontal = ModelEntity(mesh: .generateBox(size: [width, 0.002, 0.003]), materials: [material])
            horizontal.position = [bounds.center.x, 0.004, bounds.center.z + sign * depth / 2]
            outline.addChild(horizontal)
            let vertical = ModelEntity(mesh: .generateBox(size: [0.003, 0.002, depth]), materials: [material])
            vertical.position = [bounds.center.x + sign * width / 2, 0.004, bounds.center.z]
            outline.addChild(vertical)
        }
        return outline
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIRotationGestureRecognizer) ||
        (gestureRecognizer is UIRotationGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer)
    }

    func resetStage() {
        stopAll()
        stage?.removeFromParent(); stage = nil
        actors.removeAll(); isPlaced = false
        awareness = SceneAwareness()
        deselect(); cancelSpawn()
        status = "Empty scene"
    }

    private func rebuildCharacters() {
        guard let stage else { return }
        let priorTransforms = actors.mapValues { $0.root.transform }
        for actor in actors.values { actor.root.removeFromParent() }
        actors.removeAll()
        for (index, character) in roster.enumerated() {
            guard priorTransforms[character.id] != nil || !ARWorldTrackingConfiguration.isSupported else { continue }
            let root = ModelEntity()
            let home = SIMD3<Float>(index == 0 ? -0.17 : 0.17, 0, 0)
            root.transform = priorTransforms[character.id] ?? Transform(translation: home)
            let model: Entity
            if let filename = character.assetFilename {
                do {
                    let url: URL
                    if filename.hasPrefix("bundle:") {
                        guard let bundled = Bundle.main.url(forResource: String(filename.dropFirst(7)), withExtension: "usdz") else { throw CocoaError(.fileNoSuchFile) }
                        url = bundled
                    } else { url = URL.applicationSupportDirectory.appending(path: "CastAssets").appending(path: filename) }
                    let imported = try Entity.load(contentsOf: url)
                    // Keep authored metres, feet pivot, skeleton, blend shapes and fur materials intact.
                    // The outer actor root alone carries user placement, yaw and scale.
                    model = Entity(); model.addChild(imported)
                } catch { status = "Couldn’t load \(character.name)’s asset. Using a stand-in."; model = Self.standIn(character.colour) }
            } else { model = Self.standIn(character.colour) }
            root.addChild(model)
            let physicalBounds = model.visualBounds(relativeTo: root)
            CharacterPhysics.configure(root, bounds: physicalBounds, scale: root.scale.x,
                                       mode: !ARWorldTrackingConfiguration.isSupported || !tracking || selectedID == character.id ? .kinematic : .dynamic)
            let outline = selectionIndicator(bounds: physicalBounds)
            outline.isEnabled = selectedID == character.id
            root.addChild(outline)
            let label = ModelEntity(mesh: .generateText(character.name, extrusionDepth: 0.0005, font: .systemFont(ofSize: 0.025, weight: .semibold)), materials: [UnlitMaterial(color: .white)])
            let bounds = label.visualBounds(relativeTo: label)
            label.position = [-bounds.extents.x / 2, physicalBounds.max.y + 0.025, 0]
            root.addChild(label)
            stage.addChild(root)
            let actor = Actor(root: root, model: model, home: root.position)
            actor.bodyBounds = physicalBounds
            actors[character.id] = actor
        }
    }

    private static func standIn(_ colour: Int) -> Entity {
        let root = Entity()
        let tint: UIColor = colour == 0 ? .systemOrange : .systemTeal
        let material = SimpleMaterial(color: tint, roughness: 0.45, isMetallic: false)
        let body = ModelEntity(mesh: .generateBox(size: [0.075, 0.10, 0.055], cornerRadius: 0.02), materials: [material])
        body.position.y = 0.09
        let head = ModelEntity(mesh: .generateSphere(radius: 0.045), materials: [material])
        head.position.y = 0.18
        root.addChild(body); root.addChild(head)
        for x: Float in [-0.018, 0.018] {
            let eye = ModelEntity(mesh: .generateSphere(radius: 0.006), materials: [UnlitMaterial(color: .black)])
            eye.position = [x, 0.185, 0.04]; root.addChild(eye)
            let foot = ModelEntity(mesh: .generateBox(size: [0.025, 0.03, 0.05], cornerRadius: 0.008), materials: [material])
            foot.position = [x, 0.015, 0.01]; root.addChild(foot)
        }
        return root
    }

    func snapshot() -> String {
        let info: [[String: Any]] = placedRoster.map { c in
            let actor = actors[c.id]
            let p = actor?.root.position ?? .zero
            return ["id": c.id.uuidString, "name": c.name, "position_stage_metres": [p.x, p.y, p.z],
                    "personality": c.personality,
                    "scale": actor?.root.scale.x ?? 1,
                    "clear_exploration_routes": actor.map { explorationOptions($0).clear.count } ?? 0,
                    "blocked_or_unscanned_routes": actor.map { explorationOptions($0).blocked.count } ?? 0,
                    "action": actor?.action ?? "not placed", "asset": c.assetFilename == nil ? "stand-in" : "imported"]
        }
        let state: [String: Any] = ["placed": isPlaced, "tracking": tracking, "play_enabled": isPlaying, "maximum_move_metres": 0.4, "characters": info,
                                    "geometry": "rigid body collisions against other characters and reconstructed room geometry; scanned support checked before walking; no general pathfinding"]
        return (try? JSONSerialization.data(withJSONObject: state)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    func execute(_ command: CharacterCommand) -> String {
        if let error = CommandValidation.error(for: command, roster: roster) { return error }
        if command.action == "stop" { stopAll(); return "Stopped" }
        guard isPlaced, tracking, let stage, let frame = view?.session.currentFrame else { return "Place the cast and restore tracking first" }
        guard !movingSelection else { return "Finish repositioning the selected character first" }
        deselect()
        autonomyRevision += 1
        let now = frame.timestamp
        let selected = command.characterIDs.compactMap { actors[$0] }
        guard selected.count == command.characterIDs.count else { return "One or more characters have not been placed" }
        guard selected.allSatisfy({ !$0.suspended }) else { return "Reposition the character on a scanned surface first" }
        if command.action == "jump" {
            guard selected.allSatisfy({ grounded($0) }) else { return "Jump needs a stable scanned surface under the character" }
            guard selected.allSatisfy({ hasRoom(for: $0, at: $0.root.position + [0, 0.1, 0], scale: $0.root.scale.x) }) else { return "There isn’t enough space above the character to jump" }
        }
        for actor in selected {
            finishWalking(actor)
            actor.animator.reset()
            actor.model.transform = .identity
            actor.stalledTime = 0
            actor.travelSpeed = 0
            actor.lastPosition = actor.root.position
            actor.started = now
        }
        // A fresh instruction supersedes previous destinations for its participants.
        for actor in selected { actor.target = nil; actor.meetingPartner = nil; actor.sparPartner = nil }
        if command.action == "meet" {
            let a = selected[0], b = selected[1]
            let spacing = meetingDistance(a, b)
            guard let target = InteractionRules.meetingTarget(from: a.root.position, to: b.root.position, separation: spacing),
                  supportedPath(from: a.root.position, to: target), hasRoom(for: a, at: target, scale: a.root.scale.x) else {
                return "They cannot reach each other across the currently scanned surface"
            }
            face(a, toward: b.root.position); face(b, toward: a.root.position)
            if simd_distance(target, a.root.position) < 0.015 {
                greet(command.characterIDs[0], command.characterIDs[1], now: now)
                status = "A friendly greeting"
                return "Started meet and greet"
            }
            else {
                a.target = target; a.meetingPartner = command.characterIDs[1]
                a.action = "move"; a.started = now; a.ends = now + 6
            }
        } else if command.action == "explore" || command.action == "inspect" {
            var performed = false
            for actor in selected {
                let options = explorationOptions(actor)
                if command.action == "explore", let target = options.clear.first {
                    actor.target = target; actor.action = "move"; actor.started = now; actor.ends = now + 5
                    performed = true
                } else if command.action == "inspect", let target = options.blocked.first {
                    face(actor, toward: target)
                    actor.action = "inspect"; actor.started = now; actor.ends = now + 3
                    performed = true
                }
            }
            if !performed { return command.action == "explore" ? "No clear walking route on the scanned surface" : "No nearby boundary to inspect" }
        } else if command.action == "move" {
            let right = SIMD3<Float>(frame.camera.transform.columns.0.x, 0, frame.camera.transform.columns.0.z)
            let forward = SIMD3<Float>(-frame.camera.transform.columns.2.x, 0, -frame.camera.transform.columns.2.z)
            var direction: SIMD3<Float>
            switch command.direction { case "left": direction = -right; case "right": direction = right; case "forward": direction = forward; default: direction = -forward }
            guard simd_length(direction) > 0.001 else { return "Point the phone toward the stage" }
            let worldDelta = simd_normalize(direction) * (command.distance ?? 0.15)
            let local = stage.convert(direction: worldDelta, from: nil)
            let targets = selected.map { $0.root.position + SIMD3(local.x, 0, local.z) }
            guard zip(selected, targets).allSatisfy({ supportedPath(from: $0.0.root.position, to: $0.1) }) else { return "Movement blocked: outside stage or missing surface support" }
            for (actor, target) in zip(selected, targets) { actor.target = target; actor.action = "move"; actor.ends = now + 5 }
        } else if command.action == "face_each_other" || command.action == "spar" {
            let a = selected[0], b = selected[1]
            face(a, toward: b.root.position); face(b, toward: a.root.position)
            if command.action == "spar" {
                guard abs(a.root.position.y - b.root.position.y) < 0.08,
                      supportedPath(from: a.root.position, to: b.root.position) else { return "Place both characters on the same connected surface to spar" }
                for (index, actor) in selected.enumerated() {
                    actor.sparPartner = command.characterIDs[1 - index]
                    actor.action = "spar"; actor.started = now; actor.ends = now + 6
                }
            }
        } else {
            for actor in selected {
                actor.action = command.action; actor.started = now; actor.ends = now + (command.action == "dance" ? 5 : 2)
                if command.action == "jump", grounded(actor) {
                    actor.root.applyLinearImpulse([0, CharacterPhysics.mass(scale: actor.root.scale.x) * 1.2, 0], relativeTo: nil)
                }
            }
        }
        let defaultMood: String
        switch command.action {
        case "jump", "dance": defaultMood = "excited"
        case "move", "spar": defaultMood = "effort"
        case "wave": defaultMood = "happy"
        default: defaultMood = "curious"
        }
        let mood = command.speech.flatMap { CharacterVoice.moods.contains($0) ? $0 : nil } ?? defaultMood
        for character in roster where command.characterIDs.contains(character.id) { speak?(mood, character, command.expression ?? .neutral) }
        status = "\(command.characterIDs.compactMap { id in roster.first { $0.id == id }?.name }.joined(separator: " & ")) · \(command.action.replacingOccurrences(of: "_", with: " "))"
        return "Started \(command.action) for \(selected.count) character(s)"
    }

    func togglePlay() {
        if isPlaying { stopAll(); return }
        guard tracking, isPlaced else { status = "Place characters on a scanned surface first."; return }
        deselect()
        isPlaying = true
        playTurn = 0
        lastPlayDecision = (view?.session.currentFrame?.timestamp ?? 0) - 10
        status = usesLiveDirector ? "AI play · characters choose their interactions" : "Local play · characters meet and explore"
    }

    func executeAutonomous(_ command: CharacterCommand) -> String {
        guard selectedID == nil, !showingSpawn, !movingSelection,
              actors.values.allSatisfy({ !$0.suspended }),
              command.characterIDs.allSatisfy({ actors[$0]?.action == "idle" }),
              InteractionRules.allows([command], playing: isPlaying) else {
            return "Interaction paused while editing or Play is off"
        }
        return execute(command)
    }

    func decisionOptions() -> [DecisionOption] {
        guard isPlaying, tracking, isPlaced, selectedID == nil, !showingSpawn, !movingSelection else { return [] }
        var options: [DecisionOption] = [.wait]
        let available = placedRoster.filter { actors[$0.id]?.action == "idle" && actors[$0.id]?.suspended == false }
        for character in available {
            guard let actor = actors[character.id] else { continue }
            func add(_ action: String, _ description: String, partner: UUID? = nil) {
                let ids = [character.id] + (partner.map { [$0] } ?? [])
                options.append(DecisionOption(value: ids.map(\.uuidString).joined(separator: ":") + ":" + action,
                    description: character.name + ": " + description,
                    command: CharacterCommand(characterIDs: ids, action: action, direction: nil, distance: nil, speech: nil)))
            }
            add("wave", "Greet with a wave and a happy chirp")
            add("speak", "React with a curious nonverbal sound")
            let routes = explorationOptions(actor)
            if !routes.clear.isEmpty { add("explore", "Walk a short step along a currently clear scanned route") }
            if !routes.blocked.isEmpty { add("inspect", "Turn curiously toward a blocked or unscanned boundary") }
            if grounded(actor), hasRoom(for: actor, at: actor.root.position, scale: actor.root.scale.x),
               hasRoom(for: actor, at: actor.root.position + [0, 0.10, 0], scale: actor.root.scale.x) {
                add("jump", "Make a playful small hop; grounded with overhead clearance")
                add("dance", "Do a short playful dance in this clear space")
            }
            for other in available where other.id != character.id {
                guard let b = actors[other.id],
                      let target = InteractionRules.meetingTarget(from: actor.root.position, to: b.root.position, separation: meetingDistance(actor, b)),
                      supportedPath(from: actor.root.position, to: target), hasRoom(for: actor, at: target, scale: actor.root.scale.x) else { continue }
                add("meet", "Walk toward " + other.name + " and greet; currently on a reachable scanned surface", partner: other.id)
            }
        }
        return options
    }

    private func meetingDistance(_ a: Actor, _ b: Actor) -> Float {
        let ar = simd_length(SIMD2(a.bodyBounds.extents.x, a.bodyBounds.extents.z)) * a.root.scale.x / 2
        let br = simd_length(SIMD2(b.bodyBounds.extents.x, b.bodyBounds.extents.z)) * b.root.scale.x / 2
        return ar + br + 0.065
    }

    private func greet(_ first: UUID, _ second: UUID, now: TimeInterval) {
        guard let a = actors[first], let b = actors[second] else { return }
        face(a, toward: b.root.position); face(b, toward: a.root.position)
        for id in [first, second] {
            guard let actor = actors[id], let character = roster.first(where: { $0.id == id }) else { continue }
            actor.target = nil; actor.meetingPartner = nil; brake(actor)
            actor.action = "wave"; actor.started = now; actor.ends = now + 2
            speak?("happy", character, .neutral)
        }
        sceneEvent?("Characters " + first.uuidString + " and " + second.uuidString + " reached greeting distance and exchanged waves and nonverbal sounds.")
    }

    private func explorationOptions(_ actor: Actor) -> (clear: [SIMD3<Float>], blocked: [SIMD3<Float>]) {
        guard tracking else { return ([], []) }
        var clear: [SIMD3<Float>] = []
        var blocked: [SIMD3<Float>] = []
        let forward = actor.root.orientation.act(SIMD3<Float>(0, 0, 1))
        let yaw = atan2(forward.x, forward.z)
        for offset: Float in [0, .pi / 4, -.pi / 4, .pi / 2, -.pi / 2, .pi] {
            let angle = yaw + offset
            var found = false
            for distance: Float in [0.30, 0.15, 0.08] {
                let target = actor.root.position + SIMD3<Float>(sin(angle), 0, cos(angle)) * distance
                if supportedPath(from: actor.root.position, to: target), hasRoom(for: actor, at: target, scale: actor.root.scale.x) {
                    clear.append(target); found = true; break
                }
            }
            if !found { blocked.append(actor.root.position + SIMD3<Float>(sin(angle), 0, cos(angle)) * 0.15) }
        }
        return (clear, blocked)
    }

    private func localPlayStep() {
        let available = placedRoster.filter { actors[$0.id]?.suspended == false }
        guard !available.isEmpty else { return }
        let actorIndex = (playTurn / 3) % available.count
        let first = available[actorIndex]
        var action = "explore"
        var ids = [first.id]
        if available.count > 1, playTurn % 3 == 0 {
            action = "meet"
            let others = available.filter { candidate in
                guard candidate.id != first.id, let a = actors[first.id], let b = actors[candidate.id],
                      let target = InteractionRules.meetingTarget(from: a.root.position, to: b.root.position, separation: meetingDistance(a, b)) else { return false }
                return supportedPath(from: a.root.position, to: target) && hasRoom(for: a, at: target, scale: a.root.scale.x)
            }.sorted {
                simd_distance(actors[$0.id]!.root.position, actors[first.id]!.root.position) < simd_distance(actors[$1.id]!.root.position, actors[first.id]!.root.position)
            }
            if let other = others.first { ids.append(other.id) } else { action = "explore" }
        } else if playTurn % 3 == 2 { action = "inspect" }
        playTurn += 1
        let result = executeAutonomous(CharacterCommand(characterIDs: ids, action: action, direction: nil, distance: nil, speech: nil))
        if !result.hasPrefix("Started") {
            _ = executeAutonomous(CharacterCommand(characterIDs: [first.id], action: "wave", direction: nil, distance: nil, speech: "curious"))
        }
    }

    private func face(_ actor: Actor, toward target: SIMD3<Float>) {
        let delta = target - actor.root.position
        actor.root.orientation = simd_quatf(angle: atan2(delta.x, delta.z), axis: [0, 1, 0])
    }

    private func supportedPath(from start: SIMD3<Float>, to end: SIMD3<Float>) -> Bool {
        guard let stage, let session = view?.session else { return false }
        let worldStart = stage.convert(position: start, to: nil) + SIMD3<Float>(0, 0.08, 0)
        let worldEnd = stage.convert(position: end, to: nil) + SIMD3<Float>(0, 0.08, 0)
        let delta = worldEnd - worldStart
        if simd_length(delta) > 0.001, let view {
            let hits = view.scene.raycast(origin: worldStart, direction: simd_normalize(delta), length: simd_length(delta), query: .all, mask: .all, relativeTo: nil)
            if hits.contains(where: { $0.entity.components[SceneUnderstandingComponent.self] != nil }) { return false }
        }
        for step in 1...5 {
            let local = start + (end - start) * Float(step) / 5
            let world = stage.convert(position: local, to: nil)
            let query = ARRaycastQuery(origin: world + [0, 0.15, 0], direction: [0, -1, 0], allowing: .existingPlaneGeometry, alignment: .horizontal)
            guard let hit = session.raycast(query).first, abs(hit.worldTransform.columns.3.y - world.y) < 0.05 else { return false }
        }
        return true
    }

    func stopAll() {
        autonomyRevision += 1
        autonomyInterrupted?()
        isPlaying = false
        for actor in actors.values {
            finishWalking(actor)
            actor.root.physicsMotion = PhysicsMotionComponent()
            actor.sparPartner = nil
            actor.meetingPartner = nil
            actor.target = nil; actor.action = "idle"; actor.model.position = .zero; actor.model.orientation = simd_quatf(); actor.clip?.stop(); actor.animator.reset()
        }
        if isPlaced { status = "Stopped" }
    }

    private func setMode(_ actor: Actor, to mode: PhysicsBodyMode) {
        guard var body = actor.root.physicsBody else { return }
        body.isContinuousCollisionDetectionEnabled = mode == .dynamic
        body.mode = mode
        actor.root.physicsBody = body
    }

    private func setDynamic(_ actor: Actor) {
        actor.root.physicsMotion = PhysicsMotionComponent()
        setMode(actor, to: tracking && !actor.suspended ? .dynamic : .kinematic)
    }

    private func hasRoom(for actor: Actor, at position: SIMD3<Float>, scale: Float) -> Bool {
        guard environmentHasRoom(actor, at: position, scale: scale) else { return false }
        return actors.values.filter { $0 !== actor }.allSatisfy {
            !CharacterPhysics.overlaps(position: position, bounds: actor.bodyBounds, scale: scale,
                                       otherPosition: $0.root.position, otherBounds: $0.bodyBounds, otherScale: $0.root.scale.x)
        }
    }

    private func environmentHasRoom(_ actor: Actor, at position: SIMD3<Float>, scale: Float) -> Bool {
        guard let view, ARWorldTrackingConfiguration.isSupported else { return true }
        let radius = simd_length(SIMD2(actor.bodyBounds.extents.x, actor.bodyBounds.extents.z)) * scale / 2 + 0.01
        let bottom = position.y + actor.bodyBounds.min.y * scale
        let height = max(0.025, actor.bodyBounds.extents.y * scale)
        var segments: [(SIMD3<Float>, SIMD3<Float>)] = []
        for fraction: Float in [0.25, 0.6, 0.95] {
            let centre = SIMD3<Float>(position.x, bottom + height * fraction, position.z)
            for offset: Float in [-0.65, 0, 0.65] {
                segments.append((centre + [-radius, 0, radius * offset], centre + [radius, 0, radius * offset]))
                segments.append((centre + [radius * offset, 0, -radius], centre + [radius * offset, 0, radius]))
            }
        }
        segments.append(([position.x, bottom + 0.02, position.z], [position.x, bottom + height + 0.005, position.z]))
        return segments.allSatisfy { start, end in
            let delta = end - start
            guard simd_length(delta) > 0.001 else { return true }
            let hits = view.scene.raycast(origin: start, direction: simd_normalize(delta), length: simd_length(delta), query: .all, mask: .all, relativeTo: nil)
            return !hits.contains { hit in
                var entity: Entity? = hit.entity
                while let current = entity {
                    if current.components[SceneUnderstandingComponent.self] != nil || current.name == "Cast detected surface" { return true }
                    entity = current.parent
                }
                return false
            }
        }
    }

    @discardableResult private func reposition(_ actor: Actor, to position: SIMD3<Float>) -> Bool {
        guard hasRoom(for: actor, at: position, scale: actor.root.scale.x) else {
            status = "Choose a spot with space around the character."; return false
        }
        setMode(actor, to: .kinematic)
        actor.root.physicsMotion = PhysicsMotionComponent()
        actor.root.setPosition(position + [0, 0.008, 0], relativeTo: nil)
        actor.suspended = false
        actor.home = actor.root.position
        return true
    }

    private func grounded(_ actor: Actor) -> Bool {
        guard let session = view?.session else { return false }
        let feet = actor.root.position(relativeTo: nil)
        let query = ARRaycastQuery(origin: feet + [0, 0.06, 0], direction: [0, -1, 0], allowing: .existingPlaneGeometry, alignment: .horizontal)
        let tolerance = max(0.035, 0.015 * actor.root.scale.x)
        if let hit = session.raycast(query).first,
           abs(hit.worldTransform.columns.3.y - feet.y) < tolerance { return true }
        // LiDAR collision meshes may support the feet beyond a detected plane boundary.
        guard let view, abs(actor.root.physicsMotion?.linearVelocity.y ?? 0) < 0.15 else { return false }
        return view.scene.raycast(origin: feet + [0, tolerance, 0], direction: [0, -1, 0],
                                  length: tolerance * 2, query: .all, mask: .all, relativeTo: nil).contains { hit in
            var entity: Entity? = hit.entity
            while let current = entity {
                if current.components[SceneUnderstandingComponent.self] != nil || current.name == "Cast detected surface" { return true }
                entity = current.parent
            }
            return false
        }
    }

    private func finishWalking(_ actor: Actor) {
        guard actor.walking else { return }
        actor.walking = false
        setDynamic(actor)
    }

    /// Walk by advancing the character controller, not by sliding a box along a rough LiDAR mesh.
    /// Each step is at most 9 mm; collision clearance and scanned support gate every advance.
    private func walk(_ actor: Actor, toward target: SIMD3<Float>) -> Bool {
        let next = CharacterPhysics.walkingStep(from: actor.root.position, toward: target, deltaTime: movementDeltaTime)
        guard supportedPath(from: actor.root.position, to: next),
              hasRoom(for: actor, at: next, scale: actor.root.scale.x) else { return false }
        if !actor.walking {
            setMode(actor, to: .kinematic)
            actor.root.physicsMotion = PhysicsMotionComponent()
            actor.walking = true
        }
        actor.root.position = next
        return true
    }

    private func drive(_ actor: Actor, toward target: SIMD3<Float>) {
        guard actor.root.physicsBody?.mode == .dynamic else { return }
        let worldDelta = stage?.convert(direction: target - actor.root.position, to: nil) ?? (target - actor.root.position)
        CharacterPhysics.drive(actor.root, delta: worldDelta, deltaTime: movementDeltaTime)
    }

    private func brake(_ actor: Actor) {
        guard let motion = actor.root.physicsMotion else { return }
        let mass = actor.root.physicsBody?.massProperties.mass ?? CharacterPhysics.mass(scale: actor.root.scale.x)
        actor.root.applyLinearImpulse(SIMD3<Float>(-motion.linearVelocity.x, 0, -motion.linearVelocity.z) * mass, relativeTo: nil)
    }

    private func didCollide(_ event: CollisionEvents.Began) {
        guard tracking, event.impulse > 0.015, let now = view?.session.currentFrame?.timestamp,
              now - lastCollisionSound > 1 else { return }
        let participants = actors.filter { $0.value.root === event.entityA || $0.value.root === event.entityB }
        guard !participants.isEmpty else { return }
        lastCollisionSound = now
        for id in participants.keys {
            if let character = roster.first(where: { $0.id == id }) {
                speak?("effort", character, VoiceExpression(pitch: 0.9, pace: 1.25, energy: 0.65))
            }
        }
        sceneEvent?("Physical contact involving character IDs: " + participants.keys.map(\.uuidString).joined(separator: ", "))
    }

    // LiDAR devices use RealityKit's reconstructed mesh. Other devices use the
    // detected plane boundary, extruded downward to make a finite static body.
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) { updatePlaneBodies(anchors) }
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) { updatePlaneBodies(anchors) }
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors { planeBodies.removeValue(forKey: anchor.identifier)?.removeFromParent() }
    }
    private func updatePlaneBodies(_ anchors: [ARAnchor]) {
        guard !ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh), let view else { return }
        for case let plane as ARPlaneAnchor in anchors {
            let geometry = plane.geometry
            guard geometry.boundaryVertices.count >= 3 else { continue }
            var points: [SIMD3<Float>] = []
            for index in 0..<geometry.boundaryVertices.count {
                let vertex = geometry.boundaryVertices[index]
                points.append(vertex); points.append(vertex - [0, 0.025, 0])
            }
            let shape = ShapeResource.generateConvex(from: points)
            let body = ModelEntity()
            body.name = "Cast detected surface"
            body.collision = CollisionComponent(shapes: [shape])
            body.physicsBody = PhysicsBodyComponent(shapes: [shape], mass: 1, mode: .static)
            let root = planeBodies[plane.identifier] ?? AnchorEntity(world: .zero)
            root.transform = Transform(matrix: plane.transform)
            for child in Array(root.children) { child.removeFromParent() }
            root.addChild(body)
            if planeBodies[plane.identifier] == nil { view.scene.addAnchor(root); planeBodies[plane.identifier] = root }
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let normal: Bool
        if case .normal = frame.camera.trackingState { normal = true } else { normal = false }
        if tracking != normal {
            tracking = normal
            if !normal {
                stopAll()
                for actor in actors.values { setMode(actor, to: .kinematic) }
                status = "Tracking paused. Look around the stage."
            } else {
                for (id, actor) in actors where id != selectedID { setDynamic(actor) }
            }
        }
        movementDeltaTime = min(0.05, max(0.001, Float(frame.timestamp - (previousTime ?? frame.timestamp - 1 / 60))))
        previousTime = frame.timestamp
        guard normal else { return }
        if frame.timestamp - lastObservation >= 1, selectedID == nil, !showingSpawn, !actors.isEmpty {
            lastObservation = frame.timestamp
            let cp = frame.camera.transform.columns.3
            let camera = SIMD3<Float>(cp.x, cp.y, cp.z)
            let distances = actors.mapValues { simd_distance($0.root.position(relativeTo: nil), camera) }
            let ids = actors.keys.sorted { $0.uuidString < $1.uuidString }
            var pairs: [String: Float] = [:]
            for (index, id) in ids.enumerated() {
                for other in ids.dropFirst(index + 1) {
                    if let a = actors[id], let b = actors[other] {
                        pairs[id.uuidString + " and " + other.uuidString] = simd_distance(a.root.position(relativeTo: nil), b.root.position(relativeTo: nil))
                    }
                }
            }
            let events = awareness.observe(cameraDistances: distances, pairDistances: pairs, light: frame.lightEstimate.map { Float($0.ambientIntensity) })
            if !events.isEmpty { sceneEvent?(events.prefix(4).joined(separator: " ")) }
        }
        if isPlaying, selectedID == nil, !showingSpawn, frame.timestamp - lastPlayDecision >= (usesLiveDirector ? 4 : 10),
           actors.values.allSatisfy({ $0.action == "idle" && !$0.suspended }) {
            lastPlayDecision = frame.timestamp
            if usesLiveDirector {
                sceneEvent?("PLAY_TICK: the cast is idle and Play is enabled. Choose a social interaction or explore/inspect a nearby scanned route based on the current state. Do not repeat the same gesture indefinitely.")
            } else { localPlayStep() }
        }
        for (id, actor) in actors {
            let t = Float(frame.timestamp - actor.started)
            let travelled = actor.root.position - (actor.lastPosition ?? actor.root.position)
            actor.lastPosition = actor.root.position
            let speed = simd_length(SIMD2(travelled.x, travelled.z)) / movementDeltaTime
            actor.travelSpeed += (speed - actor.travelSpeed) * min(1, movementDeltaTime * 12)
            if actor.action != "idle", frame.timestamp > actor.ends { finishWalking(actor); actor.action = "idle"; actor.target = nil; actor.model.position = .zero; actor.model.orientation = simd_quatf(); actor.animator.reset() }
            guard id != selectedID, !actor.suspended else { continue }
            // An incomplete scan can have holes. Recover instead of letting an avatar disappear.
            if actor.root.position.y < actor.home.y - 1 {
                setMode(actor, to: .kinematic)
                actor.root.physicsMotion = PhysicsMotionComponent()
                actor.root.position = actor.home + [0, 0.01, 0]
                actor.suspended = true
                actor.action = "idle"; actor.target = nil
                status = "Surface scan incomplete. Select and reposition the character."
                continue
            }
            if let target = actor.target {
                let delta = target - actor.root.position
                if simd_length(SIMD2(delta.x, delta.z)) < 0.012 {
                    finishWalking(actor)
                    actor.target = nil; actor.action = "idle"; brake(actor)
                    if let partnerID = actor.meetingPartner, let other = actors[partnerID],
                       simd_distance(actor.root.position, other.root.position) < meetingDistance(actor, other) + 0.06 {
                        greet(id, partnerID, now: frame.timestamp)
                    }
                    actor.meetingPartner = nil
                }
                else {
                    if frame.timestamp - actor.lastPathCheck > 0.3 {
                        actor.lastPathCheck = frame.timestamp
                        if !supportedPath(from: actor.root.position, to: target) {
                            finishWalking(actor)
                            actor.target = nil; actor.meetingPartner = nil; actor.action = "idle"; actor.animator.reset(); brake(actor)
                            status = "Walking stopped: surface support lost"
                            sceneEvent?("Character " + id.uuidString + " stopped because its scanned route is no longer clear or supported.")
                            continue
                        }
                    }
                    face(actor, toward: target)
                    if !walk(actor, toward: target) {
                        finishWalking(actor)
                        actor.target = nil; actor.meetingPartner = nil; actor.action = "idle"
                        actor.animator.reset(); brake(actor)
                        status = "Walking stopped: path blocked or surface missing"
                        sceneEvent?("Character " + id.uuidString + " stopped at an obstacle or unsupported surface.")
                        continue
                    }
                }
            }
            let visibleAction = actor.action == "move" && actor.travelSpeed < 0.008 ? "idle" : actor.action
            actor.animator.update(action: visibleAction, time: t, duration: Float(actor.ends - actor.started))
            switch actor.action {
            case "wave": actor.model.orientation = simd_quatf(angle: sin(t * 6) * 0.08, axis: [0, 0, 1])
            case "jump": break
            case "inspect": actor.model.orientation = simd_quatf(angle: sin(t * 3) * 0.3, axis: [0, 1, 0])
            case "dance":
                actor.model.orientation = simd_quatf(angle: sin(t * 7) * 0.15, axis: [0, 1, 0])
                if frame.timestamp - actor.lastImpulse > 0.65, grounded(actor) {
                    actor.lastImpulse = frame.timestamp
                    actor.root.applyLinearImpulse([0, CharacterPhysics.mass(scale: actor.root.scale.x) * 0.45, 0], relativeTo: nil)
                }
            case "spar":
                if let partnerID = actor.sparPartner, let other = actors[partnerID] {
                    face(actor, toward: other.root.position)
                    let phase: Float = id.uuidString < partnerID.uuidString ? 0 : .pi
                    if sin(t * 4 + phase) > 0.5 { drive(actor, toward: other.root.position) }
                    else { brake(actor) }
                }
            case "move": break
            default: actor.model.position.y = 0
            }
        }
    }
}
