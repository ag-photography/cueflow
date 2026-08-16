import Testing
import Foundation
import SwiftData
@testable import LanguageLearning

@MainActor
struct SharedProgressMigrationTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    }

    @Test func createsOneScheduleWhenPhraseHasNoCard() throws {
        let context = try makeContext()
        let phrase = Phrase(sourceText: "Hund", targetText: "собака")
        context.insert(phrase)
        try context.save()

        let result = SeedData.consolidateSharedCards(context)

        #expect(result.created == 1)
        #expect(result.removed == 0)
        #expect(phrase.cards.count == 1)
    }

    @Test func keepsMostEstablishedScheduleAndPreservesEveryReview() throws {
        let context = try makeContext()
        let phrase = Phrase(sourceText: "Hund", targetText: "собака")
        let typing = StudyCard(phrase: phrase, direction: .typeDeToRu)
        typing.reps = 2
        typing.state = .learning
        typing.lastReview = Date.now.addingTimeInterval(-3_600)

        let speaking = StudyCard(phrase: phrase, direction: .speakDeToRu)
        speaking.reps = 8
        speaking.state = .review
        speaking.lastReview = .now

        let typedReview = Review(
            card: typing, rating: 3, autoGradeRating: 3, userAnswer: "собака",
            mode: .typeDeToRu, responseTimeMs: 2_000, gradeTier: 1, wasNew: false
        )
        let spokenReview = Review(
            card: speaking, rating: 4, autoGradeRating: 4, userAnswer: "собака",
            mode: .speakDeToRu, responseTimeMs: 1_500, gradeTier: 1, wasNew: false
        )
        context.insert(phrase)
        context.insert(typing)
        context.insert(speaking)
        context.insert(typedReview)
        context.insert(spokenReview)
        try context.save()

        let result = SeedData.consolidateSharedCards(context)
        try context.save()

        #expect(result.created == 0)
        #expect(result.removed == 1)
        #expect(phrase.cards.count == 1)
        #expect(phrase.cards.first === speaking)
        #expect(speaking.reviews.count == 2)
        #expect(typedReview.card === speaking)
        #expect(typedReview.modeRaw == CardDirection.typeDeToRu.rawValue)
        #expect(spokenReview.modeRaw == CardDirection.speakDeToRu.rawValue)
    }

    @Test func migrationIsIdempotent() throws {
        let context = try makeContext()
        let phrase = Phrase(sourceText: "Hund", targetText: "собака")
        context.insert(phrase)
        context.insert(StudyCard(phrase: phrase))
        try context.save()

        let first = SeedData.consolidateSharedCards(context)
        let second = SeedData.consolidateSharedCards(context)

        #expect(first.created == 0)
        #expect(first.removed == 0)
        #expect(second.created == 0)
        #expect(second.removed == 0)
        #expect(phrase.cards.count == 1)
    }
}
