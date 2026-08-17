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
    ///
    /// New cards are introduced **newest-first** (by `Phrase.createdAt`): the
    /// content you just added — tutor lessons, fresh imports — surfaces before
    /// the bundled starter pack, which was all created at first launch. Without
    /// this, just-activated topics sat at the back of an oldest-first queue and
    /// could take weeks to reach behind the seeded content.
    func nextCard(
        from cards: [StudyCard],
        reviews: [Review] = [],
        dailyNewLimit: Int = .max,
        tutorDailyNewTarget: Int = 0
    ) -> StudyCard? {
        let now = Date.now

        // 1. Priority due cards first (homework boost from PDF imports).
        //    Within priority, older-due cards still come first.
        let priorityDue = cards
            .filter { $0.dueDate <= now && $0.state != .new && ($0.phrase?.isTutorPriorityActive ?? false) }
            .sorted { $0.dueDate < $1.dueDate }
        if let next = priorityDue.first { return next }

        // 2. Regular due cards.
        let due = cards
            .filter { $0.dueDate <= now && $0.state != .new }
            .sorted { $0.dueDate < $1.dueDate }
        if let next = due.first { return next }

        let calendar = Calendar.current
        let newReviewsToday = reviews
            .filter { $0.wasNew && calendar.isDateInToday($0.timestamp) }
            .count
        let remaining = dailyNewLimit - newReviewsToday
        let tutorNewReviewsToday = reviews.filter {
            $0.wasNew && calendar.isDateInToday($0.timestamp)
                && ($0.card?.phrase?.isTutorPriorityActive ?? false)
        }.count

        // 3. Priority new cards before regular new cards. Priority cards
        //    ignore the active-topic filter — homework should show up even
        //    if the user hasn't manually activated the topic. Newest first.
        let priorityNew = cards
            .filter { $0.state == .new && ($0.phrase?.isTutorPriorityActive ?? false) }
            .sorted { ($0.phrase?.createdAt ?? .distantPast) > ($1.phrase?.createdAt ?? .distantPast) }
        if let next = priorityNew.first,
           remaining > 0 || tutorNewReviewsToday < tutorDailyNewTarget {
            return next
        }

        guard remaining > 0 else { return nil }

        // 4. Regular new cards (only from active topics). Newest first, so
        //    freshly-added/-activated content is what you see next.
        let activeNew = cards
            .filter { $0.state == .new && ($0.phrase?.topics?.contains(where: { $0.isActive }) ?? false) }
            .sorted { ($0.phrase?.createdAt ?? .distantPast) > ($1.phrase?.createdAt ?? .distantPast) }
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
