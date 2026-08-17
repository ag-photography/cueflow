import Foundation

struct RecognizedSpeechSegment: Equatable, Sendable {
    let text: String
    let confidence: Float
    let timestamp: TimeInterval
    let duration: TimeInterval
}

struct SpokenRecallFeedback: Equatable, Sendable {
    let missingReferenceWords: [String]
    let lowConfidenceSegments: [String]
    let delayedStart: Bool
    let longPause: Bool

    var isClearSignal: Bool {
        missingReferenceWords.isEmpty
            && lowConfidenceSegments.isEmpty
            && !delayedStart
            && !longPause
    }

    var headline: String {
        isClearSignal ? "Klar erkannt" : "Sprechsignal"
    }

    var notes: [String] {
        var result: [String] = []
        if !missingReferenceWords.isEmpty {
            result.append("Nicht erkannt: \(missingReferenceWords.prefix(3).joined(separator: ", "))")
        }
        if !lowConfidenceSegments.isEmpty {
            result.append("Spracherkennung unsicher bei: \(lowConfidenceSegments.prefix(3).joined(separator: ", "))")
        }
        if delayedStart { result.append("Der Abruf begann mit einer längeren Pause.") }
        if longPause { result.append("In der Antwort lag eine längere Sprechpause.") }
        return result
    }
}

enum SpokenRecallAnalyzer {
    static func analyze(
        expected: String,
        actual: String,
        segments: [RecognizedSpeechSegment],
        startDelaySec: Double,
        longestPauseSec: Double
    ) -> SpokenRecallFeedback {
        let expectedWords = tokens(expected)
        var remainingActual = tokens(actual)
        var missing: [String] = []

        for expectedWord in expectedWords {
            if let index = remainingActual.firstIndex(of: expectedWord) {
                remainingActual.remove(at: index)
            } else {
                missing.append(expectedWord)
            }
        }

        let lowConfidence = segments
            .filter { $0.confidence > 0 && $0.confidence < 0.58 }
            .map(\.text)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .reduce(into: [String]()) { result, value in
                if !result.contains(value) { result.append(value) }
            }

        return SpokenRecallFeedback(
            missingReferenceWords: missing,
            lowConfidenceSegments: lowConfidence,
            delayedStart: startDelaySec > 2.5,
            longPause: longestPauseSec > 1.8
        )
    }

    private static func tokens(_ text: String) -> [String] {
        FuzzyMatcher.normalize(text)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }
}
