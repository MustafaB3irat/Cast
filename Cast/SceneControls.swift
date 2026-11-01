import SwiftUI

struct SceneControls: View {
    @ObservedObject var scene: CastScene
    @ObservedObject var voice: LiveDirector
    var openActions: () -> Void
    @State private var connecting = false
    @State private var showLiveInfo = false

    private var hasCharacters: Bool {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--preview-scene-controls") { return true }
        #endif
        return scene.isPlaced && !scene.placedRoster.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !hasCharacters {
                Label("Add a character to get started", systemImage: "plus.circle")
                    .font(.headline)
                Text("Tap a scanned surface").font(.subheadline).foregroundStyle(.secondary)
                if scene.status != "Empty scene" && scene.status != "Ready" {
                    Text(scene.status).font(.caption).foregroundStyle(.secondary)
                }
            } else {
            HStack(spacing: 12) {
                Image(systemName: voice.isLive ? "waveform" : "mic")
                    .font(.title2).foregroundStyle(voice.isLive ? Color.accentColor : .primary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live mode").font(.headline)
                    Text(voice.status == "Voice off" ? "Voice off" : voice.status)
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(voice.isLive ? "End live" : "Go live") {
                    if voice.isLive { voice.disconnect() }
                    else {
                        connecting = true
                        Task { await voice.connect(roster: scene.roster); connecting = false }
                    }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(connecting)
            }

            if voice.isLive && hasCharacters {
                Text(scene.isPlaying ? voice.decisionStatus : "AI play paused")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !voice.caption.isEmpty && voice.isLive {
                Text(voice.caption).font(.subheadline).lineLimit(2)
            }

            if hasCharacters {
                Divider()
                HStack {
                    Text(scene.selectedID == nil ? "Your cast" : scene.selectedName).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(scene.isPlaying ? "Playing" : "\(scene.placedRoster.count) in the scene")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Button(scene.isPlaying ? "Pause" : "Play", systemImage: scene.isPlaying ? "pause.fill" : "play.fill") {
                        if !scene.isPlaying { voice.resumeSceneReactions() }
                        scene.togglePlay()
                    }
                    .disabled(!scene.tracking || scene.selectedID != nil)
                    Button("Actions", systemImage: "hand.wave") { openActions() }
                        .disabled(!scene.tracking)
                    Spacer(minLength: 0)
                    Button("Stop", systemImage: "stop.fill") { scene.stopAll(); voice.stopSpeech() }
                        .labelStyle(.iconOnly).accessibilityLabel("Stop")
                }
                .buttonStyle(.bordered).controlSize(.large)
            } else if voice.isLive {
                Button("Stop", systemImage: "stop.fill") { scene.stopAll(); voice.stopSpeech() }
                    .buttonStyle(.bordered)
            }

            Text(scene.status).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button { showLiveInfo = true } label: {
                    Label("Live uses microphone & scene data", systemImage: "info.circle")
                        .font(.caption2)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if voice.isLive {
                    Menu {
                        Toggle("React to surroundings", isOn: $voice.sceneReactionsEnabled)
                    } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 32) }
                        .accessibilityLabel("Live options")
                }
            }
            }
        }
        .padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        .sheet(isPresented: $showLiveInfo) {
            NavigationStack {
                List {
                    Section("While Live is on") {
                        Text("Your microphone audio and character scene data are sent to OpenAI. Camera images stay on your iPhone.")
                        Text("Live starts autonomous play after placement. OpenAI Decisions chooses actions from scanned routes, nearby characters and scene events. Pause stops autonomous play; voice commands remain available. Camera images are not sent.")
                        Text("Characters reply with little sounds generated on your phone. Sessions end after five minutes or when you leave the app.")
                    }
                    if voice.isLive { Toggle("React to surroundings", isOn: $voice.sceneReactionsEnabled) }
                }.navigationTitle("Live mode")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showLiveInfo = false } } }
            }.presentationDetents([.medium])
        }
    }
}

struct CharacterActionsSheet: View {
    @ObservedObject var scene: CastScene
    @ObservedObject var voice: LiveDirector
    @Environment(\.dismiss) private var dismiss
    @State private var target: UUID?
    @State private var partner: UUID?
    @State private var confirmClear = false
    private let actions = [("wave", "Wave", "hand.wave"), ("jump", "Jump", "arrow.up"), ("dance", "Dance", "music.note"), ("explore", "Explore", "figure.walk"), ("inspect", "Look around", "eyes"), ("move", "Step right", "arrow.right")]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(scene.placedRoster) { character in
                                Button {
                                    target = character.id
                                    partner = scene.placedRoster.first { $0.id != character.id }?.id
                                } label: {
                                    VStack(spacing: 8) {
                                        portrait(character).frame(width: 64, height: 64)
                                        Text(character.name).font(.subheadline.weight(.medium))
                                    }
                                    .frame(minWidth: 88).padding(12)
                                    .background(target == character.id ? Color.accentColor.opacity(0.12) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                                }.buttonStyle(.plain)
                                    .accessibilityAddTraits(target == character.id ? .isSelected : [])
                            }
                        }
                    }.scrollIndicators(.hidden)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(actions, id: \.0) { action in
                            Button { perform(action.0) } label: {
                                Label(action.1, systemImage: action.2)
                                    .font(.body.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                            }.buttonStyle(.plain)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        }
                    }.disabled(target == nil || !scene.tracking)

                    if let character = scene.placedRoster.first(where: { $0.id == target }) {
                        Button("Hear \(character.name)’s voice", systemImage: "speaker.wave.2") { voice.react("curious", character: character) }
                    }
                    if scene.placedRoster.count >= 2 {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Better together").font(.headline)
                            Picker("With", selection: $partner) {
                                ForEach(scene.placedRoster.filter { $0.id != target }) { character in
                                    Text(character.name).tag(Optional(character.id))
                                }
                            }.pickerStyle(.menu)
                            HStack {
                                Button("Say hello", systemImage: "hand.wave") { perform("meet", paired: true) }
                                Menu("More", systemImage: "ellipsis") {
                                    Button("Face each other") { perform("face_each_other", paired: true) }
                                    Button("Playful sparring") { perform("spar", paired: true) }
                                }
                            }.buttonStyle(.bordered).disabled(partner == nil || target == nil || !scene.tracking)
                        }
                    }
                }.padding(24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Actions").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Clear scene", role: .destructive) { confirmClear = true }
                    } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Scene options")
                }
            }
            .confirmationDialog("Remove every character from this scene?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear scene", role: .destructive) { voice.disconnect(); scene.resetStage(); dismiss() }
            }
            .onAppear {
                target = scene.selectedID ?? scene.placedRoster.first?.id
                partner = scene.placedRoster.first { $0.id != target }?.id
            }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }

    private func perform(_ action: String, paired: Bool = false) {
        guard let target else { return }
        var ids = [target]
        if paired { guard let partner, partner != target else { return }; ids.append(partner) }
        scene.status = scene.execute(CharacterCommand(characterIDs: ids, action: action, direction: action == "move" ? "right" : nil, distance: action == "move" ? 0.15 : nil, speech: nil))
        dismiss()
    }

    @ViewBuilder private func portrait(_ character: CastCharacter) -> some View {
        if let asset = character.assetFilename, asset.hasPrefix("bundle:") {
            Image("Preview" + String(asset.dropFirst(7))).resizable().scaledToFit()
        } else { Image(systemName: "person.crop.circle").font(.largeTitle).foregroundStyle(.secondary) }
    }
}
