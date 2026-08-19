import Foundation
import SwiftData

/// One sentence chosen to sit just past what the learner already knows.
struct ReadingPassage: Equatable, Sendable, Identifiable {
    let id: ContentID
    let sentence: String
    let translation: String?
    let transliteration: String?
    /// Words in the sentence that no stabilised phrase covers yet.
    let unknownWords: [String]
    let knownWordCount: Int
    let totalWordCount: Int

    var knownFraction: Double {
        totalWordCount == 0 ? 0 : Double(knownWordCount) / Double(totalWordCount)
    }
}

/// Builds a reading pass at *i+1* from the learner's own memory state.
///
/// The comprehensibility threshold in the input literature is roughly 95–98 %
/// known vocabulary. At sentence length that granularity does not exist — one
/// unknown word in six is 83 % — so the practical reading of "just past current
/// level" is **at most one unfamiliar word per sentence**, preferring sentences
/// with exactly one so there is something new to acquire.
///
/// What makes this possible here is that the app already knows, phrase by
/// phrase, what this learner has stabilised. The threshold is a computation
/// rather than an editorial guess, and it is per learner.
enum ReadingSelector {
    /// A phrase counts as known once its memory has some durability. FSRS
    /// stability is in days; a week means it survived at least one real gap.
    static let knownStabilityDays: Double = 7

    struct KnownPhrase: Sendable {
        let target: String
        let stability: Double
        let isIntroduced: Bool

        init(target: String, stability: Double, isIntroduced: Bool) {
            self.target = target
            self.stability = stability
            self.isIntroduced = isIntroduced
        }
    }

    struct SentenceSource: Sendable {
        let id: ContentID
        let sentence: String
        let translation: String?
        let transliteration: String?

        init(id: ContentID, sentence: String, translation: String?, transliteration: String?) {
            self.id = id
            self.sentence = sentence
            self.translation = translation
            self.transliteration = transliteration
        }
    }

    /// Words too grammatical to count as vocabulary load. Leaving them out of
    /// the "unknown" tally stops every sentence from failing on particles the
    /// learner reads straight past.
    ///
    /// Case forms are listed explicitly rather than derived: Russian pronouns
    /// are irregular (я → меня → мне, мы → нам), so the stem matcher cannot
    /// reach them and would report `нам` as new vocabulary.
    private static let functionWords: Set<String> = [
        // conjunctions, particles, prepositions
        "и", "а", "но", "или", "не", "ни", "же", "ли", "бы", "как", "что",
        "чтобы", "так", "уже", "ещё", "еще", "вот", "да", "нет", "тоже",
        "очень", "если", "когда", "потому", "только", "даже",
        "в", "во", "на", "у", "с", "со", "к", "ко", "по", "за", "из", "о",
        "об", "от", "до", "для", "при", "про", "над", "под", "без",
        // personal pronouns and their case forms
        "я", "меня", "мне", "мной", "мною",
        "ты", "тебя", "тебе", "тобой",
        "он", "она", "оно", "они", "его", "него", "ему", "нему", "им", "ним",
        "её", "ее", "неё", "нее", "ей", "ней", "их", "них", "ими", "ними",
        "мы", "нас", "нам", "нами", "вы", "вас", "вам", "вами",
        "себя", "себе", "собой",
        // possessives and demonstratives
        "мой", "моя", "моё", "мое", "мои", "моего", "моей", "моих", "моим",
        "твой", "твоя", "твоё", "твое", "твои", "твоего", "твоей",
        "наш", "наша", "наше", "наши", "ваш", "ваша", "ваше", "ваши",
        "свой", "своя", "своё", "свое", "свои", "свою", "своего", "своей",
        "это", "эта", "этот", "эти", "этом", "этого", "этой", "эту", "этим",
        "то", "та", "тот", "те", "том", "того", "той", "тем", "тех",
        "все", "всё", "вся", "весь", "всех", "всем", "всего",
    ]

