import Testing
@testable import LanguageLearning

/// The Tier-1/2 on-device grading verdicts that drive the suggested FSRS rating.
/// (Tier 3 / Foundation Models is async + device-gated and not covered here.)
struct GraderServiceTests {

    private let grader = GraderService()   // defaults: 6000ms cutoff, 1 word / 2 edits for "minor"

    @Test func exactMatchFastIsPerfect() {
        let r = grader.grade(expected: "собака", actual: "собака",
                             acceptedAlternatives: [], responseTimeMs: 1_000)
        #expect(r.autoGrade == .perfect)
        #expect(r.tier == 1)
        #expect(r.autoGrade.suggestedRating == 4)
    }

    @Test func exactMatchSlowIsHesitant() {
        let r = grader.grade(expected: "собака", actual: "собака",
                             acceptedAlternatives: [], responseTimeMs: 9_000)
        #expect(r.autoGrade == .hesitant)
        #expect(r.tier == 1)
        #expect(r.autoGrade.suggestedRating == 3)
    }

    @Test func matchIsCaseAndPunctuationInsensitive() {
        let r = grader.grade(expected: "Собака", actual: "  собака!  ",
                             acceptedAlternatives: [], responseTimeMs: 1_000)
        #expect(r.autoGrade == .perfect)
        #expect(r.tier == 1)
    }

    @Test func acceptedAlternativeIsHesitantTier1() {
        let r = grader.grade(expected: "привет", actual: "здравствуйте",
                             acceptedAlternatives: ["Здравствуйте"], responseTimeMs: 1_000)
        #expect(r.autoGrade == .hesitant)
        #expect(r.tier == 1)
    }

    @Test func singleCharTypoIsMinor() {
        let r = grader.grade(expected: "собака", actual: "сабака",
                             acceptedAlternatives: [], responseTimeMs: 1_000)
        #expect(r.autoGrade == .minor)
        #expect(r.tier == 2)
        #expect(r.editedWords == 1)
        #expect(r.totalEdits == 1)
        #expect(r.autoGrade.suggestedRating == 2)
    }

    @Test func multiWordDifferenceIsWrong() {
        let r = grader.grade(expected: "добрый день", actual: "привет мир",
                             acceptedAlternatives: [], responseTimeMs: 1_000)
        #expect(r.autoGrade == .wrong)
        #expect(r.tier == 2)
        #expect(r.autoGrade.suggestedRating == 1)
    }

    @Test func emptyAnswerIsWrong() {
        let r = grader.grade(expected: "собака", actual: "",
                             acceptedAlternatives: [], responseTimeMs: 1_000)
        #expect(r.autoGrade == .wrong)
    }

    @Test func twoCharTypoStillMinorAtThreshold() {
        // "kuchen" -> "kuhen" is within 1 word / 2 edits.
        let r = grader.grade(expected: "kuchen", actual: "kuhen",
                             acceptedAlternatives: [], responseTimeMs: 1_000)
        #expect(r.autoGrade == .minor)
        #expect(r.totalEdits <= 2)
    }
}
