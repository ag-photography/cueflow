import Testing
import Foundation
import SwiftData
@testable import LanguageLearning

/// The bundled example-sentence pipeline: the JSON ships in the app bundle,
/// loads, and enriches phrases by `de|||target` signature. The app is hosted in
/// the test runner, so `Bundle.main` is the app bundle and the resource is
/// reachable.
@MainActor
struct ExampleSentencesTests {

    @Test func bundledSentenceLoadsForKnownWord() {
        // billig → дешёвый is the user's own example; it must resolve.
        let entry = ExampleSentences.entry(de: "billig", target: "дешёвый")
        #expect(entry != nil)
        #expect(entry?.s == "Этот телефон очень дешёвый.")
        #expect(entry?.de == "Dieses Telefon ist sehr billig.")
        #expect(entry?.t?.isEmpty == false)   // ships a stress-marked line
    }

    @Test func applyPopulatesPhraseFields() {
        let phrase = Phrase(sourceText: "billig", targetText: "дешёвый")
        #expect(phrase.exampleSentence == nil)

        let didApply = ExampleSentences.apply(to: phrase)
        #expect(didApply)
        #expect(phrase.exampleSentence == "Этот телефон очень дешёвый.")
        #expect(phrase.exampleSentenceTranslation == "Dieses Telefon ist sehr billig.")
        #expect(phrase.exampleSentenceTransliteration?.isEmpty == false)
    }

    @Test func applyIsNoOpForUnknownWordAndDoesNotOverwrite() {
        // Word we don't ship a sentence for → unchanged, no crash.
        let unknown = Phrase(sourceText: "Quasar", targetText: "квазар")
        #expect(ExampleSentences.apply(to: unknown) == false)
        #expect(unknown.exampleSentence == nil)

        // Already populated → apply() must not clobber it.
        let existing = Phrase(sourceText: "billig", targetText: "дешёвый")
        existing.exampleSentence = "Custom."
        #expect(ExampleSentences.apply(to: existing) == false)
        #expect(existing.exampleSentence == "Custom.")
    }

    @Test func seedingPopulatesExampleSentences() throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let ctx = ModelContext(container)

        // Install the Russian starter pack, then confirm a single-word entry we
        // ship a sentence for got enriched during seeding.
        SeedData.addStarterPack(ctx)
        let descriptor = FetchDescriptor<Phrase>(
            predicate: #Predicate { $0.sourceText == "billig" }
        )
        let billig = try ctx.fetch(descriptor).first
        #expect(billig?.exampleSentence == "Этот телефон очень дешёвый.")
    }
}
