import Foundation

/// On-device grading for type-to-translate answers. Tier 1 is exact match
/// (including against the phrase's accepted-alternatives list). Tier 2 is a
/// fuzzy match — small edits in a single word are treated as a likely
/// morphology miss (`minor`), bigger edits or wrong word counts as `wrong`.
/// Tier 3 (Apple Foundation Models) lands in M6.
struct GraderService {
    /// Response time below this threshold turns a Tier 1 perfect match into the
    /// "fast and confident" auto-grade (FSRS Easy). Anything slower falls back
    /// to "hesitant" (FSRS Good).
    var fastResponseCutoffMs: Int = 6000

    /// At most this many edited words to still count as `minor` rather than `wrong`.
    var minorMaxEditedWords: Int = 1

    /// At most this many character edits across the edited word(s) for `minor`.
    var minorMaxTotalEdits: Int = 2

    func grade(
        expected: String,
        actual: String,
        acceptedAlternatives: [String],
        responseTimeMs: Int
    ) -> GradeResult {
        let normalizedExpected = FuzzyMatcher.normalize(expected)
        let normalizedActual = FuzzyMatcher.normalize(actual)

        if normalizedActual == normalizedExpected {
            let auto: AutoGrade = responseTimeMs <= fastResponseCutoffMs ? .perfect : .hesitant
            return GradeResult(
                autoGrade: auto,
                tier: 1,
                normalizedExpected: normalizedExpected,
                normalizedActual: normalizedActual,
                editedWords: 0,
                totalEdits: 0
            )
        }

        let normalizedAlternatives = acceptedAlternatives.map(FuzzyMatcher.normalize)
        if normalizedAlternatives.contains(normalizedActual) {
            return GradeResult(
                autoGrade: .hesitant,
                tier: 1,
                normalizedExpected: normalizedExpected,
                normalizedActual: normalizedActual,
                editedWords: 0,
                totalEdits: 0
            )
        }

        let analysis = FuzzyMatcher.wordEditAnalysis(
            expected: normalizedExpected,
            actual: normalizedActual
        )

        let isMinor = analysis.editedWords <= minorMaxEditedWords
            && analysis.totalEdits <= minorMaxTotalEdits

        return GradeResult(
            autoGrade: isMinor ? .minor : .wrong,
            tier: 2,
            normalizedExpected: normalizedExpected,
            normalizedActual: normalizedActual,
            editedWords: analysis.editedWords,
            totalEdits: analysis.totalEdits
        )
    }

    /// Tier-1/2 grade, then optionally consult the on-device foundation model
    /// to soften a `minor` or `wrong` verdict. Never promotes above `hesitant`.
    /// Falls back silently to the Tier-2 result if the judge is unavailable
    /// or times out — no user-visible failure mode.
    func gradeWithJudge(
        german: String,
        expected: String,
        actual: String,
        acceptedAlternatives: [String],
        responseTimeMs: Int,
        useJudge: Bool,
        targetLanguage: String = "Russian"
    ) async -> GradeResult {
        let baseline = grade(
            expected: expected,
            actual: actual,
            acceptedAlternatives: acceptedAlternatives,
            responseTimeMs: responseTimeMs
        )

        guard useJudge,
              baseline.autoGrade == .minor || baseline.autoGrade == .wrong
        else {
            return baseline
        }

        if #available(iOS 26.0, *), FoundationModelJudge.isAvailable {
            let verdict = await FoundationModelJudge().judge(
                german: german,
                expected: expected,
                actual: actual,
                targetLanguage: targetLanguage
            )
            return apply(verdict: verdict, to: baseline)
        }
        return baseline
    }

    @available(iOS 26.0, *)
    private func apply(
        verdict: FoundationModelJudge.Verdict?,
        to baseline: GradeResult
    ) -> GradeResult {
        guard let verdict, verdict != .unparseable else { return baseline }
        let softened: AutoGrade
        switch (baseline.autoGrade, verdict) {
        case (.wrong, .equivalent):
            softened = .hesitant
        case (.wrong, .minorMorphology), (.wrong, .minorWordChoice):
            softened = .minor
        case (.minor, .equivalent):
            // Cannot promote to perfect — soften only one tier.
            softened = .hesitant
        default:
            softened = baseline.autoGrade
        }
        return GradeResult(
            autoGrade: softened,
            tier: 3,
            normalizedExpected: baseline.normalizedExpected,
            normalizedActual: baseline.normalizedActual,
            editedWords: baseline.editedWords,
            totalEdits: baseline.totalEdits
        )
    }
}
