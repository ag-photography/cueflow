import Testing
@testable import LanguageLearning

/// The rule-based importer classifier. Encodes the *actual* behaviour (incl.
/// known quirks) so a refactor that shifts a verdict is caught.
struct PhraseClassifierTests {

    @Test(arguments: [
        ("Hallo.", "Begrüßung"),
        ("Danke.", "Höflichkeit"),
        ("die Mutter", "Familie"),
        ("das Brot", "Essen & Trinken"),
        ("Montag", "Wochentage"),
        ("rot", "Farben"),
        ("fünf", "Zahlen"),
        ("Wie spät ist es?", "Zeit"),
        ("Was?", "Fragewörter"),
        ("gehen", "Verben"),
        ("gut", "Adjektive"),
    ])
    func classifiesKnownPhrases(input: String, expected: String) {
        #expect(PhraseClassifier.classify(de: input, ru: "") == expected)
    }

    @Test func reflexivePhraseIsVerb() {
        #expect(PhraseClassifier.classify(de: "sich freuen", ru: "") == "Verben")
    }

    @Test func pronounPlusWordIsVerb() {
        // (Note: "ich wohne/heiße/komme aus" are deliberately "Sich vorstellen"
        // phrase patterns, so use a plain pronoun+verb here.)
        #expect(PhraseClassifier.classify(de: "wir spielen", ru: "") == "Verben")
    }

    @Test func selfIntroductionPhrasesAreSichVorstellen() {
        #expect(PhraseClassifier.classify(de: "ich wohne in Berlin", ru: "") == "Sich vorstellen")
    }

    @Test func adverbEndingInEnIsNotMisreadAsVerb() {
        // "draußen" ends in -en but is on the non-verb list → falls through.
        #expect(PhraseClassifier.classify(de: "draußen", ru: "") == "Allgemein")
    }

    @Test func unknownFallsBackToAllgemein() {
        #expect(PhraseClassifier.classify(de: "Quizbranzel", ru: "") == "Allgemein")
    }

    @Test func everyVerdictIsAValidTopicName() {
        let samples = ["Hallo.", "Montag", "fünf", "gehen", "gut", "Quizbranzel", "die Mutter"]
        for s in samples {
            #expect(PhraseClassifier.allTopicNames.contains(PhraseClassifier.classify(de: s, ru: "")))
        }
    }
}
