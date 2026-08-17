import Foundation
import SwiftData
import Testing
@testable import LanguageLearning

@MainActor
struct LearningInsightsTests {
    @Test func exercisePolicyScaffoldsNewUnavailableAndRepeatedFailureStates() {
        #expect(AdaptiveExercisePolicy.presentation(
            state: .new, targetWordCount: 3, speechAvailable: true, recentRatings: []
        ) == .choice)
        #expect(AdaptiveExercisePolicy.presentation(
            state: .review, targetWordCount: 3, speechAvailable: false, recentRatings: []
        ) == .tiles)
        #expect(AdaptiveExercisePolicy.presentation(
            state: .review, targetWordCount: 3, speechAvailable: true, recentRatings: [1, 2]
        ) == .tiles)
        #expect(AdaptiveExercisePolicy.presentation(
            state: .review, targetWordCount: 3, speechAvailable: true, recentRatings: [3, 1]
        ) == .speech)
    }

    @Test func curriculumRespectsPrerequisitesWithoutBlockingPractice() throws {
        let progress = CurriculumPlanner.progress(
            scenarios: ScenarioDefinition.defaults,
            fractions: ["first-conversations": 0.2]
        )
        let first = try #require(progress.first { $0.id == "first-conversations" })
        let cafe = try #require(progress.first { $0.id == "cafe-food" })

        #expect(first.readiness == .inProgress)
        #expect(cafe.readiness == .foundationsNeeded)
        #expect(CurriculumPlanner.recommendation(from: progress)?.id == "first-conversations")
    }

    @Test func analyzerFindsOmissionAndSlowRetrieval() throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let language = Language(code: "ru", name: "Русский")
        let phrase = Phrase(sourceText: "Ich möchte Kaffee", targetText: "Я хотел бы кофе", language: language)
        let card = StudyCard(phrase: phrase)
        let omission = Review(
            card: card, rating: 1, autoGradeRating: 1, userAnswer: "Я хотел кофе",
            mode: .speakDeToRu, responseTimeMs: 2_000, gradeTier: 2, wasNew: false
        )
        let slow = Review(
            card: card, rating: 3, autoGradeRating: 3, userAnswer: "Я хотел бы кофе",
            mode: .speakDeToRu, responseTimeMs: 10_000, gradeTier: 3, wasNew: false
        )
        context.insert(language)
        context.insert(phrase)
        context.insert(card)
        context.insert(omission)
        context.insert(slow)

        let patterns = LearningInsightAnalyzer.patterns(from: [omission, slow])
        #expect(patterns.contains { $0.pattern == .omittedWords })
        #expect(patterns.contains { $0.pattern == .slowRetrieval })
    }
}
