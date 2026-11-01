import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var scene = CastScene()
    @StateObject private var voice = LiveDirector()
    @Environment(\.scenePhase) private var phase
    @State private var showCast = false
    @State private var showSettings = false
    @State private var showActions = false
    @State private var showAdjustment = false
    @State private var editingCharacter: CastCharacter?

    var body: some View {
        ZStack {
            CastCamera(controller: scene).ignoresSafeArea()
            VStack {
                HStack {
                    Text("Cast").font(.title2.bold())
                    Spacer()
                    Button { showCast = true } label: {
                        Image("PreviewFelipe").resizable().scaledToFit().scaleEffect(1.7)
                            .frame(width: 28, height: 28).clipped()
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.accessibilityLabel("Characters")
                    Button("Settings", systemImage: "gearshape") { showSettings = true }.labelStyle(.iconOnly).frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
                Spacer()
                if let id = scene.pendingSavedID, let character = scene.roster.first(where: { $0.id == id }) {
                    HStack {
                        CharacterPortrait(character: character).frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Place \(character.name)").font(.headline)
                            Text(scene.status).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Cancel") { scene.cancelSavedPlacement() }
                    }
                    .padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
                } else if scene.selectedID != nil {
                    PlacementControls(scene: scene, voice: voice, adjust: { showAdjustment = true }, edit: {
                        editingCharacter = scene.roster.first { $0.id == scene.selectedID }
                    })
                } else {
                    SceneControls(scene: scene, voice: voice) { showActions = true }
                }


            }.padding()
        }
        .task {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--preview-cast") { showCast = true }
            if ProcessInfo.processInfo.arguments.contains("--preview-actions") { showActions = true }
            if ProcessInfo.processInfo.arguments.contains("--preview-character-picker") {
                scene.showingSpawn = true
            }
            #endif
        }
        .sheet(isPresented: $scene.showingSpawn, onDismiss: { scene.cancelSpawn() }) { SpawnCharacterSheet(scene: scene) }
        .sheet(isPresented: $showAdjustment) {
            NavigationStack {
                Form {
                    LabeledContent("Size", value: String(format: "%.2f×", scene.selectedScale))
                    Slider(value: Binding(get: { scene.selectedScale }, set: { scene.setScale($0) }), in: CharacterPhysics.scaleRange).accessibilityLabel("Character size")
                    if let feedback = scene.scaleFeedback { Text(feedback).font(.caption).foregroundStyle(.secondary) }
                    LabeledContent("Rotation", value: String(format: "%.0f°", scene.selectedRotation))
                    Slider(value: Binding(get: { scene.selectedRotation }, set: { scene.setRotation($0) }), in: -360...360).accessibilityLabel("Character rotation")
                }.navigationTitle(scene.selectedName)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAdjustment = false } } }
            }.presentationDetents([.medium])
        }
        .sheet(item: $editingCharacter) { character in CharacterDetails(scene: scene, character: character) }
        .sheet(isPresented: $showCast) { CharacterEditor(scene: scene) }
        .sheet(isPresented: $showSettings) { ConnectionSettings() }
        .sheet(isPresented: $showActions) {
            CharacterActionsSheet(scene: scene, voice: voice)
        }
        .onChange(of: voice.isLive) { _, live in scene.usesLiveDirector = live; if !live { scene.stopAll() } }
        .onChange(of: voice.sceneReactionsEnabled) { _, enabled in
            if !enabled { scene.stopAll(); voice.decisions.cancel() }
            else if voice.isLive, scene.isPlaced, scene.selectedID == nil, !scene.isPlaying { scene.togglePlay() }
        }
        .onChange(of: scene.isPlaced) { _, placed in if !placed { voice.disconnect(); scene.stopAll() } }
        .onChange(of: scene.roster) { _, roster in voice.updateRoster(roster) }
        .onChange(of: phase) { _, phase in if phase != .active { voice.disconnect(); scene.stopAll() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in voice.disconnect(); scene.stopAll() }
        .task {
            let stageController = scene
            let voiceController = voice
            voice.canConnect = { [weak stageController] in
                guard let stageController else { return false }
                return stageController.isPlaced && !stageController.placedRoster.isEmpty
            }
            voice.scene = { [weak stageController] in stageController?.snapshot() ?? "{}" }
            voice.playEnabled = { [weak stageController] in stageController?.isPlaying ?? false }
            voice.executeScene = { [weak stageController] command in stageController?.executeAutonomous(command) ?? "Scene unavailable" }
            voice.commandReady = { [weak stageController] command in stageController?.voiceCommandReady(command) ?? false }
            voice.execute = { [weak stageController] command in stageController?.execute(command) ?? "Scene unavailable" }
            scene.speak = { [weak voiceController] mood, character, expression in voiceController?.react(mood, character: character, expression: expression) }
            scene.sceneEvent = { [weak voiceController] event in voiceController?.observeScene(event) }
            voice.decisions.options = { [weak stageController] in stageController?.decisionOptions() ?? [] }
            voice.decisions.context = { [weak stageController] in stageController?.snapshot() ?? "{}" }
            voice.decisions.revision = { [weak stageController] in stageController?.autonomyRevision ?? 0 }
            voice.decisions.execute = { [weak stageController] command in stageController?.executeAutonomous(command) ?? "Scene unavailable" }
            scene.autonomyInterrupted = { [weak voiceController] in voiceController?.decisions.cancel() }
            voice.onReady = { [weak stageController, weak voiceController] in
                guard let stageController, voiceController?.sceneReactionsEnabled == true,
                      stageController.isPlaced, stageController.selectedID == nil, !stageController.isPlaying else { return }
                stageController.usesLiveDirector = true
                stageController.togglePlay()
            }
        }
    }


}

struct ConnectionSettings: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var hasKey = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("OpenAI connection") {
                    Text(hasKey ? "API key saved on this iPhone" : "No API key saved")
                    SecureField("OpenAI API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save key") {
                        do { try KeyStore.save(key); key = ""; hasKey = true; dismiss() }
                        catch { self.error = "Couldn’t save the key in Keychain." }
                    }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if hasKey { Button("Remove saved key", role: .destructive) { try? KeyStore.save(""); hasKey = false } }
                }
                Section {
                    Text("Personal prototype: your key is stored in this device’s Keychain and sent only to OpenAI. Live sessions use gpt-realtime-2.1 and end after five minutes or when you leave the app. API usage is billed to your OpenAI project.")
                    Text("Voice commands use OpenAI. Characters answer with their own little hums, chirps and robotic sounds, generated on your iPhone. They never speak words. You can interrupt their sounds with a new voice command. Stop always works locally.")
                }
            }
            .navigationTitle("Connection")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { hasKey = !KeyStore.read().isEmpty }
            .alert("Connection", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        }
    }
}
