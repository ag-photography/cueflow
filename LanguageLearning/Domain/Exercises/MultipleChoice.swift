import Foundation

/// Builds the answer set for the "Wählen" (multiple-choice) exercise: the
/// correct answer plus up to `distractors` other plausible options, de-duped
/// and shuffled. Pure and injectable-shuffle so it's testable.
enum MultipleChoice {
    struct Item {
        let source: String
        let target: String
        let language: String
        var alternatives: [String] = []
    }

    /// Excludes *known* ambiguity; this is not a semantic equivalence model.
    /// Keep morphology/Arabic letter distinctions intact. No topic-name or
    /// image matching determines correctness.
    static func options(correct: Item, from candidates: [Item],
                        shuffle: ([String]) -> [String] = { $0.shuffled() }) -> [String] {
        func key(_ text: String) -> String {
            text.precomposedStringWithCanonicalMapping.lowercased()
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
                .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        }
        func meanings(_ text: String) -> Set<String> {
            Set(text.components(separatedBy: CharacterSet(charactersIn: ";/,")).map(key).filter { !$0.isEmpty })
        }
        let meaning = meanings(correct.source)
        let answers = Set(([correct.target] + correct.alternatives).map(key))
        guard !meaning.isEmpty, !key(correct.target).isEmpty, !correct.language.isEmpty else { return [] }
        var seen = answers
        let eligible = candidates.compactMap { candidate -> String? in
            let target = key(candidate.target)
            let otherAnswers = Set(([candidate.target] + candidate.alternatives).map(key))
            let otherMeaning = meanings(candidate.source)
            guard candidate.language == correct.language, !target.isEmpty,
                  !otherMeaning.isEmpty, meaning.isDisjoint(with: otherMeaning),
                  answers.isDisjoint(with: otherAnswers), seen.insert(target).inserted else { return nil }
            return candidate.target
        }
        guard !eligible.isEmpty else { return [] } // Never a one-answer guessing task.
        return options(correct: correct.target, from: eligible, shuffle: shuffle)
    }

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
