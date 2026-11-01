import Foundation

struct CastCharacter: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var personality: String
    var assetFilename: String?
    var colour: Int

    static let defaults = [
        CastCharacter(name: "Milo", personality: "Bold, playful and enthusiastic", assetFilename: "bundle:Felipe", colour: 0),
        CastCharacter(name: "Nova", personality: "Thoughtful, curious and witty", assetFilename: "bundle:Alfred", colour: 1)
    ]
}

struct VoiceExpression: Codable {
    var pitch: Double
    var pace: Double
    var energy: Double
    static let neutral = VoiceExpression(pitch: 1, pace: 1, energy: 1)
    var isValid: Bool {
        pitch.isFinite && pace.isFinite && energy.isFinite &&
        (0.75...1.4).contains(pitch) && (0.7...1.5).contains(pace) && (0.4...1.2).contains(energy)
    }
}

struct CharacterCommand: Codable {
    let characterIDs: [UUID]
    let action: String
    let direction: String?
    let distance: Float?
    let speech: String?
    var expression: VoiceExpression? = nil
}

struct CommandBatch: Codable { let actions: [CharacterCommand] }

enum CommandValidation {
    static let actions = ["move", "wave", "jump", "dance", "face_each_other", "spar", "speak", "stop", "meet", "explore", "inspect"]
    static let directions = ["left", "right", "forward", "back"]
    static func error(for command: CharacterCommand, roster: [CastCharacter]) -> String? {
        guard actions.contains(command.action) else { return "Unsupported action" }
        guard !command.characterIDs.isEmpty, command.characterIDs.count <= roster.count,
              Set(command.characterIDs).count == command.characterIDs.count,
              command.characterIDs.allSatisfy({ id in roster.contains { $0.id == id } }) else { return "Unknown or duplicate character" }
        if command.action == "move" {
            guard let direction = command.direction, directions.contains(direction),
                  let distance = command.distance, distance.isFinite, distance > 0, distance <= 0.4 else {
                return "Movement must have a valid direction and distance up to 0.4 metres"
            }
        }
        if ["spar", "face_each_other", "meet"].contains(command.action), command.characterIDs.count != 2 { return "This action needs two characters" }
        if let expression = command.expression, !expression.isValid { return "Voice expression is outside supported limits" }
        if let speech = command.speech, speech.count > 240 { return "Speech is too long" }
        return nil
    }

    static func validNames(_ roster: [CastCharacter]) -> Bool {
        let names = roster.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
        return names.allSatisfy { !$0.isEmpty && $0.count <= 24 } && Set(names).count == names.count
    }
}