    static func passages(
        sentences: [SentenceSource],
        known: [KnownPhrase],
        limit: Int = 8
    ) -> [ReadingPassage] {
        // Everything durable enough to read past without stopping, bucketed by
        // stem prefix so each sentence word is a hash lookup plus a couple of
        // comparisons rather than a scan of the whole vocabulary.
        var knownStems: Set<String> = []
        var byPrefix: [String: [String]] = [:]
        for phrase in known where phrase.isIntroduced && phrase.stability >= knownStabilityDays {
            for word in words(in: phrase.target) {
                let key = ClozeBuilder.compareKey(word)
                guard !key.isEmpty else { continue }
                knownStems.insert(key)
                byPrefix[bucket(key), default: []].append(key)
                // Knowing быть means recognising была, which shares too little
                // with it for the stem rule to connect.
                for form in IrregularForms.forms(ofHeadword: key) {
                    knownStems.insert(form)
                }
            }
        }
        guard !knownStems.isEmpty else { return [] }

        var scored: [(passage: ReadingPassage, unknown: Int)] = []
        for source in sentences {
            let tokens = words(in: source.sentence)
            guard tokens.count >= 3 else { continue }

            var unknown: [String] = []
            var knownCount = 0
            for token in tokens {
                let key = ClozeBuilder.compareKey(token)
                if knownStems.contains(key) || functionWords.contains(key)
                    || isKnownForm(key, byPrefix: byPrefix) {
                    knownCount += 1
                } else {
                    unknown.append(token)
                }
            }
            guard unknown.count <= 1 else { continue }

            scored.append((
                ReadingPassage(
                    id: source.id,
                    sentence: source.sentence,
                    translation: source.translation,
                    transliteration: source.transliteration,
                    unknownWords: unknown,
                    knownWordCount: knownCount,
                    totalWordCount: tokens.count
                ),
                unknown.count
            ))
        }

        // Exactly one new word first — that is where acquisition happens.
        // Fully-known sentences still earn a place: fluent re-reading is how
        // recognition becomes automatic.
        return scored
            .sorted { lhs, rhs in
                if lhs.unknown != rhs.unknown { return lhs.unknown > rhs.unknown }
                return lhs.passage.totalWordCount > rhs.passage.totalWordCount
            }
            .prefix(limit)
            .map(\.passage)
    }

    /// Catches case and verb endings on an otherwise known stem, so `вечером`
    /// counts as known once `вечер` is stable and `читаю` once `читать` is.
    ///
    /// Suppletive forms that no suffix rule reaches (быть → была, ходить → хожу)
    /// are enumerated in `IrregularForms` and folded into the known set, so they
    /// resolve rather than reading as new vocabulary.
    private static func isKnownForm(_ key: String, byPrefix: [String: [String]]) -> Bool {
        byPrefix[bucket(key), default: []].contains { ClozeBuilder.isInflection(of: $0, key) }
    }

    /// Inflection preserves the first few characters, so a short prefix is a
    /// safe bucket key for candidates that could possibly match.
    private static func bucket(_ key: String) -> String {
        String(key.prefix(3))
    }

    private static func words(in text: String) -> [String] {
        text.split { !($0.isLetter || $0.isNumber || $0 == "-" || $0 == "\u{0301}") }
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}

extension ReadingSelector {
    @MainActor
    static func passages(phrases: [Phrase], languageCode: String, limit: Int = 8) -> [ReadingPassage] {
        var sentences: [SentenceSource] = []
        var known: [KnownPhrase] = []
        for phrase in phrases where phrase.language?.code == languageCode {
            let cards = phrase.cards ?? []
            known.append(KnownPhrase(
                target: phrase.targetText,
                stability: cards.map(\.stability).max() ?? 0,
                isIntroduced: cards.contains { $0.state.isIntroduced }
            ))
            if let sentence = phrase.exampleSentence, !sentence.isEmpty {
                sentences.append(SentenceSource(
                    id: phrase.contentID,
                    sentence: sentence,
                    translation: phrase.exampleSentenceTranslation,
                    transliteration: phrase.exampleSentenceTransliteration
                ))
            }
        }
        return passages(sentences: sentences, known: known, limit: limit)
    }
}
