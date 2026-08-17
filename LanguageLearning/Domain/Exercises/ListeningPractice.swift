import Foundation

struct ListeningChallenge: Equatable, Sendable {
    let phraseID: String
    let spokenText: String
    let correctMeaning: String
    let alternatives: [String]
    let languageCode: String
    let locale: String

    var options: [String] { ([correctMeaning] + alternatives).uniqued().prefix(4).map { $0 } }
}

enum ListeningPracticeBuilder {
    static func challenge(
        phraseID: String,
        spokenText: String,
        meaning: String,
        languageCode: String,
        locale: String,
        distractorMeanings: [String]
    ) -> ListeningChallenge? {
        let cleanSpoken = spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMeaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSpoken.isEmpty, !cleanMeaning.isEmpty else { return nil }
        let distractors = distractorMeanings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.localizedCaseInsensitiveCompare(cleanMeaning) != .orderedSame }
            .uniqued()
        guard distractors.count >= 2 else { return nil }
        return ListeningChallenge(
            phraseID: phraseID,
            spokenText: cleanSpoken,
            correctMeaning: cleanMeaning,
            alternatives: Array(distractors.prefix(3)),
            languageCode: languageCode,
            locale: locale
        )
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
