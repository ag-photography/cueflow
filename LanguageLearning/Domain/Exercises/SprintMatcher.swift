import Foundation

/// Lenient "did they say it?" check for the fluency Sprint. Speech recognition
/// is messy, and Sprint rewards *volume and speed* over precision — so we accept
/// more slop than the graded modes: an exact normalized hit, the target
/// appearing inside the spoken tail, or a near-match within a small edit budget.
///
/// Kept as a pure function (no mic, no SwiftData) so the matching logic is
/// unit-testable — the live speech loop can only be exercised on a real device,
/// but this can be pinned down in tests.
enum SprintMatcher {

    /// - Parameters:
    ///   - spokenTail: the speech recognised *since the current card appeared*
    ///     (the running transcription with the previous cards' text removed).
    ///   - target: the expected answer (target-language text).
    /// - Returns: true if the tail is a close-enough rendering of the target.
    static func matches(spokenTail: String, target: String) -> Bool {
        let t = FuzzyMatcher.normalize(target)
        let s = FuzzyMatcher.normalize(spokenTail)
        guard !t.isEmpty, !s.isEmpty else { return false }

        if s == t { return true }

        // The recogniser streams a growing transcription; once the user finishes
        // the phrase the target usually sits at the end of it. Only trust a raw
        // substring hit for targets long enough not to fire on filler words.
        if t.count >= 4, s.contains(t) { return true }

        // Tolerate ~1 edit per 6 characters (morphology slips + recogniser
        // noise), comparing the target against a same-sized window at the tail.
        let budget = max(1, t.count / 6)
        let window = String(s.suffix(t.count + budget))
        return FuzzyMatcher.levenshtein(window, t) <= budget
    }
}
