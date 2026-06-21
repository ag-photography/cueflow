import Foundation

/// Read-only lookup of bundled example sentences, keyed by the same
/// `"<de>|||<target>"` signature the seed loaders use for de-duplication.
///
/// The sentences are authored/generated **offline** and shipped inside the app
/// bundle (`example-sentences.json`) — exactly like `openrussian-vocab.json`.
/// Nothing here touches the network or an LLM at runtime, so the app's
/// on-device guarantee is unaffected: at runtime we only read bundled strings.
///
/// Loaded once, lazily, and cached. If the resource is missing or malformed the
/// map is empty and every lookup returns nil — callers degrade silently (a
/// phrase simply has no sentence beat).
enum ExampleSentences {
    struct Entry: Decodable {
        /// The example sentence in the target language (Russian, Arabic, …).
        let s: String
        /// German translation of the sentence (optional).
        let de: String?
        /// Pronunciation reference: stress-marked Cyrillic for Russian, Arabic
        /// script for Arabic. Mirrors `Phrase.transliteration`. Optional.
        let t: String?
    }

    private static let map: [String: Entry] = load()

    private static func load() -> [String: Entry] {
        guard
            let url = Bundle.main.url(forResource: "example-sentences", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return decoded
    }

    static func signature(de: String, target: String) -> String {
        "\(de)|||\(target)"
    }

    static func entry(de: String, target: String) -> Entry? {
        map[signature(de: de, target: target)]
    }

    /// Enriches a Phrase with its bundled example sentence, if we ship one and
    /// the phrase doesn't already have one. No-op otherwise, so it's safe to
    /// call on every phrase in every seed loader and on backfill.
    @discardableResult
    static func apply(to phrase: Phrase) -> Bool {
        guard phrase.exampleSentence == nil,
              let entry = entry(de: phrase.sourceText, target: phrase.targetText)
        else { return false }
        phrase.exampleSentence = entry.s
        phrase.exampleSentenceTranslation = entry.de
        phrase.exampleSentenceTransliteration = entry.t
        return true
    }
}
