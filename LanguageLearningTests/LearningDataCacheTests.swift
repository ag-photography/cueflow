import XCTest
@testable import LanguageLearning

@MainActor
final class LearningDataCacheTests: XCTestCase {
    func testDashboardIsPrecomputedOncePerDataRevision() async {
        let language = Language(code: "ru", name: "Русский")
        let topic = Topic(name: "Begrüßung", language: language, isActive: true)
        let phrase = Phrase(
            sourceText: "Guten Tag",
            targetText: "Добрый день",
            language: language
        )
        phrase.topics = [topic]
        topic.phrases = [phrase]

        let card = StudyCard(phrase: phrase)
        card.state = .review
        card.dueDate = .distantPast
        let review = Review(
            card: card,
            rating: 4,
            autoGradeRating: 4,
            userAnswer: "Добрый день",
            mode: .speakDeToRu,
            responseTimeMs: 1_500,
            gradeTier: 3,
            wasNew: false
        )

        let cache = LearningDataCache.shared
        cache.update(cards: [card], reviews: [review], topics: [topic])
        let firstRevision = cache.revision
        let first = await cache.dashboard(languageCode: "ru").snapshot

        XCTAssertEqual(first.reviewedToday, 1)
        XCTAssertEqual(first.spokenWordsTodayPractice, 2)
        XCTAssertEqual(first.reviewCount, 1)
        XCTAssertEqual(first.dueNow, 1)
        XCTAssertEqual(first.topics.first?.practised, 1)
        XCTAssertEqual(first.scenarioFractions["first-conversations"], 1)

        cache.update(cards: [card], reviews: [review], topics: [topic])
        XCTAssertEqual(cache.revision, firstRevision, "Identical input must reuse the prepared dashboard")
        let reused = await cache.dashboard(languageCode: "ru").snapshot
        XCTAssertEqual(reused, first)
    }
}
