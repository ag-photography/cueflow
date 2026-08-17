import AVFoundation

enum ReferenceAudioSource: Equatable, Sendable {
    case bundled(fileName: String)
    case synthesized(locale: String)
}

enum ReferenceAudioResolver {
    static func source(
        audioFileName: String?,
        locale: String,
        fileExists: (String) -> Bool
    ) -> ReferenceAudioSource {
        if let audioFileName, !audioFileName.isEmpty, fileExists(audioFileName) {
            return .bundled(fileName: audioFileName)
        }
        return .synthesized(locale: locale)
    }
}

/// One playback entry point for recorded references and system speech. Language
/// packs can gain human recordings incrementally without changing exercise UI.
@MainActor
final class ReferenceAudioService {
    static let shared = ReferenceAudioService()

    private var player: AVAudioPlayer?

    func play(text: String, locale: String, audioFileName: String? = nil, slow: Bool = false) {
        let source = ReferenceAudioResolver.source(
            audioFileName: audioFileName,
            locale: locale,
            fileExists: { Bundle.main.url(forResource: $0, withExtension: nil) != nil }
        )
        switch source {
        case .bundled(let fileName):
            guard let url = Bundle.main.url(forResource: fileName, withExtension: nil) else { return }
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                try session.setActive(true)
                let player = try AVAudioPlayer(contentsOf: url)
                player.enableRate = true
                player.rate = slow ? 0.72 : 1
                self.player = player
                player.play()
            } catch {
                TTSService.shared.speak(text, language: locale, rate: slow ? 0.68 : 0.9)
            }
        case .synthesized:
            TTSService.shared.speak(text, language: locale, rate: slow ? 0.68 : 0.9)
        }
    }

    func stop() {
        player?.stop()
        player = nil
        TTSService.shared.stop()
    }
}
