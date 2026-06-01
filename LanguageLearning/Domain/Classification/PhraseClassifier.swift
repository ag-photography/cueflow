import Foundation

/// Rule-based topic classifier for German phrases. Maps a German phrase to
/// one of the standard topic names used by the starter pack (Begrüßung,
/// Familie, Essen & Trinken, Verben, …). Falls back to "Allgemein" for
/// anything that doesn't fit a clear bucket.
///
/// Deterministic and offline — no LLM. ~80% accurate on typical A1-A2
/// vocabulary; ambiguous cases land in Allgemein and the user can re-tag
/// them in Library afterwards.
enum PhraseClassifier {

    /// All topic names the classifier may return — handy for "ensure
    /// topic exists" passes during import.
    static let allTopicNames: [String] = [
        "Begrüßung", "Höflichkeit", "Verständigung", "Sich vorstellen",
        "Zahlen", "Wochentage", "Monate", "Zeit", "Familie",
        "Im Restaurant", "Wegbeschreibung", "Einkaufen", "Verben",
        "Adjektive", "Fragewörter", "Wetter", "Körperteile",
        "Essen & Trinken", "Kleidung", "Zuhause", "Farben", "Verkehr",
        "Allgemein"
    ]

    static func classify(de: String, ru: String) -> String {
        let raw = de.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        let words = lower.split(whereSeparator: { $0.isWhitespace || $0 == "?" || $0 == "!" || $0 == "." || $0 == "," }).map(String.init)

        // Phrase-level patterns first (so "Wie spät ist es?" doesn't get
        // matched as a generic question word).
        if lower.contains("wie spät") || lower.contains("uhr ist") { return "Zeit" }
        if lower.contains("wie geht") || lower.contains("wie heißt du") { return "Sich vorstellen" }
        if lower.contains("wie ist das wetter") { return "Wetter" }
        if lower.contains("ich heiße") || lower.contains("ich komme aus") || lower.contains("ich wohne") || lower.contains("wie alt") || lower.contains("woher kommst") || lower.contains("wo wohnst") { return "Sich vorstellen" }

        // Question words: with `?` suffix OR explicit list (wieviel,
        // wieviele have no `?` in some tutor lists).
        let questionWords: Set<String> = ["was","wer","wo","wohin","woher","wann","warum","wie","welche","welcher","welches","wieviel","wieviele","wie viele","wie viel"]
        if lower.hasSuffix("?"), words.count <= 2, questionWords.contains(words.first ?? "") {
            return "Fragewörter"
        }
        if words.count == 1, questionWords.contains(lower) {
            return "Fragewörter"
        }

        // Hard-coded category lists. Order matters — more specific first.
        for (topic, terms) in topicTerms {
            if terms.contains(lower) { return topic }
            // Compound phrase: any single word in the phrase matches.
            if words.contains(where: { terms.contains($0) }) { return topic }
            // Prefix match for noun phrases like "der Honig" → "honig" is in the list.
            for word in words where word.count >= 3 {
                if terms.contains(word) { return topic }
            }
        }

        // Numbers (catch any digits-as-words).
        if isNumberWord(lower) { return "Zahlen" }

        // Verbs: bare infinitive (ends in -en, no article, single word) —
        // unless it's a known non-verb that happens to end in -en (adverbs
        // of place, common adjectives).
        if words.count == 1, lower.hasSuffix("en"),
           !startsWithArticle(lower),
           !nonVerbsEndingInEn.contains(lower) {
            return "Verben"
        }
        // "ich/du/er/sie/wir/ihr/man X" → verb usage.
        if words.count >= 2, ["ich", "du", "er", "wir", "ihr", "es", "man"].contains(words[0]) {
            return "Verben"
        }
        // "sie" is ambiguous (she / they / formal you) — verb only if next word ends in -en/-t.
        if words.count >= 2, words[0] == "sie",
           let second = words.dropFirst().first,
           second.hasSuffix("en") || second.hasSuffix("t") {
            return "Verben"
        }
        if words.first == "sich" { return "Verben" }   // reflexive

        // Adjectives: positive-list whitelist. Single-word, no article.
        // Anything outside the whitelist falls through to Allgemein so
        // adverbs ("deshalb", "gerne", "leider") and conjunctions ("aber")
        // don't get mis-labelled as adjectives.
        if words.count == 1, !startsWithArticle(lower), knownAdjectives.contains(lower) {
            return "Adjektive"
        }

        return "Allgemein"
    }

    /// Whitelist of common A1–B1 German adjectives. Anything outside the
    /// list lands in Allgemein. Precision > recall — user can re-tag the
    /// long-tail in Library.
    private static let knownAdjectives: Set<String> = [
        "gut","schlecht","groß","klein","neu","alt","schön","hässlich",
        "einfach","schwierig","schnell","langsam","warm","kalt","heiß",
        "billig","teuer","lecker","müde","glücklich","traurig","scharf",
        "süß","leicht","schwer","richtig","falsch","wichtig","interessant",
        "lustig","ernst","laut","leise","hell","dunkel","sauber","schmutzig",
        "stark","schwach","jung","frisch","frei","reich","arm","dick","dünn",
        "lang","kurz","breit","schmal","tief","hoch","niedrig","voll","leer"
    ]

