import Foundation
import FSRS

/// Wraps the FSRS-6 algorithm. Owns the next-card selection policy and the
/// post-review state update on a `StudyCard`. The view layer only ever sees
/// the SwiftData `StudyCard`; FSRS structs stay inside this file.
struct SchedulerService {
    private let fsrs: FSRS

    init() {
        self.fsrs = FSRS(parameters: FSRSParameters())
    }

    /// Picks the next card to review. Due cards (sorted by overdue-ness) take
    /// priority. If none are due, falls back to a `new` card from cards whose
    /// topic is currently active, capped by `dailyNewLimit` minus the count of
    /// new-card reviews already made today (tracked via `Review.wasNew`).
    func nextCard(
        from cards: [StudyCard],
        direction: CardDirection? = nil,
        reviews: [Review] = [],
        dailyNewLimit: Int = .max
    ) -> StudyCard? {
        let scoped = direction.map { d in cards.filter { $0.direction == d } } ?? cards
        let now = Date.now
        let due = scoped
            .filter { $0.dueDate <= now && $0.state != .new }
            .sorted { $0.dueDate < $1.dueDate }
        if let next = due.first {
            return next
        }

        let calendar = Calendar.current
        let newReviewsToday = reviews
            .filter { $0.wasNew && calendar.isDateInToday($0.timestamp) }
            .filter { direction == nil || ($0.card?.direction == direction) }
            .count
        let remaining = dailyNewLimit - newReviewsToday
        guard remaining > 0 else { return nil }

        let activeNew = scoped
            .filter { $0.state == .new && ($0.phrase?.topics.contains(where: { $0.isActive }) ?? false) }
            .sorted { ($0.phrase?.createdAt ?? .distantPast) < ($1.phrase?.createdAt ?? .distantPast) }
        return activeNew.first
    }

    /// Applies a learner rating (1=Again, 2=Hard, 3=Good, 4=Easy) to a card,
    /// running the FSRS algorithm and mutating the card's schedule fields.
    /// Throws if the rating is out of range.
    func record(rating: Int, on card: StudyCard, now: Date = .now) throws {
        guard let fsrsRating = Rating(rawValue: rating), fsrsRating != .manual else {
            throw SchedulerError.invalidRating(rating)
        }

        let result = try fsrs.next(card: card.fsrsCard, now: now, grade: fsrsRating)
        card.applyFSRS(result.card)
    }

    enum SchedulerError: Error {
        case invalidRating(Int)
    }
}

private extension StudyCard {
    var fsrsCard: Card {
        Card(
            due: dueDate,
            stability: stability,
            difficulty: difficulty,
            elapsedDays: 0,
            scheduledDays: 0,
            reps: reps,
            lapses: lapses,
            state: CardState(rawValue: state.fsrsRawValue) ?? .new,
            lastReview: lastReview
        )
    }

    func applyFSRS(_ updated: Card) {
        dueDate = updated.due
        stability = updated.stability
        difficulty = updated.difficulty
        reps = updated.reps
        lapses = updated.lapses
        if let mapped = LearningState.fromFSRS(updated.state) {
            state = mapped
        }
        lastReview = updated.lastReview
    }
}

private extension LearningState {
    var fsrsRawValue: Int {
        switch self {
        case .new: return 0
        case .learning: return 1
        case .review: return 2
        case .relearning: return 3
        }
    }

    static func fromFSRS(_ s: CardState) -> LearningState? {
        switch s {
        case .new: return .new
        case .learning: return .learning
        case .review: return .review
        case .relearning: return .relearning
        }
    }
}
