import Foundation

struct TutorFocusPacing: Equatable {
    let focusedTopicCount: Int
    let totalPhraseCount: Int
    let introducedPhraseCount: Int
    let remainingNewCount: Int
    let daysUntilLesson: Int
    let dailyNewTarget: Int

    var preparationFraction: Double {
        guard totalPhraseCount > 0 else { return 0 }
        return Double(introducedPhraseCount) / Double(totalPhraseCount)
    }
}

enum TutorFocusPlanner {
    static func pacing(
        topics: [Topic],
        cards: [StudyCard],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TutorFocusPacing? {
        let focused = topics.filter { $0.isTutorFocusActive(at: now) }
        guard !focused.isEmpty else { return nil }

        let phraseIDs = Set(focused.flatMap { $0.phrases ?? [] }.map(ObjectIdentifier.init))
        guard !phraseIDs.isEmpty else { return nil }
        let focusedCards = cards.filter {
            guard let phrase = $0.phrase else { return false }
            return phraseIDs.contains(ObjectIdentifier(phrase))
        }
        let introduced = focusedCards.count { $0.state.isIntroduced }
        let remaining = focusedCards.count { $0.state == .new }
        let nextLesson = focused.compactMap(\.tutorNextLessonAt).min()
        let days: Int
        if let nextLesson {
            let start = calendar.startOfDay(for: now)
            let end = calendar.startOfDay(for: nextLesson)
            days = max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1)
        } else {
            // Migrated lessons without a stored date get a gentle one-week
            // preparation horizon until the learner sets their next lesson.
            days = 7
        }
        let dailyTarget = remaining == 0 ? 0 : Int(ceil(Double(remaining) / Double(days)))
        return TutorFocusPacing(
            focusedTopicCount: focused.count,
            totalPhraseCount: phraseIDs.count,
            introducedPhraseCount: introduced,
            remainingNewCount: remaining,
            daysUntilLesson: days,
            dailyNewTarget: dailyTarget
        )
    }
}
