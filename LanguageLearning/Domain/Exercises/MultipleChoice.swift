import Foundation

/// Builds the answer set for the "Wählen" (multiple-choice) exercise: the
/// correct answer plus up to `distractors` other plausible options, de-duped
/// and shuffled. Pure and injectable-shuffle so it's testable.
enum MultipleChoice {
    static func options(
        correct: String,
        from candidates: [String],
        distractors: Int = 3,
        shuffle: ([String]) -> [String] = { $0.shuffled() }
    ) -> [String] {
        var seen: Set<String> = [correct]
        var picks: [String] = []
        for candidate in shuffle(candidates) where !seen.contains(candidate) {
            seen.insert(candidate)
            picks.append(candidate)
            if picks.count == distractors { break }
        }
        return shuffle([correct] + picks)
    }
}
