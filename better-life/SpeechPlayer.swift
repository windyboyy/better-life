import Foundation
import AVFoundation

/// Speaks an English word aloud with the built-in offline British voice. Used by
/// the flashcard speaker button — playback is always user-initiated (tap), never
/// automatic.
final class SpeechPlayer {
    private let synthesizer = AVSpeechSynthesizer()

    init() {
        // Mix with (and briefly duck) any other audio, and stay audible even when
        // the ringer switch is silent.
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .default, options: [.mixWithOthers, .duckOthers]
        )
    }

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}
