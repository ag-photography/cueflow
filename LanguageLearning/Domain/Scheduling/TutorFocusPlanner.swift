import Foundation

/// One invitation, with continuation ahead of new work. Dates represent actual
/// saved rounds, not a newly computed preview. No scheduling or trial mutation.
enum TodayPracticeRecommendation: Equatable {
    case tutor, practice, situation

    static func choose(tutorResume: Date?, practiceResume: Date?, situationResume: Date?,
                       hasTutor: Bool, hasPractice: Bool, hasSituation: Bool) -> Self? {
        let resumable: [(Self, Date?)] = [(.tutor, tutorResume), (.practice, practiceResume), (.situation, situationResume)]
        if let saved = resumable.compactMap({ kind, date in date.map { (kind, $0) } })
            .max(by: { $0.1 < $1.1 }) { return saved.0 }
        if hasTutor { return .tutor }
        if hasPractice { return .practice }
        return hasSituation ? .situation : nil
    }
}

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
    /// Builds bounded entry points from the actual lesson vocabulary. No title
    /// matching, generated substitutes, extra schedules or daily-limit bypass.
    struct QuickRound: Identifiable {
        var id: UUID { plan.id }
        let topic: Topic
        let plan: PracticePlan
        let remainingCount: Int
    }

    static func quickRounds(topics: [Topic], cards: [StudyCard], reviews: [Review],
                            language: String, dailyLimit: Int,
                            savedPlans: [PracticePlan] = [], endedIDs: [UUID] = []) -> [QuickRound] {
        topics.filter { $0.language?.code == language && $0.isTutorFocusActive }
            .sorted {
                let left = $0.tutorNextLessonAt ?? .distantFuture
                let right = $1.tutorNextLessonAt ?? .distantFuture
                return left == right ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : left < right
            }.map { topic in
                let scope = PracticeScope.topic(id: topic.persistentModelID)
                let pool = cards.filter { $0.phrase?.language?.code == language && scope.includes($0) }
                let saved = savedPlans.last {
                    $0.canResume(language: language, scope: scope.planKey, mode: .speakDeToRu,
                                 budget: 3, endedIDs: endedIDs)
                    && !$0.remaining(in: pool, reviews: reviews).isEmpty
                }
                let plan = saved ?? PracticePlan.make(cards: pool, reviews: reviews, language: language,
                    scope: scope.planKey, mode: .speakDeToRu, budget: 3, dailyLimit: dailyLimit,
                    tutorIDs: Set(pool.compactMap { $0.phrase?.contentID }))
                return QuickRound(topic: topic, plan: plan,
                    remainingCount: plan.remaining(in: pool, reviews: reviews, dailyNewLimit: dailyLimit).count)
            }
    }

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
