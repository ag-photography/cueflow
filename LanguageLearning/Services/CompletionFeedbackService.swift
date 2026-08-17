import AVFoundation
import UIKit

/// CueFlow's restrained completion signature: a short, warm two-note chime
/// paired with a success haptic. It is reserved for meaningful completion
/// events, respects the device's Silent switch (`.ambient`), mixes with other
/// audio, and never carries information that the visible UI does not also show.
@MainActor
final class CompletionFeedbackService {
    static let shared = CompletionFeedbackService()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var playbackGeneration = UUID()

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func playCompletion() {
        guard UserDefaults.standard.object(forKey: "soundEffectsEnabled") as? Bool ?? true else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            if !engine.isRunning { try engine.start() }

            let generation = UUID()
            playbackGeneration = generation
            player.stop()
            player.scheduleBuffer(
                makeCompletionBuffer(),
                at: nil,
                options: .interrupts,
                completionCallbackType: .dataPlayedBack
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.playbackGeneration == generation else { return }
                    self.engine.stop()
                    try? AVAudioSession.sharedInstance().setActive(
                        false,
                        options: .notifyOthersOnDeactivation
                    )
                }
            }
            player.play()
        } catch {
            // The haptic and visible completion state still communicate success.
            // Audio must never block progression or surface an error dialog.
        }
    }

    private func makeCompletionBuffer() -> AVAudioPCMBuffer {
        let duration = 0.42
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        guard let samples = buffer.floatChannelData?[0] else { return buffer }

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / format.sampleRate
            let first = bellVoice(time: time, start: 0, frequency: 659.25, decay: 10.5)
            let second = bellVoice(time: time, start: 0.13, frequency: 987.77, decay: 8.5)
            samples[frame] = Float(min(0.72, first * 0.42 + second * 0.50))
        }
        return buffer
    }

    private func bellVoice(time: Double, start: Double, frequency: Double, decay: Double) -> Double {
        let localTime = time - start
        guard localTime >= 0 else { return 0 }
        let attack = min(1, localTime / 0.008)
        let envelope = attack * exp(-decay * localTime)
        let fundamental = sin(2 * .pi * frequency * localTime)
        let shimmer = 0.18 * sin(2 * .pi * frequency * 2.01 * localTime)
        return (fundamental + shimmer) * envelope
    }
}
