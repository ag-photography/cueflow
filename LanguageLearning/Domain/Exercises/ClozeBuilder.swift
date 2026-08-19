import Foundation
import SwiftData

/// A sentence with one expression removed, for the learner to produce in context.
///
/// Cloze is the cheapest way to practise morphology: the learner has to supply
/// the *inflected* form the sentence actually needs, not the dictionary form the
/// flashcard taught. That is exactly the step chunk-based drilling skips.
struct ClozeItem: Equatable, Sendable {
    /// The sentence with the answer replaced by `ClozeBuilder.blank`.
    let prompt: String
    /// The surface form removed from the sentence — what the learner must say
    /// or type. Note this is the *inflected* form, not the phrase's headword.
    let answer: String
    /// The untouched sentence, shown on reveal.
    let sentence: String
    /// German translation of the whole sentence: the comprehension anchor.
    let translation: String?
    /// Stress-marked or transliterated reading of the whole sentence.
    let transliteration: String?

    /// True when the sentence uses a different surface form than the headword —
    /// i.e. this item genuinely teaches an ending rather than just re-testing
    /// the flashcard.
    var teachesInflection: Bool {
        ClozeBuilder.compareKey(answer) != ClozeBuilder.compareKey(headword)
    }

    /// The dictionary form this item was built from.
    let headword: String
}

enum ClozeBuilder {
    static let blank = "＿＿＿＿"

    /// Sentences shorter than this give no useful context once a word is
    /// removed — blanking one of two words is just the flashcard again.
    private static let minimumWordCount = 3

    static func item(for phrase: Phrase) -> ClozeItem? {
        guard let sentence = phrase.exampleSentence else { return nil }
        return item(
            sentence: sentence,
            translation: phrase.exampleSentenceTranslation,
            transliteration: phrase.exampleSentenceTransliteration,
            target: phrase.targetText,
            languageCode: phrase.language?.code ?? "ru"
        )
    }

    static func item(
        sentence: String,
        translation: String?,
        transliteration: String?,
        target: String,
        languageCode: String
    ) -> ClozeItem? {
        let tokens = tokenize(sentence)
        guard tokens.count >= minimumWordCount else { return nil }

        let targetWords = tokenize(target).map(\.text)
        guard !targetWords.isEmpty else { return nil }

        guard let span = locate(targetWords, in: tokens, languageCode: languageCode) else { return nil }

        let answer = tokens[span].map(\.text).joined(separator: " ")
        guard !answer.isEmpty else { return nil }

        // Removing the answer must leave something behind to reason from.
        guard tokens.count - (span.upperBound - span.lowerBound) >= minimumWordCount - 1 else { return nil }

        let lower = tokens[span.lowerBound].range.lowerBound
        let upper = tokens[span.upperBound - 1].range.upperBound
        var prompt = sentence
        prompt.replaceSubrange(lower..<upper, with: blank)

        return ClozeItem(
            prompt: prompt,
            answer: answer,
            sentence: sentence,
            translation: translation,
            transliteration: transliteration,
            headword: target
        )
    }

    // MARK: - Matching

    private struct Token {
        let text: String
        let key: String
        let range: Range<String.Index>
    }

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index].isLetter || text[index].isNumber else {
                index = text.index(after: index)
                continue
            }
            var end = index
            while end < text.endIndex,
                  text[end].isLetter || text[end].isNumber
                    || text[end] == "-" || text[end] == "\u{0301}" {
                end = text.index(after: end)
            }
            let slice = String(text[index..<end])
            tokens.append(Token(text: slice, key: compareKey(slice), range: index..<end))
            index = end
        }
        return tokens
    }

    /// Lowercased, stripped of combining stress marks and Arabic diacritics, so
    /// `вечеро́м` and `вечером` compare equal.
    static func compareKey(_ word: String) -> String {
        let folded = word.lowercased().precomposedStringWithCanonicalMapping
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter { scalar in
            switch scalar.value {
            case 0x0300...0x036F:  // combining marks, incl. the acute used for stress
                return false
            case 0x064B...0x065F, 0x0670, 0x06D6...0x06ED:  // Arabic harakat
                return false
            default:
                return true
            }
        }))
    }

    /// Finds the run of sentence tokens corresponding to the target expression.
    private static func locate(
        _ targetWords: [String],
        in tokens: [Token],
        languageCode: String
    ) -> Range<Int>? {
        let keys = targetWords.map(compareKey)
        guard tokens.count >= keys.count else { return nil }

        var best: (range: Range<Int>, score: Int)?
        for start in 0...(tokens.count - keys.count) {
            var score = 0
            var matched = true
            for offset in keys.indices {
                guard let quality = match(keys[offset], tokens[start + offset].key, languageCode: languageCode) else {
                    matched = false
                    break
                }
                score += quality
            }
            guard matched else { continue }
            let range = start..<(start + keys.count)
            if best == nil || score > best!.score { best = (range, score) }
        }
        return best?.range
    }

    /// Returns a quality score when `sentenceWord` is a form of `targetWord`,
    /// or nil when they are unrelated. Higher is a closer match.
    private static func match(_ targetWord: String, _ sentenceWord: String, languageCode: String) -> Int? {
        if targetWord == sentenceWord { return 100 }

        if languageCode == "ar" {
            // Arabic morphology is non-concatenative; a prefix heuristic would
            // produce confident nonsense. Only the definite article is safe.
            let stripped = sentenceWord.hasPrefix("ال") ? String(sentenceWord.dropFirst(2)) : sentenceWord
            let strippedTarget = targetWord.hasPrefix("ال") ? String(targetWord.dropFirst(2)) : targetWord
            return stripped == strippedTarget ? 90 : nil
        }

        // Suppletive and stem-changing forms cannot be reached by any suffix
        // rule; they are enumerated for the shipped corpus instead.
        if IrregularForms.forms(ofHeadword: targetWord).contains(sentenceWord) { return 95 }

        guard isInflection(of: targetWord, sentenceWord) else { return nil }
        return commonPrefixLength(targetWord, sentenceWord)
    }

    /// Whether `candidate` looks like an inflected form of `known` under
    /// concatenative morphology (Russian cases, verb endings): the stem is
    /// shared and only the tail moves. Both arguments must already be
    /// `compareKey`-folded.
    ///
    /// Shared by the reading selector, which asks the same question in the
    /// opposite direction — is this sentence word a form of something I know?
    static func isInflection(of known: String, _ candidate: String) -> Bool {
        if known == candidate { return true }
        let shared = commonPrefixLength(known, candidate)
        let required = max(3, Int((Double(min(known.count, candidate.count)) * 0.6).rounded(.up)))
        guard shared >= required else { return false }
        guard abs(known.count - candidate.count) <= 4 else { return false }
        // A short word is often a coincidental prefix of a longer, unrelated one
        // — стол ⊂ столица. An inflection appends an ending, not a new stem, so
        // cap the growth relative to the word's own length.
        return candidate.count - known.count <= max(2, known.count / 2)
    }

    private static func commonPrefixLength(_ a: String, _ b: String) -> Int {
        var count = 0
        var i = a.startIndex
        var j = b.startIndex
        while i < a.endIndex, j < b.endIndex, a[i] == b[j] {
            count += 1
            i = a.index(after: i)
            j = b.index(after: j)
        }
        return count
    }
}
