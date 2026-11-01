import Foundation

/// Short, original nonverbal voices; no text-to-speech or network audio generation.
enum CharacterVoice {
    static let moods = ["curious", "happy", "excited", "effort", "confused", "sleepy"]

    static func samples(character: CastCharacter, mood: String, expression: VoiceExpression = .neutral) -> [Int16] {
        let expression = expression.isValid ? expression : .neutral
        // Identity, rather than display name, keeps a voice stable after renaming.
        let seed = character.id.uuidString.utf8.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 }
        let variation = 0.94 + Double(seed % 13) / 100
        let asset = character.assetFilename ?? ""
        let base: Double = asset.contains("Alfred") ? 190 : asset.contains("Jojo") ? 350 : asset.contains("Todd") ? 145 : 270
        let metallic: Double = asset.contains("Todd") ? 0.32 : asset.contains("Jojo") ? 0.22 : 0.10
        // Syllable pitch contours approximate hums, squeaks and small robotic grunts.
        let notes: [(Double, Double, Double)]
        switch mood {
        case "happy": notes = [(0.15, 1, 1.3), (0.22, 1.2, 1.05)]
        case "excited": notes = [(0.10, 1.1, 1.5), (0.10, 1.3, 1.7), (0.19, 1.5, 1.2)]
        case "effort": notes = [(0.18, 0.8, 0.65), (0.16, 1, 0.75)]
        case "confused": notes = [(0.24, 1, 0.8), (0.28, 0.85, 1.35)]
        case "sleepy": notes = [(0.55, 0.85, 0.55)]
        default: notes = [(0.42, 0.85, 1.4)]
        }
        let rate = 24000.0
        var output = [Int16]()
        var phase = 0.0
        for (rawDuration, start, end) in notes {
            let duration = rawDuration / expression.pace
            let count = Int(duration * rate)
            for index in 0..<count {
                let t = Double(index) / rate
                let progress = Double(index) / Double(count)
                let pitch = base * variation * expression.pitch * (start + (end - start) * progress) * (1 + 0.018 * sin(2 * .pi * 7 * t))
                phase += 2 * .pi * pitch / rate
                let envelope = min(1, t / 0.025) * min(1, (duration - t) / 0.055)
                let hum = sin(phase) + 0.32 * sin(2 * phase) + 0.12 * sin(3 * phase)
                let robot = metallic * sin(phase * 2.41 + 1.2 * sin(phase))
                let sample = (hum + robot) * envelope * 0.36 * expression.energy
                output.append(Int16(max(-1, min(1, sample)) * 32767))
            }
            output += Array(repeating: 0, count: 840)
        }
        // Tail keeps microphone capture paused briefly after the last audible sound.
        output += Array(repeating: 0, count: 3600)
        return output
    }

    static func wav(character: CastCharacter, mood: String, expression: VoiceExpression = .neutral) -> Data {
        let audio = samples(character: character, mood: mood, expression: expression)
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) { var n = value.littleEndian; withUnsafeBytes(of: &n) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { var n = value.littleEndian; withUnsafeBytes(of: &n) { data.append(contentsOf: $0) } }
        text("RIFF"); u32(UInt32(36 + audio.count * 2)); text("WAVE")
        text("fmt "); u32(16); u16(1); u16(1); u32(24000); u32(48000); u16(2); u16(16)
        text("data"); u32(UInt32(audio.count * 2))
        for sample in audio { u16(UInt16(bitPattern: sample)) }
        return data
    }
}
