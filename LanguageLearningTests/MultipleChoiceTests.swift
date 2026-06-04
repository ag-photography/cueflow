import Testing
@testable import LanguageLearning

struct MultipleChoiceTests {
    // Deterministic "shuffle" so order is assertable.
    private let identity: ([String]) -> [String] = { $0 }

    @Test func alwaysIncludesCorrectAnswer() {
        let opts = MultipleChoice.options(correct: "собака", from: ["кошка", "птица", "рыба"],
                                          distractors: 3, shuffle: identity)
        #expect(opts.contains("собака"))
        #expect(opts.count == 4)
        #expect(Set(opts).count == 4)   // all distinct
    }

    @Test func deduplicatesAndExcludesCorrect() {
        let opts = MultipleChoice.options(correct: "да", from: ["да", "нет", "нет", "может"],
                                          distractors: 3, shuffle: identity)
        #expect(opts.filter { $0 == "да" }.count == 1)
        #expect(Set(opts).count == opts.count)
    }

    @Test func gracefullyHandlesTooFewCandidates() {
        let opts = MultipleChoice.options(correct: "привет", from: ["пока"],
                                          distractors: 3, shuffle: identity)
        #expect(opts.contains("привет"))
        #expect(opts.count == 2)        // correct + the one available distractor
    }

    @Test func capsAtRequestedDistractorCount() {
        let opts = MultipleChoice.options(correct: "a", from: ["b", "c", "d", "e", "f"],
                                          distractors: 3, shuffle: identity)
        #expect(opts.count == 4)
    }
}
