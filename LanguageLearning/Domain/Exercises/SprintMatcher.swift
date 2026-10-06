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

/// Sprint personal best, stored per language. The first read adopts the old
/// app-wide best so nobody loses their record.
enum SprintBest {
    private static let legacyKey = "sprintBest"
    private static func key(_ language: String) -> String { "sprintBest.\(language)" }

    static func value(for language: String, defaults: UserDefaults = .standard) -> Int {
        if defaults.object(forKey: key(language)) == nil, defaults.integer(forKey: legacyKey) > 0 {
            defaults.set(defaults.integer(forKey: legacyKey), forKey: key(language))
            defaults.removeObject(forKey: legacyKey)
        }
        return defaults.integer(forKey: key(language))
    }

    static func set(_ value: Int, for language: String, defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: key(language))
    }
}
