import AVFoundation

/// Wraps `AVSpeechSynthesizer` with best-available voice selection per language.
/// Probes voices once on init and prefers `.premium` over `.enhanced` over
/// `.default`. Disk caching is deferred — playback is near-instant on modern
/// iOS, and caching only matters for the audio export use case which doesn't
/// apply yet.
///
/// Activates a `.playback` audio session before each utterance so TTS plays
/// even when the device ringer switch is on silent — important for a
/// production-skill learning app where the user is expected to hear the
/// reference pronunciation.
@MainActor
final class TTSService {
    static let shared = TTSService()

    private let synthesizer = AVSpeechSynthesizer()
    private(set) var bestRussianVoice: AVSpeechSynthesisVoice?
    private(set) var bestGermanVoice: AVSpeechSynthesisVoice?

    init() {
        bestRussianVoice = Self.pickBestVoice(language: "ru-RU")
        bestGermanVoice = Self.pickBestVoice(language: "de-DE")
    }

    /// Speak the supplied text in the given language, optionally repeated
    /// `times` times with `gap` seconds between repeats. Cancels any utterance
    /// currently in progress so rapid taps don't queue up. Supports `ru-RU`
    /// and `de-DE` with cached best-quality voices; other locales fall back
    /// to the system default voice for that language.
    func speak(
        _ text: String,
        language: String = "ru-RU",
        times: Int = 1,
        gap: TimeInterval = 1.5,
        rate: Float = 0.9
    ) {
        guard !text.isEmpty, times > 0 else { return }
        configureAudioSessionForPlayback()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let voice = preferredVoice(for: language) ?? AVSpeechSynthesisVoice(language: language)
        for i in 0..<times {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * min(1.2, max(0.5, rate))
            if i > 0 {
                utterance.preUtteranceDelay = gap
            }
            synthesizer.speak(utterance)
        }
    }

    /// Cancel any in-flight utterance — called when the user moves to the
    /// next card so a half-finished reveal doesn't keep speaking over the
    /// new prompt.
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    /// Make sure the device plays TTS even if the ringer switch is on silent.
    /// The speech-recognition service flips the category to `.record` while
    /// listening; we need to flip it back before each utterance so reveal-time
    /// playback works regardless of how we got here.
    private func configureAudioSessionForPlayback() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: [])
        } catch {
            // Best-effort: if the session is locked by another route, speech
            // may still play. Don't crash or block the UI on this.
        }
    }

    /// Whether the device only has the default-quality Russian voice. Used to
    /// nudge the user to install the Enhanced voice from iOS Settings.
    var hasOnlyDefaultRussianVoice: Bool {
        guard let voice = bestRussianVoice else { return true }
        return voice.quality == .default
    }

    private func preferredVoice(for language: String) -> AVSpeechSynthesisVoice? {
        switch language {
        case "ru-RU": return bestRussianVoice
        case "de-DE": return bestGermanVoice
        default: return nil
        }
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
