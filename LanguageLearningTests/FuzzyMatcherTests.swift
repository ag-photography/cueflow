import Testing
@testable import LanguageLearning

/// The grading pipeline rides entirely on these primitives, so they're the
/// highest-leverage thing to pin down.
struct FuzzyMatcherTests {

    // MARK: normalize

    @Test func normalizeLowercasesTrimsCollapsesAndStripsPunctuation() {
        #expect(FuzzyMatcher.normalize("  Hallo,  Welt!  ") == "hallo welt")
    }

    @Test func normalizeLowercasesCyrillic() {
        #expect(FuzzyMatcher.normalize("Привет!") == "привет")
    }

    @Test func normalizeIsIdempotent() {
        let once = FuzzyMatcher.normalize("Ja, gerne.")
        #expect(FuzzyMatcher.normalize(once) == once)
        #expect(once == "ja gerne")
    }

    @Test func normalizeUnifiesComposedAndDecomposedForms() {
        let composed = "café"                     // é as one scalar (U+00E9)
        let decomposed = "cafe\u{0301}"           // e + combining acute
        #expect(FuzzyMatcher.normalize(composed) == FuzzyMatcher.normalize(decomposed))
    }

    // MARK: levenshtein

    @Test func levenshteinKnownDistances() {
        #expect(FuzzyMatcher.levenshtein("kitten", "sitting") == 3)
        #expect(FuzzyMatcher.levenshtein("flaw", "lawn") == 2)
        #expect(FuzzyMatcher.levenshtein("same", "same") == 0)
    }

    @Test func levenshteinHandlesEmptyStrings() {
        #expect(FuzzyMatcher.levenshtein("", "abc") == 3)
        #expect(FuzzyMatcher.levenshtein("abc", "") == 3)
        #expect(FuzzyMatcher.levenshtein("", "") == 0)
    }

    // MARK: wordEditAnalysis

    @Test func wordEditAnalysisCountsPerWordWhenWordCountsMatch() {
        let r = FuzzyMatcher.wordEditAnalysis(expected: "der hund", actual: "der hand")
        #expect(r.editedWords == 1)
        #expect(r.totalEdits == 1)
    }

    @Test func wordEditAnalysisIgnoresIdenticalStrings() {
        let r = FuzzyMatcher.wordEditAnalysis(expected: "guten tag", actual: "guten tag")
        #expect(r.editedWords == 0)
        #expect(r.totalEdits == 0)
    }

    @Test func wordEditAnalysisFallsBackToStringDistanceOnDifferingWordCounts() {
        let r = FuzzyMatcher.wordEditAnalysis(expected: "ich gehe", actual: "ich gehe schnell")
        #expect(r.editedWords == 3)        // max(2, 3)
        #expect(r.totalEdits > 0)
    }

    // MARK: characterDiff

    @Test func characterDiffMarksAllMatchesForIdenticalInput() {
        let diff = FuzzyMatcher.characterDiff(expected: "abc", actual: "abc")
        #expect(diff.expected.count == 3)
        #expect(diff.actual.count == 3)
        #expect(mismatchCount(diff.actual) == 0)
    }

    @Test func characterDiffMarksASubstitution() {
        let diff = FuzzyMatcher.characterDiff(expected: "abc", actual: "abd")
        #expect(mismatchCount(diff.actual) == 1)
    }

    // MARK: stripGradingPunctuation

    @Test func stripGradingPunctuationKeepsCaseAndSpacing() {
        #expect(FuzzyMatcher.stripGradingPunctuation("Hallo, Welt!") == "Hallo Welt")
    }

    // MARK: helpers

    private func mismatchCount(_ ops: [FuzzyMatcher.DiffOp]) -> Int {
        ops.reduce(0) { acc, op in
            if case .mismatch = op { return acc + 1 }
            return acc
        }
    }
}
