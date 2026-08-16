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
        /// Pronunciation reference. Legacy Arabic entries have script here and
        /// Latin in `s`; `apply` normalizes that representation at runtime.
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
        guard phrase.exampleSentence == nil else { return false }

        let direct = entry(de: phrase.sourceText, target: phrase.targetText)
        let legacyArabic = phrase.language?.code == "ar"
            ? phrase.transliteration.flatMap { entry(de: phrase.sourceText, target: $0) }
            : nil
        guard let entry = direct ?? legacyArabic else { return false }

        if phrase.language?.code == "ar",
           let script = entry.t,
           containsArabicScript(script),
           !containsArabicScript(entry.s) {
            phrase.exampleSentence = script
            phrase.exampleSentenceTransliteration = entry.s
        } else {
            phrase.exampleSentence = entry.s
            phrase.exampleSentenceTransliteration = entry.t
        }
        phrase.exampleSentenceTranslation = entry.de
        return true
    }

    private static func containsArabicScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF,
                 0xFB50...0xFDFF, 0xFE70...0xFEFF:
                return true
            default:
                return false
            }
        }
    }
}
