import AVFoundation

@MainActor final class CharacterVoicePlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var queue: [Data] = []
    private(set) var isPlaying = false
    var activityChanged: ((Bool) -> Void)?

    func play(character: CastCharacter, mood: String, expression: VoiceExpression = .neutral) {
        guard queue.count < 4 else { return }
        queue.append(CharacterVoice.wav(character: character, mood: mood, expression: expression))
        if !isPlaying { playNext() }
    }

    func stop() {
        queue.removeAll()
        player?.stop(); player = nil
        isPlaying = false
        activityChanged?(false)
    }

    private func playNext() {
        guard !queue.isEmpty else { stop(); return }
        let data = queue.removeFirst()
        do {
            let next = try AVAudioPlayer(data: data)
            player = next
            next.delegate = self
            next.volume = 0.75
            isPlaying = true
            activityChanged?(true)
            if !next.play() { stop() }
        } catch { stop() }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.playNext()
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in if self.player === player { self.stop() } }
    }
}
