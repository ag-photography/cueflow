import Foundation
import SwiftData
import Testing
@testable import LanguageLearning

struct DifficultPracticeTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fixture() throws -> (ModelContext, StudyCard, StudyCard, StudyCard) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Language.self, Phrase.self, StudyCard.self, Review.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let russian = Language(code: "ru", name: "Русский")
        let arabic = Language(code: "ar", name: "العربية")
        let first = StudyCard(phrase: Phrase(sourceText: "Hallo", targetText: "Привет", language: russian))
        let second = StudyCard(phrase: Phrase(sourceText: "Danke", targetText: "Спасибо", language: russian))
        let otherLanguage = StudyCard(phrase: Phrase(sourceText: "Hallo", targetText: "مرحبا", language: arabic))
        context.insert(russian)
        context.insert(arabic)
        context.insert(first)
        context.insert(second)
        context.insert(otherLanguage)
        try context.save()
        return (context, first, second, otherLanguage)
    }

    private func review(_ card: StudyCard, rating: Int, daysAgo: Double) -> Review {
        let review = Review(
            card: card,
            rating: rating,
            autoGradeRating: rating,
            userAnswer: "",
            mode: .speakDeToRu,
            responseTimeMs: 2_000,
            gradeTier: rating >= 3 ? 3 : 1,
            wasNew: false
        )
        review.timestamp = now.addingTimeInterval(-daysAgo * 86_400)
        return review
    }

    @Test func includesOnlyRecentDifficultReviewsInActiveLanguage() throws {
        let (context, first, second, otherLanguage) = try fixture()
        let reviews = [review(first, rating: 1, daysAgo: 2), review(second, rating: 1, daysAgo: 9), review(otherLanguage, rating: 1, daysAgo: 1)]
        for review in reviews { context.insert(review) }
        try context.save()

        let result = DifficultPractice.candidates(
            cards: [first, second, otherLanguage],
            reviews: reviews,
            languageCode: "ru",
            now: now
        )

        #expect(result.count == 1)
        #expect(result.first === first)
    }

    @Test func repeatedErrorsArePrioritized() throws {
        let (context, first, second, _) = try fixture()
        let reviews = [
            review(first, rating: 2, daysAgo: 4),
            review(first, rating: 1, daysAgo: 3),
            review(second, rating: 1, daysAgo: 1),
        ]
        for review in reviews { context.insert(review) }
        try context.save()

        let result = DifficultPractice.candidates(
            cards: [first, second],
            reviews: reviews,
            languageCode: "ru",
            now: now
        )

        #expect(result.first === first)
    }

    @Test func strongReviewsAloneDoNotCreateMistakePractice() throws {
        let (context, first, _, _) = try fixture()
        let strong = review(first, rating: 4, daysAgo: 1)
        context.insert(strong)
        try context.save()

        #expect(DifficultPractice.candidates(
            cards: [first], reviews: [strong], languageCode: "ru", now: now
        ).isEmpty)
    }
}
