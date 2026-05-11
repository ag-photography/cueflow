import AVFoundation

/// Wraps `AVSpeechSynthesizer` with best-available Russian voice selection.
/// Probes voices once and prefers `.premium` over `.enhanced` over `.default`.
/// Disk caching is deferred — playback is near-instant on modern iOS, and
/// caching only matters for the audio export use case which doesn't apply yet.
@MainActor
final class TTSService {
    static let shared = TTSService()

    private let synthesizer = AVSpeechSynthesizer()
    private(set) var bestRussianVoice: AVSpeechSynthesisVoice?

    init() {
        bestRussianVoice = Self.pickBestVoice(language: "ru-RU")
    }

    /// Speak the supplied Russian (or `language`-tagged) text. Cancels any
    /// utterance currently in progress so rapid taps don't queue up.
    func speak(_ text: String, language: String = "ru-RU") {
        guard !text.isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = (language == "ru-RU" ? bestRussianVoice : nil)
            ?? AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }

    /// Whether the device only has the default-quality Russian voice. Used to
    /// nudge the user to install the Enhanced voice from iOS Settings.
    var hasOnlyDefaultRussianVoice: Bool {
        guard let voice = bestRussianVoice else { return true }
        return voice.quality == .default
    }

    private static func pickBestVoice(language: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        return voices.max { lhs, rhs in
            qualityRank(lhs.quality) < qualityRank(rhs.quality)
        }
    }

    private static func qualityRank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
        switch q {
        case .premium: return 3
        case .enhanced: return 2
        case .default: return 1
        @unknown default: return 0
        }
    }
}
