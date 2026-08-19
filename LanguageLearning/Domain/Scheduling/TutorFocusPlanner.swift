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

        init(phraseID: ContentID, state: LearningState) {
            self.phraseID = phraseID
            self.state = state
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

        // Identity by object reference, not `persistentModelID`: this path also
        // runs against models that were never inserted into a store (tests).
        let phraseIDs = Set(focused.flatMap { $0.phrases ?? [] }.map(ObjectIdentifier.init))
        guard !phraseIDs.isEmpty else { return nil }
        let focusedCards = cards.filter {
            guard let phrase = $0.phrase else { return false }
            return phraseIDs.contains(ObjectIdentifier(phrase))
        }
        return pacing(
            focusedTopicCount: focused.count,
            totalPhraseCount: phraseIDs.count,
            introducedPhraseCount: focusedCards.count { $0.state.isIntroduced },
            remainingNewCount: focusedCards.count { $0.state == .new },
            nextLesson: focused.compactMap(\.tutorNextLessonAt).min(),
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
        let focusedCards = cards.filter { phraseIDs.contains($0.phraseID) }
        return pacing(
            focusedTopicCount: focusedTopics.count,
            totalPhraseCount: phraseIDs.count,
            introducedPhraseCount: focusedCards.count { $0.state.isIntroduced },
            remainingNewCount: focusedCards.count { $0.state == .new },
            nextLesson: focusedTopics.compactMap(\.nextLessonAt).min(),
            now: now,
            calendar: calendar
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
