import Foundation

struct TutorFocusPacing: Equatable, Sendable {
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
    /// A focused topic reduced to the values pacing actually needs. Lets the
    /// dashboard snapshots be built off the main actor, away from `@Model`.
    struct TopicInput: Sendable {
        let phraseIDs: Set<ContentID>
        let nextLessonAt: Date?

        init(phraseIDs: Set<ContentID>, nextLessonAt: Date?) {
            self.phraseIDs = phraseIDs
            self.nextLessonAt = nextLessonAt
        }
    }

    struct CardInput: Sendable {
        let phraseID: ContentID
        let state: LearningState
        let introduced: Bool

        init(phraseID: ContentID, state: LearningState, introduced: Bool? = nil) {
            self.phraseID = phraseID
            self.state = state
            self.introduced = introduced ?? state.isIntroduced
        }
    }

    static func pacing(
        topics: [Topic],
        cards: [StudyCard],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TutorFocusPacing? {
        let focused = topics.filter { $0.isTutorFocusActive(at: now) }
        guard !focused.isEmpty else { return nil }

        return pacing(
            focusedTopics: focused.map { .init(phraseIDs: Set(($0.phrases ?? []).map(\.contentID)), nextLessonAt: $0.tutorNextLessonAt) },
            cards: cards.compactMap { card in
                card.phrase.map { .init(phraseID: $0.contentID, state: card.state, introduced: card.hasBeenIntroduced) }
            },
            now: now,
            calendar: calendar
        )
    }

    /// Value-typed entry point used when building snapshots off the main actor.
    static func pacing(
        focusedTopics: [TopicInput],
        cards: [CardInput],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TutorFocusPacing? {
        guard !focusedTopics.isEmpty else { return nil }
        let phraseIDs = Set(focusedTopics.flatMap(\.phraseIDs))
        guard !phraseIDs.isEmpty else { return nil }
        let introduced = Set(cards.filter(\.introduced).map(\.phraseID)).intersection(phraseIDs)
        // Allocate shared phrases once, to their nearest deadline. Each topic
        // keeps its own preparation horizon rather than borrowing the first date.
        var allocated: Set<ContentID> = []
        var target = 0
        var nearest = 7
        for topic in focusedTopics.sorted(by: { ($0.nextLessonAt ?? now.addingTimeInterval(7 * 86_400)) < ($1.nextLessonAt ?? now.addingTimeInterval(7 * 86_400)) }) {
            let ids = topic.phraseIDs.subtracting(allocated)
            allocated.formUnion(ids)
            let item = pacing(focusedTopicCount: 1, totalPhraseCount: ids.count,
                              introducedPhraseCount: ids.intersection(introduced).count,
                              remainingNewCount: ids.subtracting(introduced).count,
                              nextLesson: topic.nextLessonAt, now: now, calendar: calendar)
            target += item.dailyNewTarget
            nearest = allocated == ids ? item.daysUntilLesson : min(nearest, item.daysUntilLesson)
        }
        return TutorFocusPacing(
            focusedTopicCount: focusedTopics.count,
            totalPhraseCount: phraseIDs.count,
            introducedPhraseCount: introduced.count,
            remainingNewCount: phraseIDs.subtracting(introduced).count,
            daysUntilLesson: nearest,
            dailyNewTarget: target
        )
    }

    private static func pacing(
        focusedTopicCount: Int,
        totalPhraseCount: Int,
        introducedPhraseCount: Int,
        remainingNewCount: Int,
        nextLesson: Date?,
        now: Date,
        calendar: Calendar
    ) -> TutorFocusPacing {
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
        return TutorFocusPacing(
            focusedTopicCount: focusedTopicCount,
            totalPhraseCount: totalPhraseCount,
            introducedPhraseCount: introducedPhraseCount,
            remainingNewCount: remainingNewCount,
            daysUntilLesson: days,
            dailyNewTarget: remainingNewCount == 0 ? 0 : Int(ceil(Double(remainingNewCount) / Double(days)))
        )
    }
}
