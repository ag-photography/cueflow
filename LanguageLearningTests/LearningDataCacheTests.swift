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
        cache.update(cards: [card], reviews: [review], topics: [topic], languages: [language], phraseCount: 1)
        let firstRevision = cache.revision
        let first = await cache.snapshots(languageCode: "ru").snapshots.dashboard

        XCTAssertEqual(first.reviewedToday, 1)
        XCTAssertEqual(first.spokenWordsTodayPractice, 2)
        XCTAssertEqual(first.reviewCount, 1)
        XCTAssertEqual(first.dueNow, 1)
        XCTAssertEqual(first.topics.first?.practised, 1)
        XCTAssertEqual(first.scenarioFractions["first-conversations"], 1)

        cache.update(cards: [card], reviews: [review], topics: [topic], languages: [language], phraseCount: 1)
        XCTAssertEqual(cache.revision, firstRevision, "Identical input must reuse the prepared dashboard")
        let reused = await cache.snapshots(languageCode: "ru").snapshots.dashboard
        XCTAssertEqual(reused, first)
    }

    func testHeuteSnapshotIsBuiltFromTheSamePass() async {
        let language = Language(code: "ru", name: "Русский")
        let topic = Topic(name: "Begrüßung", language: language, isActive: true)
        let phrase = Phrase(
            sourceText: "Guten Tag",
            targetText: "Добрый день",
            language: language
        )
        phrase.topics = [topic]
        topic.phrases = [phrase]

        let due = StudyCard(phrase: phrase)
        due.state = .review
        due.dueDate = .distantPast

        let fresh = Phrase(sourceText: "Danke", targetText: "Спасибо", language: language)
        fresh.topics = [topic]
        topic.phrases = [phrase, fresh]
        let newCard = StudyCard(phrase: fresh)

        let cache = LearningDataCache.shared
        cache.invalidate()
        cache.update(cards: [due, newCard], reviews: [], topics: [topic], languages: [language], phraseCount: 2)
        let today = await cache.snapshots(languageCode: "ru").snapshots.today

        XCTAssertEqual(today.dueCount, 1)
        XCTAssertEqual(today.availableNewCount, 1, "New cards in an active topic are available")
        XCTAssertEqual(today.difficultCount, 0)
        XCTAssertEqual(today.missionName, "Begrüßung")
        XCTAssertEqual(today.missionPhraseCount, 2)
    }

    func testDashboardCountsOnlyTheActiveLanguage() async {
        let russian = Language(code: "ru", name: "Русский")
        let arabic = Language(code: "ar", name: "العربية")
        let ruTopic = Topic(name: "Begrüßung", language: russian, isActive: true)
        let arTopic = Topic(name: "Begrüßung (AR)", language: arabic, isActive: true)

        let ruPhrase = Phrase(sourceText: "Guten Tag", targetText: "Добрый день", language: russian)
        ruPhrase.topics = [ruTopic]
        ruTopic.phrases = [ruPhrase]
        let arPhrase = Phrase(sourceText: "Guten Tag", targetText: "مرحبا", language: arabic)
        arPhrase.topics = [arTopic]
        arTopic.phrases = [arPhrase]
        russian.phrases = [ruPhrase]
        arabic.phrases = [arPhrase]

        let ruCard = StudyCard(phrase: ruPhrase)
        ruCard.state = .review
        ruCard.dueDate = .distantPast
        let arCard = StudyCard(phrase: arPhrase)
        arCard.state = .review
        arCard.dueDate = .distantPast

        let arReview = Review(
            card: arCard, rating: 4, autoGradeRating: 4, userAnswer: "مرحبا",
            mode: .speakDeToRu, responseTimeMs: 1_500, gradeTier: 3, wasNew: false
        )

        let cache = LearningDataCache.shared
        cache.invalidate()
        cache.update(
            cards: [ruCard, arCard], reviews: [arReview],
            topics: [ruTopic, arTopic], languages: [russian, arabic], phraseCount: 2
        )
        let ru = await cache.snapshots(languageCode: "ru").snapshots.dashboard

        XCTAssertEqual(ru.dueNow, 1, "Arabic cards must not inflate the Russian dashboard")
        XCTAssertEqual(ru.reviewCount, 1)
        XCTAssertEqual(ru.reviewedToday, 0, "The Arabic answer belongs to the Arabic dashboard")
        XCTAssertEqual(ru.currentStreak, 0)
        XCTAssertEqual(ru.topics.count, 1)
        XCTAssertEqual(ru.topics.first?.name, "Begrüßung")
        XCTAssertEqual(
            ru.reviewsByLanguage, ["ar": 1],
            "reviewsByLanguage stays cross-language on purpose"
        )

        let ar = await cache.snapshots(languageCode: "ar").snapshots.dashboard
        XCTAssertEqual(ar.reviewedToday, 1)
        XCTAssertEqual(ar.topics.first?.name, "Begrüßung (AR)")
    }

    func testHeuteCountsOnlyTheActiveLanguage() async {
        let russian = Language(code: "ru", name: "Русский")
        let arabic = Language(code: "ar", name: "العربية")
        let arTopic = Topic(name: "Begrüßung (AR)", language: arabic, isActive: true)
        let arPhrase = Phrase(sourceText: "Guten Tag", targetText: "مرحبا", language: arabic)
        arPhrase.topics = [arTopic]
        arTopic.phrases = [arPhrase]
        arabic.phrases = [arPhrase]
        russian.phrases = []

        let arCard = StudyCard(phrase: arPhrase)
        arCard.state = .review
        let arReview = Review(
            card: arCard, rating: 4, autoGradeRating: 4, userAnswer: "مرحبا",
            mode: .speakDeToRu, responseTimeMs: 1_500, gradeTier: 3, wasNew: false
        )

        let cache = LearningDataCache.shared
        cache.invalidate()
        cache.update(
            cards: [arCard], reviews: [arReview],
            topics: [arTopic], languages: [russian, arabic], phraseCount: 1
        )

        let ru = await cache.snapshots(languageCode: "ru").snapshots.today
        XCTAssertEqual(ru.reviewsToday, 0, "Heute's greeting counts the active language only")
        let ar = await cache.snapshots(languageCode: "ar").snapshots.today
        XCTAssertEqual(ar.reviewsToday, 1)
    }

    func testIncrementalRebuildPicksUpNewReviews() async {
        let language = Language(code: "ru", name: "Русский")
        let topic = Topic(name: "Begrüßung", language: language, isActive: true)
        let phrase = Phrase(sourceText: "Guten Tag", targetText: "Добрый день", language: language)
        phrase.topics = [topic]
        topic.phrases = [phrase]
        language.phrases = [phrase]
        let card = StudyCard(phrase: phrase)
        card.state = .review

        func review() -> Review {
            Review(
                card: card, rating: 4, autoGradeRating: 4, userAnswer: "Добрый день",
                mode: .speakDeToRu, responseTimeMs: 1_500, gradeTier: 3, wasNew: false
            )
        }

        let cache = LearningDataCache.shared
        cache.invalidate()
        var reviews = [review()]
        cache.update(
            cards: [card], reviews: reviews, topics: [topic],
            languages: [language], phraseCount: 1
        )
        let first = await cache.snapshots(languageCode: "ru").snapshots.dashboard
        XCTAssertEqual(first.reviewedToday, 1)

        // The cached record for the first review is reused; only the second is
        // converted. The result must be identical to a from-scratch build.
        reviews.append(review())
        card.reps += 1
        cache.update(
            cards: [card], reviews: reviews, topics: [topic],
            languages: [language], phraseCount: 1
        )
        let incremental = await cache.snapshots(languageCode: "ru").snapshots.dashboard
        XCTAssertEqual(incremental.reviewedToday, 2)

        cache.invalidate()
        cache.update(
            cards: [card], reviews: reviews, topics: [topic],
            languages: [language], phraseCount: 1
        )
        let fromScratch = await cache.snapshots(languageCode: "ru").snapshots.dashboard
        XCTAssertEqual(
            incremental, fromScratch,
            "An incremental rebuild must equal a cold one"
        )
    }

    func testInvalidateDropsCachedPhraseContent() async {
        let language = Language(code: "ru", name: "Русский")
        let topic = Topic(name: "Begrüßung", language: language, isActive: true)
        let phrase = Phrase(sourceText: "Guten Tag", targetText: "Добрый день", language: language)
        phrase.topics = [topic]
        topic.phrases = [phrase]
        language.phrases = [phrase]
        let card = StudyCard(phrase: phrase)

        let cache = LearningDataCache.shared
        cache.invalidate()
        cache.update(
            cards: [card], reviews: [], topics: [topic],
            languages: [language], phraseCount: 1
        )
        let before = await cache.snapshots(languageCode: "ru").snapshots.today
        XCTAssertEqual(before.availableNewCount, 1)

        // Deactivating the topic is a content edit the fingerprint *does* see;
        // the priority flag below is one it does not, which is why editors call
        // `invalidate()`.
        topic.isActive = false
        phrase.isPriority = true
        phrase.priorityUntil = .now.addingTimeInterval(86_400)
        cache.invalidate()
        cache.update(
            cards: [card], reviews: [], topics: [topic],
            languages: [language], phraseCount: 1
        )
        let after = await cache.snapshots(languageCode: "ru").snapshots.today
        XCTAssertEqual(
            after.availableNewCount, 1,
            "A freshly flagged priority phrase is still available after invalidate()"
        )
    }

    func testFingerprintNoticesReschedulingWithoutCountChanges() async {
        let language = Language(code: "ru", name: "Русский")
        let topic = Topic(name: "Begrüßung", language: language, isActive: true)
        let phrase = Phrase(sourceText: "Guten Tag", targetText: "Добрый день", language: language)
        phrase.topics = [topic]
        topic.phrases = [phrase]
        let card = StudyCard(phrase: phrase)
        card.state = .review
        card.dueDate = .distantPast

        let cache = LearningDataCache.shared
        cache.invalidate()
        cache.update(cards: [card], reviews: [], topics: [topic], languages: [language], phraseCount: 1)
        let before = cache.revision

        // Same counts, different schedule: the old count-only fingerprint
        // treated this as a no-op and served a stale dashboard.
        card.dueDate = .distantFuture
        card.reps += 1
        cache.update(cards: [card], reviews: [], topics: [topic], languages: [language], phraseCount: 1)

        XCTAssertNotEqual(cache.revision, before, "Rescheduling must invalidate the snapshot")
        let after = await cache.snapshots(languageCode: "ru").snapshots.today
        XCTAssertEqual(after.dueCount, 0)
    }
}
