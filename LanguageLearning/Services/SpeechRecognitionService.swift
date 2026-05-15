import Foundation
import AVFoundation
import Speech

/// On-device Russian speech recognition. Wraps `SFSpeechRecognizer` and an
/// `AVAudioEngine` capture pipeline. Emits the running transcription so the
/// UI can show the user what was heard, plus a hesitancy signal (time to first
/// recognized word + longest mid-utterance pause).
///
/// Privacy: forces `requiresOnDeviceRecognition = true`. If the user's device
/// doesn't have the on-device Russian model, recognition will fail rather
/// than fall back to the cloud — matches the project's on-device-only choice.
@MainActor
final class SpeechRecognitionService: ObservableObject {
    @Published private(set) var transcription: String = ""
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var lastError: String?

    private var recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private var recordingStart: Date?
    private var firstWordAt: Date?
    private var lastSpeechAt: Date?
    private var longestPauseSec: Double = 0
    private(set) var currentLocale: String = "ru_RU"

    init(localeIdentifier: String = "ru_RU") {
        self.currentLocale = localeIdentifier
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
    }

    /// Switch the recogniser to a different language. Cheap; just instantiates
    /// a new SFSpeechRecognizer for the new locale. No-op if already on this locale.
    func setLocale(_ localeIdentifier: String) {
        guard localeIdentifier != currentLocale else { return }
        currentLocale = localeIdentifier
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
    }

    /// Hesitancy: time before the first recognized word and the longest gap
    /// between subsequent recognizer updates. Captured during recording, valid
    /// once `stop()` returns.
    struct HesitancySignal {
        var startDelaySec: Double
        var longestPauseSec: Double
    }

    private(set) var hesitancy = HesitancySignal(startDelaySec: 0, longestPauseSec: 0)

    func requestAuthorization() async -> Bool {
        let speechAuthorized = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        let micAuthorized = await AVAudioApplication.requestRecordPermission()
        return speechAuthorized && micAuthorized
    }

    func start() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "Speech", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Sprachmodell für \(currentLocale) nicht verfügbar."])
        }

        // Reset state
        transcription = ""
        recordingStart = .now
        firstWordAt = nil
        lastSpeechAt = nil
        longestPauseSec = 0
        lastError = nil

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let now = Date.now
                    if self.firstWordAt == nil, !result.bestTranscription.formattedString.isEmpty {
                        self.firstWordAt = now
                    }
                    if let last = self.lastSpeechAt {
                        let pause = now.timeIntervalSince(last)
                        if pause > self.longestPauseSec { self.longestPauseSec = pause }
                    }
                    self.lastSpeechAt = now
                    self.transcription = result.bestTranscription.formattedString
                }
                if let error {
                    self.lastError = error.localizedDescription
                    self.stop()
                }
            }
        }
        isRecording = true
    }

    func clearTranscription() {
        transcription = ""
        lastError = nil
        hesitancy = HesitancySignal(startDelaySec: 0, longestPauseSec: 0)
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil

        let now = Date.now
        let startDelay = (firstWordAt ?? now).timeIntervalSince(recordingStart ?? now)
        hesitancy = HesitancySignal(
            startDelaySec: max(0, startDelay),
            longestPauseSec: longestPauseSec
        )
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
