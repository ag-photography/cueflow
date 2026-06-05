import Testing
@testable import LanguageLearning

struct SprintMatcherTests {
    @Test func exactMatchAfterNormalization() {
        // Punctuation + case are stripped by FuzzyMatcher.normalize.
        #expect(SprintMatcher.matches(spokenTail: "Привет!", target: "привет"))
    }

    @Test func targetAtTailOfRunningTranscription() {
        // The recogniser streamed filler before the actual answer.
        #expect(SprintMatcher.matches(spokenTail: "эм доброе утро", target: "доброе утро"))
    }

    @Test func toleratesSmallMorphologySlip() {
        // One-character slip is within the edit budget.
        #expect(SprintMatcher.matches(spokenTail: "спасиба", target: "спасибо"))
    }

    @Test func rejectsWrongAnswer() {
        #expect(!SprintMatcher.matches(spokenTail: "до свидания", target: "доброе утро"))
    }

    @Test func emptyTailDoesNotMatch() {
        #expect(!SprintMatcher.matches(spokenTail: "", target: "привет"))
    }

    @Test func shortTargetIsNotMatchedByIncidentalSubstring() {
        // "да" hides at the end of "когда" — must NOT count as saying "да".
        #expect(!SprintMatcher.matches(spokenTail: "когда придёт автобус", target: "да"))
        // …but actually saying it does.
        #expect(SprintMatcher.matches(spokenTail: "ну да", target: "да"))
    }
}
