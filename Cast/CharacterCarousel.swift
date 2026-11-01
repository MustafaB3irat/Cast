import SwiftUI

struct CharacterLook: Identifiable {
    let id: String
    var preview: String { "Preview" + id }
    static let all = ["Felipe", "Alfred", "Jojo", "Todd", "Iggy"].map { CharacterLook(id: $0) }
}

struct CharacterCarousel: View {
    @Binding var selection: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let width = min(280.0, geometry.size.width * 0.68)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(CharacterLook.all) { look in
                        Button {
                            withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) { selection = look.id }
                        } label: {
                            VStack(spacing: 8) {
                                AnimatedCharacterPortrait(character: CastCharacter(name: look.id, personality: "", assetFilename: "bundle:" + look.id, colour: 0), animated: selection == look.id)
                                    .padding(.horizontal, 8)
                                    .frame(height: 248)
                                    .accessibilityHidden(true)
                                Text(look.id).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                                Image(systemName: selection == look.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selection == look.id ? Color.accentColor : Color.secondary.opacity(0.4))
                                    .font(.body)
                            }
                            .padding(.vertical, 16)
                            .frame(width: width, height: 328)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(look.id)
                        .accessibilityAddTraits(selection == look.id ? .isSelected : [])
                        .accessibilityIdentifier("Look " + look.id)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(reduceMotion ? 1 : 1 - 0.18 * abs(phase.value))
                                .rotation3DEffect(.degrees(reduceMotion ? 0 : -24 * phase.value), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                                .offset(y: reduceMotion ? 0 : 16 * abs(phase.value))
                                .opacity(phase.isIdentity ? 1 : 0.72)
                        }
                        .id(look.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 12)
            }
            .contentMargins(.horizontal, (geometry.size.width - width) / 2, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selection, anchor: .center)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .accessibilityIdentifier("Character carousel")
        }
        .frame(height: 352)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

struct SpawnCharacterSheet: View {
    @ObservedObject var scene: CastScene
    @State private var selection: String? = "Felipe"
    @State private var name = ""
    @State private var error = ""
    @State private var savedID: UUID?
    @FocusState private var naming: Bool

    private var saved: [CastCharacter] {
        scene.roster.filter { c in !scene.placedRoster.contains { $0.id == c.id } }
    }
    private var selectedSaved: CastCharacter? { saved.first { $0.id == savedID } }
    private var resolvedName: String { scene.resolvedSpawnName(name, asset: selection ?? "Felipe") }
    private var valid: Bool {
        selectedSaved != nil || (selection != nil && CommandValidation.validNames(scene.roster + [CastCharacter(name: resolvedName, personality: "", assetFilename: nil, colour: 0)]))
    }
    private var duplicate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !valid
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Who’s joining?").font(.largeTitle.weight(.semibold))
                    }.padding(.horizontal, 24)

                    CharacterCarousel(selection: $selection)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(selectedSaved == nil ? "Name · optional" : "Back for more").font(.headline)
                            Spacer()
                            if selectedSaved != nil { Button("Create new") { savedID = nil; name = "" } }
                        }
                        if let character = selectedSaved {
                            Text(character.name).font(.title2.weight(.medium))
                        } else {
                            TextField(scene.resolvedSpawnName("", asset: selection ?? "Felipe"), text: $name)
                                .accessibilityIdentifier("Their name")
                                .font(.title3).padding(16)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                                .textInputAutocapitalization(.words).autocorrectionDisabled()
                                .focused($naming).submitLabel(.done)
                                .onSubmit { naming = false }
                                .onChange(of: name) { _, value in name = String(value.prefix(24)) }
                            if duplicate { Text("That name is already in your cast").font(.caption).foregroundStyle(.red) }
                        }
                    }.padding(.horizontal, 24)

                    if !saved.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Your cast").font(.headline).padding(.horizontal, 24)
                            ScrollView(.horizontal) {
                                HStack(spacing: 12) {
                                    ForEach(saved) { character in
                                        Button {
                                            savedID = character.id
                                            naming = false
                                            if let asset = character.assetFilename, asset.hasPrefix("bundle:") {
                                                selection = String(asset.dropFirst(7))
                                            }
                                        } label: {
                                            VStack(spacing: 8) {
                                                AnimatedCharacterPortrait(character: character, animated: savedID == character.id).frame(width: 64, height: 64)
                                                Text(character.name).font(.caption).lineLimit(1)
                                            }
                                            .frame(width: 80).padding(8)
                                            .background(savedID == character.id ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
                                        }.buttonStyle(.plain)
                                            .accessibilityLabel("Place " + character.name)
                                    }
                                }.padding(.horizontal, 24)
                            }.scrollIndicators(.hidden)
                        }
                    }
                    if !error.isEmpty { Text(error).font(.callout).foregroundStyle(.red).padding(.horizontal, 24) }
                }.padding(.top, 16).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                Button {
                    naming = false
                    let success: Bool
                    if let character = selectedSaved { success = scene.spawnSaved(character.id) }
                    else { success = scene.spawn(name: name, asset: selection ?? "Felipe") }
                    if !success { error = scene.status }
                } label: {
                    Text(selectedSaved.map { "Add " + $0.name } ?? "Add " + resolvedName)
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!valid)
                .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
                .background(.bar)
                .accessibilityIdentifier("Spawn character")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { scene.cancelSpawn() } }
                ToolbarItem(placement: .principal) { Text("Add to your cast").font(.headline) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selection) { _, new in
                error = ""
                if let character = selectedSaved, character.assetFilename != "bundle:" + (new ?? "") { savedID = nil }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
    }

    @ViewBuilder private func savedPortrait(_ character: CastCharacter) -> some View {
        if let asset = character.assetFilename, asset.hasPrefix("bundle:"), CharacterLook.all.contains(where: { "bundle:" + $0.id == asset }) {
            Image("Preview" + String(asset.dropFirst(7))).resizable().scaledToFit()
        } else { Image(systemName: "person.crop.square").font(.largeTitle).foregroundStyle(.secondary) }
    }
}
