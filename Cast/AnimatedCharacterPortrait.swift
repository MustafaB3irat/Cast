import SwiftUI
import RealityKit
import Combine

/// Decorative previews never start an AR session or modify the placed character.
struct AnimatedCharacterPortrait: View {
    let character: CastCharacter
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var visible = false
    @State private var ready = false

    var body: some View {
        ZStack {
            CharacterPortrait(character: character).opacity(ready ? 0 : 1)
            if animated && visible && !reduceMotion && phase == .active, let asset = character.assetFilename {
                CharacterPreviewRenderer(asset: asset, ready: $ready)
                    .id(asset)
                    .allowsHitTesting(false)
                    .onDisappear { ready = false }
            }
        }
        .onScrollVisibilityChange(threshold: 0.2) { visible = $0 }
        .onDisappear { visible = false }
        .accessibilityHidden(true)
    }
}

@MainActor private struct CharacterPreviewRenderer: UIViewRepresentable {
    let asset: String
    @Binding var ready: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> PortraitView {
        let view = PortraitView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.isUserInteractionEnabled = false
        view.isOpaque = false
        view.backgroundColor = .clear
        view.environment.background = .color(.clear)
        view.environment.lighting.intensityExponent = 0.5
        // Fade the renderer over the static fallback only after the complete model is loaded.
        view.alpha = 0
        context.coordinator.load(asset, into: view) { ready = true }
        return view
    }
    func updateUIView(_ view: PortraitView, context: Context) {}
    static func dismantleUIView(_ view: PortraitView, coordinator: Coordinator) {
        coordinator.task?.cancel()
        coordinator.subscription?.cancel()
        coordinator.animator?.reset()
        view.scene.anchors.removeAll()
    }

    final class Coordinator {
        var task: Task<Void, Never>?
        var subscription: Cancellable?
        var animator: CharacterAnimator?
        private var elapsed: Double = 0
        private var previousBeat = -1

        func load(_ asset: String, into view: PortraitView, onReady: @escaping () -> Void) {
            let url: URL?
            if asset.hasPrefix("bundle:") {
                url = Bundle.main.url(forResource: String(asset.dropFirst(7)), withExtension: "usdz")
            } else {
                url = URL.applicationSupportDirectory.appending(path: "CastAssets").appending(path: asset)
            }
            guard let url else { return }
            task = Task { @MainActor [weak self, weak view] in
                guard let model = try? await Entity(contentsOf: url), !Task.isCancelled,
                      let self, let view else { return }
                let bounds = model.visualBounds(relativeTo: nil)
                guard bounds.extents.y.isFinite, bounds.extents.y > 0 else { return }
                let anchor = AnchorEntity(world: .zero)
                let performer = Entity()
                performer.addChild(model)
                anchor.addChild(performer)
                let camera = PerspectiveCamera()
                camera.camera.fieldOfViewInDegrees = 32
                anchor.addChild(camera)
                view.portraitCamera = camera
                view.modelBounds = bounds
                view.frameCamera()
                let light = DirectionalLight()
                light.light.intensity = 2200
                light.look(at: bounds.center, from: bounds.center + [-1, 2, 3], relativeTo: nil)
                anchor.addChild(light)
                view.scene.addAnchor(anchor)
                let animator = CharacterAnimator(model)
                self.animator = animator
                // Each character starts on a different beat rather than moving in unison.
                self.elapsed = Double(asset.utf8.reduce(0) { $0 + Int($1) } % 3) * 3
                self.subscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self, performer, weak view] event in
                    guard let self else { return }
                    self.elapsed += min(event.deltaTime, 0.1)
                    let cycle = self.elapsed.truncatingRemainder(dividingBy: 9)
                    let beat = Int(cycle / 3)
                    let time = Float(cycle.truncatingRemainder(dividingBy: 3))
                    if beat != self.previousBeat {
                        animator.reset()
                        self.previousBeat = beat
                        animator.update(action: beat == 0 ? "wave" : beat == 1 ? "dance" : "idle", time: 0, duration: 2)
                    }
                    let envelope = max(0, sin(min(time / 2, 1) * .pi))
                    performer.orientation = simd_quatf(angle: beat == 1 ? sin(time * 6) * 0.10 * envelope : 0, axis: [0, 0, 1])
                    let hop = beat == 2 && time < 1 ? sin(time * .pi) * bounds.extents.y * 0.12 : 0
                    performer.position.y = max(0, hop)
                    if view?.alpha == 0 { view?.alpha = 1; onReady() }
                }
            }
        }
    }

    final class PortraitView: ARView {
        var portraitCamera: PerspectiveCamera?
        var modelBounds: BoundingBox?
        override func layoutSubviews() { super.layoutSubviews(); frameCamera() }
        func frameCamera() {
            guard let camera = portraitCamera, let box = modelBounds, bounds.width > 0, bounds.height > 0 else { return }
            let aspect = Float(bounds.height / bounds.width)
            // Keep a level front camera and extra space for hands and the little hop.
            let center = box.center + SIMD3<Float>(0, box.extents.y * 0.05, 0)
            let distance = max(box.extents.y * 1.2, box.extents.x * aspect * 1.5) * 2.2
            camera.look(at: center, from: center + [0, 0, distance], upVector: [0, 1, 0], relativeTo: nil)
        }
    }
}
