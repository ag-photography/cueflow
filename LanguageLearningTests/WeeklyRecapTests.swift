import Foundation
import SwiftData
import Testing
@testable import LanguageLearning

struct WeeklyRecapTests {
    @Test func summaryCountsOnlyCurrentWeekAndLanguage() throws {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Language.self, Phrase.self, StudyCard.self, Review.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let russian = Language(code: "ru", name: "Русский")
        let arabic = Language(code: "ar", name: "العربية")
        let russianCard = StudyCard(phrase: Phrase(sourceText: "Hallo", targetText: "Привет", language: russian))
        let arabicCard = StudyCard(phrase: Phrase(sourceText: "Hallo", targetText: "مرحبا", language: arabic))
        context.insert(russian)
        context.insert(arabic)
        context.insert(russianCard)
        context.insert(arabicCard)
        try context.save()

        let spoken = makeReview(russianCard, rating: 4, wasNew: true, at: now.addingTimeInterval(-86_400))
        let weak = makeReview(russianCard, rating: 2, wasNew: false, at: now.addingTimeInterval(-43_200))
        let otherLanguage = makeReview(arabicCard, rating: 4, wasNew: true, at: now)
        let old = makeReview(russianCard, rating: 4, wasNew: true, at: now.addingTimeInterval(-10 * 86_400))
        for review in [spoken, weak, otherLanguage, old] { context.insert(review) }
        try context.save()

        let result = WeeklyRecap.summary(
            reviews: [spoken, weak, otherLanguage, old],
            languageCode: "ru",
            now: now,
            calendar: calendar
        )

        #expect(result.answers == 2)
        #expect(result.newlyIntroduced == 1)
        #expect(result.successfulSpokenRecalls == 1)
        #expect(result.notificationBody.contains("2 Antworten"))
    }

    @Test func emptyWeekUsesGentleNonJudgmentalCopy() {
        let summary = WeeklyRecapSummary(answers: 0, newlyIntroduced: 0, successfulSpokenRecalls: 0)
        #expect(summary.notificationBody.contains("wartet"))
        #expect(!summary.notificationBody.localizedCaseInsensitiveContains("verpasst"))
    }

    private func makeReview(_ card: StudyCard, rating: Int, wasNew: Bool, at date: Date) -> Review {
        let review = Review(
            card: card,
            rating: rating,
            autoGradeRating: rating,
            userAnswer: "Antwort",
            mode: .speakDeToRu,
            responseTimeMs: 1_500,
            gradeTier: rating >= 3 ? 3 : 1,
            wasNew: wasNew
        )
        review.timestamp = date
        return review
    }
}
