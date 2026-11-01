// macOS RealityKit integration check: actual travel over a frictional floor, then wall collision.
// From the project root:
// mkdir -p /tmp/cast-locomotion
// cp scripts/verify_locomotion.swift /tmp/cast-locomotion/main.swift
// swiftc Cast/CharacterPhysics.swift /tmp/cast-locomotion/main.swift -o /tmp/cast-locomotion/check
// /tmp/cast-locomotion/check
import AppKit
import RealityKit
import Combine
import simd
let app = NSApplication.shared
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
let view = ARView(frame: window.contentView!.bounds)
window.contentView = view; window.orderFront(nil)
var subscription: Cancellable?
Task { @MainActor in
    let stage = AnchorEntity(world: .zero)
    let floor = ModelEntity(mesh: .generateBox(size: [2, 0.05, 2]))
    floor.position.y = -0.025
    floor.generateCollisionShapes(recursive: false)
    floor.physicsBody = PhysicsBodyComponent(shapes: floor.collision!.shapes, mass: 1, material: .generate(friction: 0.6, restitution: 0), mode: .static)
    stage.addChild(floor)
    let actor = ModelEntity(mesh: .generateBox(size: [0.06, 0.12, 0.06]))
    let mesh = actor.model!
    actor.model = nil
    let visual = ModelEntity(); visual.model = mesh; visual.position.y = 0.06; actor.addChild(visual)
    actor.position = [-0.2, 0.01, 0]
    CharacterPhysics.configure(actor, bounds: BoundingBox(min: [-0.03, 0, -0.03], max: [0.03, 0.12, 0.03]), scale: 1, mode: .dynamic)
    stage.addChild(actor)
    let camera = PerspectiveCamera(); camera.look(at: .zero, from: [0, 0.5, 1], relativeTo: nil); stage.addChild(camera)
    view.scene.addAnchor(stage)
    var target = SIMD3<Float>(0.1, 0, 0)
    subscription = view.scene.subscribe(to: SceneEvents.Update.self) { event in
        actor.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        CharacterPhysics.drive(actor, delta: target - actor.position, deltaTime: Float(event.deltaTime))
    }
    try? await Task.sleep(for: .seconds(4))
    print("Travel from -0.2m toward +0.1m:", actor.position)
    guard actor.position.x > 0.06, actor.position.x < 0.13, abs(actor.position.y) < 0.04 else { exit(1) }
    let wall = ModelEntity(mesh: .generateBox(size: [0.05, 0.4, 1]))
    wall.position = [0.22, 0.2, 0]; wall.generateCollisionShapes(recursive: false)
    wall.physicsBody = PhysicsBodyComponent(shapes: wall.collision!.shapes, mass: 1, mode: .static); stage.addChild(wall)
    target = [0.5, 0, 0]
    try? await Task.sleep(for: .seconds(4))
    print("Blocked by wall at 0.22m:", actor.position)
    guard actor.position.x < 0.20, actor.position.x > 0.12 else { exit(2) }
    print("PASS: traverses floor and stays blocked by wall")
    exit(0)
}
app.run()
