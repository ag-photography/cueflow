import Testing
import Foundation
import SwiftData
@testable import LanguageLearning

/// Next-card selection policy and the FSRS state transition. Uses an in-memory
/// store so it never touches the app's real data.
@MainActor
struct SchedulerServiceTests {

    private let scheduler = SchedulerService()

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    }

    @discardableResult
    private func makePhrase(_ ctx: ModelContext, active: Bool = true, priority: Bool = false) -> Phrase {
        let topic = Topic(name: "Tiere", isActive: active)
        let phrase = Phrase(sourceText: "Hund", targetText: "собака", topics: [topic])
        if priority {
            phrase.isPriority = true
            phrase.priorityUntil = Date.now.addingTimeInterval(7 * 24 * 3600)
        }
        ctx.insert(topic)
        ctx.insert(phrase)
        return phrase
    }

    // MARK: - Selection

    @Test func dueReviewCardBeatsNewCard() throws {
        let ctx = try makeContext()
        let phrase = makePhrase(ctx)
        let newCard = StudyCard(phrase: phrase, direction: .typeDeToRu)
        let dueCard = StudyCard(phrase: phrase, direction: .typeDeToRu)
        dueCard.state = .review
        dueCard.dueDate = Date.now.addingTimeInterval(-3600)   // overdue
        ctx.insert(newCard); ctx.insert(dueCard)

        let next = scheduler.nextCard(from: [newCard, dueCard],
                                      reviews: [], dailyNewLimit: 10)
        #expect(next === dueCard)
    }

    @Test func newCardFromActiveTopicIsServedWhenNoneDue() throws {
        let ctx = try makeContext()
        let phrase = makePhrase(ctx, active: true)
        let card = StudyCard(phrase: phrase, direction: .typeDeToRu)
        ctx.insert(card)

        let next = scheduler.nextCard(from: [card], reviews: [], dailyNewLimit: 10)
        #expect(next === card)
    }

    @Test func newCardFromInactiveTopicIsNotServed() throws {
        let ctx = try makeContext()
        let phrase = makePhrase(ctx, active: false)
        let card = StudyCard(phrase: phrase, direction: .typeDeToRu)
        ctx.insert(card)

        let next = scheduler.nextCard(from: [card], reviews: [], dailyNewLimit: 10)
        #expect(next == nil)
    }

    @Test func dailyNewLimitStopsServingNewCards() throws {
        let ctx = try makeContext()
        let phrase = makePhrase(ctx, active: true)
        let card = StudyCard(phrase: phrase, direction: .typeDeToRu)
        ctx.insert(card)

        let todaysNewReviews = (0..<3).map { _ in
            Review(card: card, rating: 3, autoGradeRating: 3, userAnswer: "",
                   mode: .typeDeToRu, responseTimeMs: 1_000, gradeTier: 1, wasNew: true)
        }
        let next = scheduler.nextCard(from: [card], reviews: todaysNewReviews, dailyNewLimit: 3)
        #expect(next == nil)
    }

    @Test func newCardsAreIntroducedNewestFirst() throws {
        let ctx = try makeContext()
        let topic = Topic(name: "Tutor", isActive: true)
        ctx.insert(topic)
        // Older "seeded" phrase vs a newer "just added" one.
        let older = Phrase(sourceText: "alt", targetText: "старый", topics: [topic])
        older.createdAt = Date.now.addingTimeInterval(-10_000)
        let newer = Phrase(sourceText: "neu", targetText: "новый", topics: [topic])
        newer.createdAt = Date.now
        ctx.insert(older); ctx.insert(newer)
        let olderCard = StudyCard(phrase: older, direction: .typeDeToRu)
        let newerCard = StudyCard(phrase: newer, direction: .typeDeToRu)
        ctx.insert(olderCard); ctx.insert(newerCard)

        let next = scheduler.nextCard(from: [olderCard, newerCard],
                                      reviews: [], dailyNewLimit: 10)
        #expect(next === newerCard)
    }

    @Test func priorityNewCardIgnoresInactiveTopic() throws {
        let ctx = try makeContext()
        // Homework boost: a priority phrase surfaces even if its topic is off.
        let phrase = makePhrase(ctx, active: false, priority: true)
        let card = StudyCard(phrase: phrase, direction: .typeDeToRu)
        ctx.insert(card)

        let next = scheduler.nextCard(from: [card], reviews: [], dailyNewLimit: 10)
        #expect(next === card)
    }

    @Test func tutorPacingCanIntroduceRequiredCardAfterGeneralDailyLimit() throws {
        let ctx = try makeContext()
        let topic = Topic(name: "Jahreszeiten", isActive: true)
        topic.startTutorFocus(nextLessonAt: Date.now.addingTimeInterval(2 * 86_400))
        let phrase = Phrase(sourceText: "Frühling", targetText: "весна", topics: [topic])
        phrase.contentSource = .tutorImport
        let card = StudyCard(phrase: phrase)
        ctx.insert(topic); ctx.insert(phrase); ctx.insert(card)

        let completedRegularLimit = (0..<3).map { _ in
            let review = Review(
                card: card, rating: 3, autoGradeRating: 3, userAnswer: "",
                mode: .typeDeToRu, responseTimeMs: 900, gradeTier: 1, wasNew: true
            )
            // These represent regular cards, so don't count them against the
            // tutor-specific preparation target.
            review.card = nil
            return review
        }
        let next = scheduler.nextCard(
            from: [card], reviews: completedRegularLimit,
            dailyNewLimit: 3, tutorDailyNewTarget: 2
        )

        #expect(next === card)
    }

    @Test func topicScopeOnlyIncludesCardsFromTheChosenTutorFocus() throws {
        let ctx = try makeContext()
        let seasons = Topic(name: "Jahreszeiten", isActive: true)
        let travel = Topic(name: "Reisen", isActive: true)
        let spring = Phrase(sourceText: "Frühling", targetText: "весна", topics: [seasons])
        let train = Phrase(sourceText: "Zug", targetText: "поезд", topics: [travel])
        let springCard = StudyCard(phrase: spring, direction: .typeDeToRu)
        let trainCard = StudyCard(phrase: train, direction: .typeDeToRu)
        ctx.insert(seasons); ctx.insert(travel)
        ctx.insert(spring); ctx.insert(train)
        ctx.insert(springCard); ctx.insert(trainCard)

        let scope = PracticeScope.topic(id: seasons.persistentModelID)

        #expect(scope.includes(springCard))
        #expect(!scope.includes(trainCard))
    }

    @Test func schedulerDoesNotSplitProgressByExerciseMode() throws {
        let ctx = try makeContext()
        let phrase = makePhrase(ctx, active: true)
        let typeCard = StudyCard(phrase: phrase, direction: .typeDeToRu)
        let speakCard = StudyCard(phrase: phrase, direction: .speakDeToRu)
        ctx.insert(typeCard); ctx.insert(speakCard)

        typeCard.state = .review
        typeCard.dueDate = Date.now.addingTimeInterval(-60)

        let next = scheduler.nextCard(from: [typeCard, speakCard], reviews: [], dailyNewLimit: 10)
        #expect(next === typeCard)
    }

    // MARK: - Recording a review

    @Test func recordAdvancesNewCardState() throws {
        let ctx = try makeContext()
        let phrase = makePhrase(ctx)
        let card = StudyCard(phrase: phrase, direction: .typeDeToRu)
        ctx.insert(card)
        let dueBefore = card.dueDate

        try scheduler.record(rating: 3, on: card, now: .now)

        #expect(card.reps == 1)
        #expect(card.state != .new)
        #expect(card.lastReview != nil)
        #expect(card.dueDate > dueBefore)
    }

    @Test func recordRejectsInvalidRating() throws {
        let ctx = try makeContext()
        let phrase = makePhrase(ctx)
        let card = StudyCard(phrase: phrase, direction: .typeDeToRu)
        ctx.insert(card)

        #expect(throws: SchedulerService.SchedulerError.self) {
            try scheduler.record(rating: 0, on: card)
        }
    }
}
