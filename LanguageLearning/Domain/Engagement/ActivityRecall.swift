import Foundation
import SwiftData

/// Free activities (Arcade, Sprint) write to the same memory as Üben, so
/// speaking practice is never a separate progress silo.
///
/// The rule mirrors `EpisodeVocabulary`: an unsupported attempt from memory
/// schedules FSRS — at most once per card per round, and only for a card that
/// is already introduced and due, so a game never introduces a card or pulls a
/// review forward. Supported attempts (shadowing, after a reveal, after building
/// from tiles) are logged as practice and spoken volume, never as a grade.
enum ActivityRecall {
    struct Decision: Equatable {
        let schedules: Bool
        let rating: Int
    }

    static func decision(supported: Bool, correct: Bool, introduced: Bool,
                         due: Bool, alreadyScheduled: Bool) -> Decision {
        let rating = correct ? 3 : 1
        return Decision(schedules: !supported && introduced && due && !alreadyScheduled, rating: rating)
    }

    /// Records one attempt and returns whether it moved the schedule.
    @MainActor @discardableResult
    static func record(card: StudyCard, kind: String, sessionID: UUID, answer: String,
                       spoken: Bool, supported: Bool, correct: Bool, alreadyScheduled: Bool,
                       responseTimeMs: Int = 0, now: Date = .now, context: ModelContext) throws -> Bool {
        let decision = decision(supported: supported, correct: correct, introduced: card.hasBeenIntroduced,
                                due: card.dueDate <= now, alreadyScheduled: alreadyScheduled)
        var evidence = AttemptEvidence(support: supported ? .revealed : .none, inputWasSpeech: spoken,
                                       assessedCorrect: correct, gradingMethod: 1)
        evidence.sessionID = sessionID
        evidence.kind = kind
        evidence.schedulingApplied = decision.schedules
        evidence.spokenWordCount = spoken ? max(1, answer.split(whereSeparator: \.isWhitespace).count) : 0
        let review = Review(card: card, rating: decision.rating, autoGradeRating: decision.rating,
                            userAnswer: answer, mode: spoken ? .speakDeToRu : .typeDeToRu,
                            responseTimeMs: responseTimeMs, gradeTier: 1, wasNew: !card.hasBeenIntroduced)
        review.timestamp = now
        review.evidence = evidence
        if decision.schedules { try SchedulerService().record(rating: decision.rating, on: card, now: now) }
        context.insert(review)
        try context.save()
        return decision.schedules
    }
}
