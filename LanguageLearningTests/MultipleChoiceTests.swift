import Testing
@testable import LanguageLearning

struct MultipleChoiceTests {
    private func item(_ source: String, _ target: String, language: String = "ru",
                      alternatives: [String] = []) -> MultipleChoice.Item {
        .init(source: source, target: target, language: language, alternatives: alternatives)
    }

    @Test func excludesKnownSynonymsAndOverlappingMeanings() {
        let correct = item("Hallo / Guten Tag", "привет", alternatives: ["здравствуйте"])
        let result = MultipleChoice.options(correct: correct, from: [
            item("Begrüßung", "здравствуйте"), item("Guten Tag", "добрый день"),
            item("Hi", "привет!"), item("Tschüss", "пока")
        ], shuffle: identity)
        #expect(result == ["привет", "пока"])
    }

    @Test func reciprocalAlternativesCannotBeWrongOptions() {
        #expect(MultipleChoice.options(correct: item("Hallo", "привет"), from: [
            item("Hi", "здравствуй", alternatives: ["привет"])
        ], shuffle: identity).isEmpty)
    }

    @Test func noDistractorsMeansFallbackNotOneAnswerQuiz() {
        #expect(MultipleChoice.options(correct: item("Herbst", "осень"), from: [], shuffle: identity).isEmpty)
    }

    @Test func rejectsOtherLanguagesAndMissingMeanings() {
        #expect(MultipleChoice.options(correct: item("Herbst", "осень"), from: [
            item("Winter", "شتاء", language: "ar"), item("", "зима"), item("Winter", " ")
        ], shuffle: identity).isEmpty)
    }

    @Test func handlesArabicWithoutCollapsingDistinctLetters() {
        let result = MultipleChoice.options(correct: item("Herbst", "خريف", language: "ar"), from: [
            item("Winter", "شتاء", language: "ar"), item("Winter", " شتاء ", language: "ar")
        ], shuffle: identity)
        #expect(result == ["خريف", "شتاء"])
    }

    @Test func preservesCanonicalInflectedRussianAndAbstractTutorWords() {
        let result = MultipleChoice.options(correct: item("im Herbst", "осенью"), from: [
            item("trotzdem", "всё-таки"), item("Herbst", "осень")
        ], shuffle: identity)
        #expect(result == ["осенью", "всё-таки", "осень"])
    }

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
