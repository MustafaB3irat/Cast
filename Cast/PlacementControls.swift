import SwiftUI

/// Placement is a focused step: position first, then return to Live and Play.
struct PlacementControls: View {
    @ObservedObject var scene: CastScene
    @ObservedObject var voice: LiveDirector
    let adjust: () -> Void
    let edit: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let character = scene.roster.first(where: { $0.id == scene.selectedID }) {
                    CharacterPortrait(character: character)
                        .frame(width: 48, height: 48).scaleEffect(1.4).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(scene.selectedName).font(.title3.weight(.semibold))
                    Text(scene.movingSelection ? "Moving" : "Positioning")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Edit character", systemImage: "pencil") { edit() }
                    if voice.isLive {
                        Button("End live", systemImage: "mic.slash") { voice.disconnect() }
                    }
                    Button("Stop all", systemImage: "stop") { scene.stopAll(); voice.stopSpeech() }
                    Button("Delete character", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }.accessibilityLabel("Character options")
            }

            if let feedback = scene.scaleFeedback {
                Text(feedback).font(.caption).foregroundStyle(.secondary)
            }
            if scene.movingSelection {
                Text(scene.status).font(.caption).foregroundStyle(.secondary)
                Button("Cancel move") {
                    scene.movingSelection = false
                    scene.status = "\(scene.selectedName) selected"
                }.buttonStyle(.bordered).controlSize(.large)
            } else {
                HStack(spacing: 12) {
                    Button("New spot", systemImage: "arrow.up.and.down.and.arrow.left.and.right") { scene.beginMove() }
                        .disabled(!scene.tracking)
                    Button("Adjust", systemImage: "slider.horizontal.3") { adjust() }
                    Spacer(minLength: 0)
                }.buttonStyle(.bordered).controlSize(.large)
            }

            HStack {
                Text("\(scene.selectedScale, specifier: "%.2f")× · \(scene.selectedRotation, specifier: "%.0f")°")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityIdentifier("Selected transform")
                Spacer()
            }
            // Keep collision/tracking feedback visible; normal gesture guidance is already above.
            if !scene.status.hasSuffix(" selected") && !scene.status.hasPrefix("Moving ") && !scene.status.hasPrefix("Moved ") {
                Text(scene.status).font(.caption).foregroundStyle(.secondary)
            }
            Button {
                scene.deselect()
                if voice.isLive && voice.sceneReactionsEnabled {
                    voice.resumeSceneReactions()
                    scene.togglePlay()
                } else { scene.status = "Ready" }
            } label: {
                Label("Ready", systemImage: "checkmark")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
            }.buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(scene.movingSelection)
                .accessibilityHint("Finish positioning and return to Live and Play controls")
        }
        .padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        .alert("Delete this character?", isPresented: $confirmDelete) {
            Button("Delete character", role: .destructive) { scene.removeSelected() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("This removes \(scene.selectedName) from your cast and the scene.") }
    }

}
