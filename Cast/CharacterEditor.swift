import SwiftUI
import UniformTypeIdentifiers

struct CharacterPortrait: View {
    let character: CastCharacter
    var body: some View {
        if let asset = character.assetFilename, asset.hasPrefix("bundle:") {
            Image("Preview" + String(asset.dropFirst(7))).resizable().scaledToFit()
        } else {
            Image(systemName: "face.smiling").resizable().scaledToFit().padding(32).foregroundStyle(.secondary)
        }
    }
}

struct CharacterEditor: View {
    @ObservedObject var scene: CastScene
    @Environment(\.dismiss) private var dismiss
    @State private var editing: CastCharacter?
    @State private var deleting: CastCharacter?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if scene.roster.isEmpty {
                        ContentUnavailableView("Room for new friends", systemImage: "face.smiling")
                    } else {
                        Text("Little characters. Big personalities.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 152), spacing: 16)], spacing: 16) {
                            ForEach(scene.roster) { character in
                                VStack(spacing: 0) {
                                    Button { editing = character } label: {
                                        VStack(spacing: 8) {
                                            CharacterPortrait(character: character)
                                                .frame(height: 144).scaleEffect(1.2).accessibilityHidden(true)
                                            Text(character.name).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                                            Text(scene.placedRoster.contains(where: { $0.id == character.id }) ? "In your scene" : "Ready to join")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }.frame(maxWidth: .infinity).padding(.top, 16).padding(.horizontal, 12)
                                    }.buttonStyle(.plain).accessibilityLabel("Edit " + character.name)
                                    HStack {
                                        Button("Edit", systemImage: "pencil") { editing = character }.font(.caption)
                                        Spacer()
                                        Button(role: .destructive) { deleting = character } label: {
                                            Image(systemName: "trash").frame(width: 44, height: 44)
                                        }.accessibilityLabel("Delete " + character.name)
                                    }.padding(.leading, 16).padding(.trailing, 4).padding(.top, 8)
                                }
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                            }
                        }
                    }
                }.padding(24)
            }.background(Color(.systemGroupedBackground))
                .navigationTitle("Your cast")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(item: $editing) { character in CharacterDetails(scene: scene, character: character) }
                .alert("Delete \(deleting?.name ?? "character")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { character in
                    Button("Delete character", role: .destructive) {
                        scene.removeCharacter(character.id)
                        deleting = nil
                    }
                    Button("Cancel", role: .cancel) { deleting = nil }
                } message: { _ in Text("This removes them from your cast and the current scene.") }
        }
    }
}

struct CharacterDetails: View {
    @ObservedObject var scene: CastScene
    @Environment(\.dismiss) private var dismiss
    @State var character: CastCharacter
    @State private var showImporter = false
    @State private var error: String?

    private var proposed: [CastCharacter] { scene.roster.map { $0.id == character.id ? character : $0 } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CharacterPortrait(character: character).frame(height: 180).frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                Section("Their name") {
                    TextField("Name", text: $character.name)
                        .onChange(of: character.name) { _, value in character.name = String(value.prefix(24)) }
                    if !CommandValidation.validNames(proposed) {
                        Text("Choose a name nobody else in your cast has").font(.caption).foregroundStyle(.red)
                    }
                }
                Section("Personality") {
                    TextField("Personality", text: $character.personality, axis: .vertical)
                        .lineLimit(2...4)
                        .onChange(of: character.personality) { _, value in character.personality = String(value.prefix(240)) }
                }
                Section("Their look") {
                    Picker("Character", selection: $character.assetFilename) {
                        Text("Stand-in").tag(String?.none)
                        ForEach(CharacterLook.all) { look in Text(look.id).tag(Optional("bundle:" + look.id)) }
                        if let filename = character.assetFilename, !filename.hasPrefix("bundle:") { Text("Imported").tag(Optional(filename)) }
                    }
                    Button("Import a 3D character", systemImage: "cube") { showImporter = true }
                }
            }
            .navigationTitle("Edit character").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if scene.updateRoster(proposed) { dismiss() } }
                        .disabled(!CommandValidation.validNames(proposed))
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.usdz]) { result in
                do {
                    let url = try result.get()
                    // Existing importer validates and preserves the complete authored hierarchy.
                    character.assetFilename = try scene.stageImportedAsset(url)
                } catch { self.error = error.localizedDescription }
            }
            .alert("Couldn’t import character", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        }
    }
}
