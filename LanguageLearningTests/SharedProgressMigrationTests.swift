import Testing
import Foundation
import SwiftData
@testable import LanguageLearning

@MainActor
struct SharedProgressMigrationTests {

    @Test func interactionGateRejectsDuplicateSubmission() {
        var gate = PracticeInteractionGate()
        let first = gate.begin(.grading)
        let duplicateGrading = gate.begin(.grading)
        let competingPersistence = gate.begin(.persistence)

        #expect(first != nil)
        #expect(duplicateGrading == nil)
        #expect(competingPersistence == nil)
        #expect(gate.isBusy)
    }

    @Test func interactionGateRejectsStaleAsyncCompletion() throws {
        var gate = PracticeInteractionGate()
        let staleCandidate = gate.begin(.choiceDelay)
        let stale = try #require(staleCandidate)
        gate.invalidate()
        let currentCandidate = gate.begin(.persistence)
        let current = try #require(currentCandidate)
        let staleFinished = gate.finish(stale)

        #expect(gate.accepts(stale) == false)
        #expect(staleFinished == false)
        #expect(gate.activeOperation == .persistence)
        let currentFinished = gate.finish(current)
        #expect(currentFinished)
        #expect(gate.isBusy == false)
    }

    @Test func supportedLanguagesComeFromReusablePackConfiguration() {
        #expect(LanguagePack.supported.map(\.code) == ["ru", "ar"])
        #expect(LanguagePack.configuration(for: "ru")?.ttsLocale == "ru-RU")
        #expect(LanguagePack.configuration(for: "ar")?.speechLocale == "ar-SA")
        #expect(LanguagePack.configuration(for: "ar")?.isRTL == true)
        #expect(LanguagePack.configuration(for: "xx") == nil)
    }

    @Test func fsrsStatesDescribePracticeNotMastery() {
        #expect(LearningState.new.isIntroduced == false)
        #expect(LearningState.learning.isIntroduced)
        #expect(LearningState.review.isIntroduced)
        #expect(LearningState.relearning.isIntroduced)
    }

    @Test func supportedLanguageSeedRepairsCapabilityMetadata() throws {
        let context = try makeContext()
        let arabic = Language(
            code: "ar",
            name: "Arabic",
            isRTL: false,
            defaultTransliterationVisible: false
        )
        context.insert(arabic)
        try context.save()

        let first = SeedData.ensureSupportedLanguages(context)
        let second = SeedData.ensureSupportedLanguages(context)
        let languages = try context.fetch(FetchDescriptor<Language>())

        #expect(first == 1) // Russian was missing.
        #expect(second == 0)
        #expect(languages.count == LanguagePack.supported.count)
        #expect(arabic.name == LanguagePack.arabic.nativeName)
        #expect(arabic.isRTL)
        #expect(arabic.defaultTransliterationVisible)
    }

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
