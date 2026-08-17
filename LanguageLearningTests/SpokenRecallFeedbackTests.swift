import Testing
@testable import LanguageLearning

struct SpokenRecallFeedbackTests {
    @Test func clearRecognitionProducesClearSignal() {
        let feedback = SpokenRecallAnalyzer.analyze(
            expected: "Кофе пожалуйста",
            actual: "кофе, пожалуйста!",
            segments: [
                .init(text: "кофе", confidence: 0.92, timestamp: 0, duration: 0.4),
                .init(text: "пожалуйста", confidence: 0.88, timestamp: 0.5, duration: 0.7)
            ],
            startDelaySec: 0.8,
            longestPauseSec: 0.4
        )

        #expect(feedback.isClearSignal)
        #expect(feedback.notes.isEmpty)
    }

    @Test func reportsMissingLowConfidenceAndHesitationSeparately() {
        let feedback = SpokenRecallAnalyzer.analyze(
            expected: "Я хотел бы кофе",
            actual: "Я хотел кофе",
            segments: [.init(text: "хотел", confidence: 0.42, timestamp: 3, duration: 0.6)],
            startDelaySec: 3,
            longestPauseSec: 2.1
        )

        #expect(feedback.missingReferenceWords == ["бы"])
        #expect(feedback.lowConfidenceSegments == ["хотел"])
        #expect(feedback.delayedStart)
        #expect(feedback.longPause)
        #expect(!feedback.isClearSignal)
    }

    @Test func zeroConfidenceIsIgnoredBecauseSomeRecognizersDoNotReportIt() {
        let feedback = SpokenRecallAnalyzer.analyze(
            expected: "شكراً",
            actual: "شكراً",
            segments: [.init(text: "شكراً", confidence: 0, timestamp: 0, duration: 0.5)],
            startDelaySec: 0,
            longestPauseSec: 0
        )

        #expect(feedback.lowConfidenceSegments.isEmpty)
        #expect(feedback.isClearSignal)
    }
}