    /// Common German words that end in "-en" but are NOT verb infinitives.
    /// Mostly adverbs of place and a few adjectives. Keeps the verb-by-suffix
    /// heuristic from over-classifying.
    private static let nonVerbsEndingInEn: Set<String> = [
        "draußen", "drinnen", "oben", "unten", "innen", "vorne", "hinten",
        "offen", "eigen", "eben", "morgen", "übermorgen", "morgens",
        "abends", "übrigen", "mitten", "gegen", "neben", "zwischen",
        "hinter", "über", "unter"
    ]

    // MARK: - Term tables

    /// German keywords keyed by their topic. Matched as exact word or
    /// substring-of-word. Lowercased.
    private static let topicTerms: [(String, Set<String>)] = [
        ("Wochentage", [
            "montag", "dienstag", "mittwoch", "donnerstag", "freitag", "samstag", "sonntag"
        ]),
        ("Monate", [
            "januar","februar","märz","april","mai","juni","juli","august",
            "september","oktober","november","dezember"
        ]),
        ("Farben", [
            "rot","blau","grün","gelb","schwarz","weiß","grau","braun","orange","violett","rosa"
        ]),
        ("Familie", [
            "familie","mutter","vater","bruder","schwester","sohn","tochter",
            "großmutter","großvater","oma","opa","eltern","kind","kinder","freund","freunde","freundin"
        ]),
        ("Essen & Trinken", [
            "brot","wasser","kaffee","tee","milch","käse","fleisch","fisch","apfel","banane",
            "ei","zucker","salz","suppe","bier","wein","honig","kaviar","hering","reis","eistee",
            "gemüse","getränk","obst","frucht","früchte","essen","trinken","trinkt","durst","hunger",
            "mit gemüse","kaffee hilft","kartoffel","kartoffeln","kuchen","schokolade","saft",
            "butter","wurst","schinken","tomate","gurke","zwiebel","knoblauch","pfeffer"
        ]),
        ("Körperteile", [
            "kopf","hand","bein","auge","ohr","mund","nase","gesicht","haar","zahn","arm","fuß","finger"
        ]),
        ("Kleidung", [
            "hemd","hose","schuhe","mantel","mütze","kleid","jacke","pullover","schal"
        ]),
        ("Zuhause", [
            "haus","wohnung","zimmer","küche","bad","badezimmer","schlafzimmer",
            "fenster","tür","tisch","stuhl","sofa","bett"
        ]),
        ("Verkehr", [
            "auto","zug","bus","flugzeug","u-bahn","taxi","fahrrad","bahnhof"
        ]),
        ("Zeit", [
            "heute","morgen","gestern","jetzt","später","bald","stunde","minute","tag","woche","monat","jahr",
            "schon lange"
        ]),
        ("Wetter", [
            "wetter","regnet","schneit","sonnig","windig","heiß","kalt"
        ]),
        ("Begrüßung", [
            "hallo","guten morgen","guten tag","guten abend","gute nacht",
            "auf wiedersehen","tschüss","bis bald","bis morgen","willkommen"
        ]),
        ("Höflichkeit", [
            "danke","vielen dank","bitte","entschuldigung","tut mir leid","keine ursache","macht nichts"
        ]),
        ("Verständigung", [
            "ja","nein","vielleicht","verstehe nicht","wiederholen","sprechen sie","langsamer"
        ]),
        ("Im Restaurant", [
            "speisekarte","rechnung","lecker","bestellen","tisch reservieren","ober","menü"
        ]),
        ("Wegbeschreibung", [
            "links","rechts","geradeaus","toilette","markt","richtung"
        ]),
        ("Einkaufen", [
            "kostet","teuer","billig","karte zahlen","kasse","wie viel kostet"
        ])
    ]

    private static func isQuestionStarter(_ w: String) -> Bool {
        ["was","wer","wo","wohin","wann","warum","wie","welche","welcher","welches"].contains(w)
    }

    private static func startsWithArticle(_ s: String) -> Bool {
        for art in ["der ", "die ", "das ", "den ", "dem ", "des ", "ein ", "eine ", "einen ", "einem "] {
            if s.hasPrefix(art) { return true }
        }
        return false
    }

    private static func isNumberWord(_ s: String) -> Bool {
        let nums: Set<String> = [
            "eins","zwei","drei","vier","fünf","sechs","sieben","acht","neun","zehn",
            "elf","zwölf","dreizehn","vierzehn","fünfzehn","sechzehn","siebzehn","achtzehn","neunzehn",
            "zwanzig","dreißig","vierzig","fünfzig","sechzig","siebzig","achtzig","neunzig","hundert","tausend"
        ]
        return nums.contains(s.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
