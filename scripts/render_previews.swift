import AppKit
import RealityKit
import simd

// Render with the same USD/skinning/material loader as the iOS app.
// Only the camera is framed; authored model transforms and materials are untouched.
let app = NSApplication.shared
let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 720), styleMask: [.borderless], backing: .buffered, defer: false)
let view = ARView(frame: window.contentView!.bounds)
window.contentView = view
window.orderFront(nil)
view.environment.background = .color(.clear)
view.environment.lighting.intensityExponent = 0.5
Task { @MainActor in
    do {
        for name in ["Felipe", "Alfred", "Jojo", "Todd", "Iggy"] {
            view.scene.anchors.removeAll()
            let model = try await Entity(contentsOf: base.appendingPathComponent("Cast/Assets/Characters/\(name).usdz"))
            let bounds = model.visualBounds(relativeTo: nil)
            let root = AnchorEntity(world: .zero)
            root.addChild(model)
            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 32
            let center = bounds.center
            let distance = max(bounds.extents.y, bounds.extents.x * 720 / 640) * 2.5
            // Authored front is +Z. Keep the lens level with the centre: no downward pitch.
            camera.look(at: center, from: center + [0, 0, distance], upVector: [0, 1, 0], relativeTo: nil)
            root.addChild(camera)
            let light = DirectionalLight()
            light.light.intensity = 2200
            light.look(at: center, from: [-1, 2, 3], relativeTo: nil)
            root.addChild(light)
            view.scene.addAnchor(root)
            try await Task.sleep(for: .seconds(1))
            let snapshot: NSImage? = await withCheckedContinuation { continuation in
                view.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
            }
            guard let snapshot, let tiff = snapshot.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Render failed") }
            let folder = base.appendingPathComponent("Cast/Assets.xcassets/Preview\(name).imageset")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: folder.appendingPathComponent("preview.png"))
            let contents: [String: Any] = ["images": [["filename": "preview.png", "idiom": "universal"]], "info": ["author": "xcode", "version": 1]]
            try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("Contents.json"))
            print("Rendered \(name): \(bounds.extents)")
        }
        exit(0)
    } catch { print(error); exit(1) }
}
app.run()
