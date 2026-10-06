import Foundation
import SwiftData

struct ProgressDayStat: Identifiable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    let count: Int
}

struct ProgressTopicStat: Identifiable, Equatable, Sendable {
    let id: ContentID
    let name: String
    let isActive: Bool
    let practised: Int
    let total: Int
}

struct ProgressDashboardSnapshot: Equatable, Sendable {
    let scenarioFractions: [String: Double]
    let learningPatterns: [LearningPatternInsight]
    let fastestRecall: LearningEvent?
    let phrasesProducedUnaided: Int
    let dueNow: Int
    let reviewedToday: Int
    let currentStreak: Int
    let newCount: Int
    let learningCount: Int
    let reviewCount: Int
    let relearningCount: Int
    let weekly: [ProgressDayStat]
    let spokenWeekly: [ProgressDayStat]
    let spokenWordsTodayPractice: Int
    let fluencyLabel: String?
    let reviewsByLanguage: [String: Int]
    let topics: [ProgressTopicStat]
    /// Items that keep slipping across their whole history — worth rewording
    /// rather than drilling again.
    let leechCount: Int
    /// The headline number: correct answers said aloud from memory, unaided,
    /// in the last 7 days — the product's core act, from any activity.
    var spokenFromMemoryThisWeek: Int = 0
    /// Ausdrücke that sit: FSRS stability of at least 21 days.
    var durableCount: Int = 0

    static let empty = ProgressDashboardSnapshot(
        scenarioFractions: [:], learningPatterns: [], fastestRecall: nil,
        phrasesProducedUnaided: 0, dueNow: 0, reviewedToday: 0,
        currentStreak: 0, newCount: 0, learningCount: 0,
        reviewCount: 0, relearningCount: 0, weekly: [], spokenWeekly: [],
        spokenWordsTodayPractice: 0, fluencyLabel: nil,
        reviewsByLanguage: [:], topics: [], leechCount: 0
    )
}

/// Everything the Heute tab renders, precomputed.
///
/// Heute used to derive all of this from live `@Query` arrays inside `body`.
/// Because a `TabView` re-evaluates every tab's body whenever the selection
/// changes, that put ~1.3 s of relationship faulting and list-building on the
/// main thread for *every* tab switch — including switches away from Heute.
struct TodaySnapshot: Equatable, Sendable {
    var tutorFocusNames: [String] = []
    let dueCount: Int
    let availableNewCount: Int
    let reviewsToday: Int
    let difficultCount: Int
    let dailyQuests: [DailyQuestProgress]
    let fastestRecall: LearningEvent?
    let recentImprovement: ImprovingExpression?
    let pacing: TutorFocusPacing?
    let missionName: String?
    let missionPhraseCount: Int

    var allQuestsComplete: Bool { !dailyQuests.isEmpty && dailyQuests.allSatisfy(\.isComplete) }

    static let empty = TodaySnapshot(
        dueCount: 0, availableNewCount: 0, reviewsToday: 0, difficultCount: 0,
        dailyQuests: [], fastestRecall: nil, recentImprovement: nil,
        pacing: nil, missionName: nil, missionPhraseCount: 0
    )
}

/// One language's precomputed screens, produced together so a single pass over
/// the store feeds every tab.
struct LearningSnapshots: Equatable, Sendable {
    let dashboard: ProgressDashboardSnapshot
    let today: TodaySnapshot

    static let empty = LearningSnapshots(dashboard: .empty, today: .empty)
}

private struct ProgressCardRecord: Sendable {
    let phraseID: ContentID
    let languageCode: String
    let state: LearningState
    let introduced: Bool
    let dueDate: Date
    let lapses: Int
    var stability: Double = 0
    /// Stored rather than pre-evaluated: the boost expires on a clock, so a
    /// cached boolean would freeze at whatever it was when the record was built.
    let isPriority: Bool
    let priorityUntil: Date?

    func isPriorityActive(at date: Date) -> Bool {
        isPriority && (priorityUntil.map { $0 >= date } ?? true)
    }
}

/// The part of a card that comes from its phrase and effectively never moves.
/// Cached across rebuilds so a practice session doesn't re-fault `card.phrase`
/// for every card in the store just because one card was rescheduled.
private struct CardIdentity: Sendable {
    let phraseID: ContentID
    let languageCode: String
    let isPriority: Bool
    let priorityUntil: Date?
}

private struct ProgressReviewRecord: Sendable {
    let languageCode: String
    let cardID: ContentID
    let event: LearningEvent
    let autoGradeRating: Int
    let expectedAnswer: String
    let userAnswer: String
}

private struct ProgressTopicRecord: Sendable {
    let id: ContentID
    let name: String
    /// `name` with any trailing language suffix removed, resolved once —
    /// scenario matching used to run this regex per topic per scenario.
    let baseName: String
    let languageCode: String
    let isActive: Bool
    let isTutorFocusActive: Bool
    let tutorNextLessonAt: Date?
    let phraseIDs: Set<ContentID>
}

/// A process-local read cache for navigation destinations.
///
/// One pass over the store converts the `@Model` graph into `Sendable` value
/// records; every screen's derived state is then computed from those records in
/// a detached task. Views read a finished struct, so re-evaluating a body costs
/// nothing beyond laying out the result.
@MainActor
final class LearningDataCache {
    static let shared = LearningDataCache()

    private var eventsByLanguage: [String: [LearningEvent]] = [:]
    private(set) var isPrimed = false
    private(set) var revision = 0
    private var fingerprint: Int?
    private var snapshotTask: Task<[String: LearningSnapshots], Never>?
    /// Reviews never change once written, so their records survive a rebuild.
    /// This is what makes the pass after a practice session cheap: only the
    /// answers just given have to be converted.
    private var reviewRecordsByID: [ContentID: ProgressReviewRecord] = [:]
    private var identityByCard: [ContentID: CardIdentity] = [:]

    private init() {}

    /// Drops everything derived from phrase content, so the next `update`
    /// rebuilds from scratch.
    ///
    /// The fingerprint sees counts, topic flags, review timestamps and card
    /// scheduling — everything the practice loop touches. It cannot see a phrase
    /// being retyped, moved between topics, or flagged priority, because none of
    /// those move a count or a scalar it hashes. Content editors call this.
    func invalidate() {
        fingerprint = nil
        reviewRecordsByID = [:]
        identityByCard = [:]
    }

    func update(
        cards: [StudyCard],
        reviews: [Review],
        topics: [Topic],
        languages: [Language],
        phraseCount: Int
    ) {
        let nextFingerprint = Self.fingerprint(
            cards: cards, reviews: reviews, topics: topics, phraseCount: phraseCount
        )
        guard fingerprint != nextFingerprint else { return }
        fingerprint = nextFingerprint

        // Resolved from the language side: `Language.phrases` is the inverse of
        // `Phrase.language`, so this is one relationship fault per language
        // rather than one per card.
        var languageByPhrase: [ContentID: String] = [:]
        languageByPhrase.reserveCapacity(phraseCount)
        for language in languages {
            let code = language.code
            for phrase in language.phrases ?? [] {
                languageByPhrase[phrase.contentID] = code
            }
        }
        // A phrase is reviewed many times, so its topic set is resolved once
        // and reused. Faulting `phrase.topics` per review was the bulk of this
        // pass — and this pass runs again after every practice session.
        var topicIDsByPhrase: [ContentID: Set<ContentID>] = [:]
        var nextReviewRecords: [ContentID: ProgressReviewRecord] = [:]
        nextReviewRecords.reserveCapacity(reviews.count)
        var reviewRecords: [ProgressReviewRecord] = []
        reviewRecords.reserveCapacity(reviews.count)
        for review in reviews {
            let reviewID = review.contentID
            guard review.evidence?.kind != "exposure" else { continue }
            // Already converted on an earlier pass — reuse it rather than
            // faulting card → phrase → topics all over again.
            if let known = reviewRecordsByID[reviewID] {
                nextReviewRecords[reviewID] = known
                reviewRecords.append(known)
                continue
            }
            guard let card = review.card, let phrase = card.phrase else { continue }
            let phraseID = phrase.contentID
            let topicIDs: Set<ContentID>
            if let known = topicIDsByPhrase[phraseID] {
                topicIDs = known
            } else {
                topicIDs = Set((phrase.topics ?? []).map(\.contentID))
                topicIDsByPhrase[phraseID] = topicIDs
            }
            let record = ProgressReviewRecord(
                languageCode: languageByPhrase[phraseID] ?? "",
                cardID: card.contentID,
                event: LearningEvent(
                    timestamp: review.timestamp,
                    phraseID: phraseID,
                    sourceText: phrase.sourceText,
                    topicIDs: topicIDs,
                    exercise: LearningExercise(rawValue: review.modeRaw),
                    rating: review.rating,
                    gradeTier: review.gradeTier,
                    responseTimeMs: review.responseTimeMs,
                    spokenWordCount: review.evidence?.spokenWordCount ?? review.userAnswer.split(whereSeparator: \.isWhitespace).count,
                    evidence: review.evidence
                ),
                autoGradeRating: review.autoGradeRating,
                expectedAnswer: phrase.targetText,
                userAnswer: review.userAnswer
            )
            nextReviewRecords[reviewID] = record
            reviewRecords.append(record)
        }
        reviewRecordsByID = nextReviewRecords
        let introducedCardIDs = Set(reviews.compactMap { $0.card?.contentID })

        var nextIdentities: [ContentID: CardIdentity] = [:]
        nextIdentities.reserveCapacity(cards.count)
        var cardRecords: [ProgressCardRecord] = []
        cardRecords.reserveCapacity(cards.count)
        for card in cards {
            let cardID = card.contentID
            let identity: CardIdentity
            if let known = identityByCard[cardID] {
                identity = known
            } else {
                guard let phrase = card.phrase else { continue }
                let phraseID = phrase.contentID
                identity = CardIdentity(
                    phraseID: phraseID,
                    languageCode: languageByPhrase[phraseID] ?? "",
                    isPriority: phrase.isPriority,
                    priorityUntil: phrase.priorityUntil
                )
            }
            nextIdentities[cardID] = identity
            // Only the scheduling scalars are re-read; they live on the card
            // itself, so no relationship is touched.
            cardRecords.append(ProgressCardRecord(
                phraseID: identity.phraseID,
                languageCode: identity.languageCode,
                state: card.state,
                introduced: card.state.isIntroduced || introducedCardIDs.contains(cardID),
                dueDate: card.dueDate,
                lapses: card.lapses,
                stability: card.stability,
                isPriority: identity.isPriority,
                priorityUntil: identity.priorityUntil
            ))
        }
        identityByCard = nextIdentities
        let topicRecords = topics.map {
            ProgressTopicRecord(
                id: $0.contentID,
                name: $0.name,
                baseName: Self.baseTopicName($0.name),
                languageCode: $0.language?.code ?? "",
                isActive: $0.isActive,
                isTutorFocusActive: $0.isTutorFocusActive,
                tutorNextLessonAt: $0.tutorNextLessonAt,
                phraseIDs: Set(($0.phrases ?? []).map(\.contentID))
            )
        }
        eventsByLanguage = Dictionary(grouping: reviewRecords, by: \.languageCode)
            .mapValues { $0.map(\.event) }
        revision += 1
        snapshotTask?.cancel()
        snapshotTask = Task.detached(priority: .userInitiated) {
            let codes = Set(reviewRecords.map(\.languageCode) + topicRecords.map(\.languageCode) + ["ru", "ar"])
            return Dictionary(uniqueKeysWithValues: codes.map { code in
                (code, LearningSnapshots(
                    dashboard: Self.makeDashboard(
                        activeLanguageCode: code,
                        cards: cardRecords,
                        reviews: reviewRecords,
                        topics: topicRecords
                    ),
                    today: Self.makeToday(
                        activeLanguageCode: code,
                        cards: cardRecords,
                        reviews: reviewRecords,
                        topics: topicRecords
                    )
                ))
            })
        }
        isPrimed = true
    }

    func snapshots(languageCode: String) async -> (revision: Int, snapshots: LearningSnapshots) {
        let requestedRevision = revision
        guard let snapshotTask else { return (requestedRevision, .empty) }
        let value = await snapshotTask.value
        return (requestedRevision, value[languageCode] ?? .empty)
    }

    func events(languageCode: String) -> [LearningEvent] {
        eventsByLanguage[languageCode] ?? []
    }

    /// A change token for the store.
    ///
    /// Deliberately avoids touching any relationship: faulting `topic.phrases`
    /// for every topic just to decide there is nothing to do was costing more
    /// than the check saved. `phraseCount` comes from a `fetchCount`, which is
    /// a `SELECT COUNT(*)` rather than a materialisation.
    ///
    private static func fingerprint(
        cards: [StudyCard], reviews: [Review], topics: [Topic], phraseCount: Int
    ) -> Int {
        var signature = Hasher()
        signature.combine(cards.count)
        signature.combine(reviews.count)
        signature.combine(topics.count)
        signature.combine(phraseCount)
        for topic in topics {
            signature.combine(topic.persistentModelID)
            signature.combine(topic.name)
            signature.combine(topic.isActive)
            signature.combine(topic.isTutorFocus)
            signature.combine(topic.tutorFocusUntil)
            signature.combine(topic.tutorNextLessonAt)
        }
        // Scalars, not relationships: these move whenever a card is graded or
        // rescheduled, which counts alone would miss.
        var latestReview = Date.distantPast
        for review in reviews {
            latestReview = max(latestReview, review.timestamp)
        }
        signature.combine(latestReview)
        var totalReps = 0
        var latestDue = Date.distantPast
        for card in cards {
            totalReps += card.reps
            latestDue = max(latestDue, card.dueDate)
        }
        signature.combine(totalReps)
        signature.combine(latestDue)
        return signature.finalize()
    }

    // MARK: - Heute

    nonisolated private static func makeToday(
        activeLanguageCode: String,
        cards: [ProgressCardRecord],
        reviews: [ProgressReviewRecord],
        topics: [ProgressTopicRecord],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TodaySnapshot {
        let languageTopics = topics.filter { $0.languageCode == activeLanguageCode }
        let languageCards = cards.filter { $0.languageCode == activeLanguageCode }
        let events = reviews.lazy.filter { $0.languageCode == activeLanguageCode }.map(\.event)
        let languageEvents = Array(events)

        // Eligibility resolved from the topic side. Asking each new card "do any
        // of your topics count?" faults a to-many relationship per card, which
        // was the single most expensive thing Heute did.
        let activeTopicPhraseIDs = Set(languageTopics.lazy.filter(\.isActive).flatMap(\.phraseIDs))
        let tutorTopicPhraseIDs = Set(languageTopics.lazy.filter(\.isTutorFocusActive).flatMap(\.phraseIDs))

        let availableNew = languageCards.count { card in
            !card.introduced
                && (activeTopicPhraseIDs.contains(card.phraseID)
                    || card.isPriorityActive(at: now)
                    || tutorTopicPhraseIDs.contains(card.phraseID))
        }

        let pacing = TutorFocusPlanner.pacing(
            focusedTopics: languageTopics.filter(\.isTutorFocusActive).map {
                TutorFocusPlanner.TopicInput(phraseIDs: $0.phraseIDs, nextLessonAt: $0.tutorNextLessonAt)
            },
            cards: languageCards.map {
                TutorFocusPlanner.CardInput(phraseID: $0.phraseID, state: $0.state, introduced: $0.introduced)
            },
            now: now,
            calendar: calendar
        )

        let mission = languageTopics.first(where: \.isActive)
        let startOfToday = calendar.startOfDay(for: now)

        return TodaySnapshot(
            tutorFocusNames: languageTopics.filter(\.isTutorFocusActive).map(\.name),
            dueCount: languageCards.count { $0.state != .new && $0.dueDate <= now },
            availableNewCount: availableNew,
            reviewsToday: reviews.count {
                $0.languageCode == activeLanguageCode && $0.event.timestamp >= startOfToday
            },
            difficultCount: difficultCardCount(
                cards: languageCards, reviews: reviews,
                languageCode: activeLanguageCode, now: now, calendar: calendar
            ),
            dailyQuests: LearningMotivation.dailyQuests(events: languageEvents, now: now, calendar: calendar),
            fastestRecall: LearningMotivation.fastestStrongRecall(events: languageEvents),
            recentImprovement: LearningMotivation.mostRecentImprovement(events: languageEvents),
            pacing: pacing,
            missionName: mission?.name,
            missionPhraseCount: mission?.phraseIDs.count ?? 0
        )
    }

    /// Mirrors `DifficultPractice.candidates`, counting only. Heute shows the
    /// number; the practice session builds the real pool when it starts.
    nonisolated private static func difficultCardCount(
        cards: [ProgressCardRecord],
        reviews: [ProgressReviewRecord],
        languageCode: String,
        now: Date,
        calendar: Calendar
    ) -> Int {
        guard let start = calendar.date(byAdding: .day, value: -7, to: now) else { return 0 }
        var difficult: Set<ContentID> = []
        for review in reviews where review.languageCode == languageCode {
            guard review.event.timestamp >= start, review.event.timestamp <= now,
                  review.event.rating <= 2 || review.autoGradeRating <= 2
            else { continue }
            difficult.insert(review.cardID)
        }
        return difficult.count
    }

    // MARK: - Fortschritt

    nonisolated private static func makeDashboard(
        activeLanguageCode: String,
        cards: [ProgressCardRecord],
        reviews: [ProgressReviewRecord],
        topics: [ProgressTopicRecord],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ProgressDashboardSnapshot {
        // Everything on this screen describes the language the learner has
        // selected. Only `reviewsByLanguage` is deliberately cross-language —
        // it exists to compare them.
        let languageReviews = reviews.filter { $0.languageCode == activeLanguageCode }
        let languageCards = cards.filter { $0.languageCode == activeLanguageCode }
        let languageTopics = topics.filter { $0.languageCode == activeLanguageCode }
        let events = languageReviews.map(\.event)
        let startOfToday = calendar.startOfDay(for: now)
        let introducedPhraseIDs = Set(languageCards.filter(\.introduced).map(\.phraseID))
        let weekly = dayStats(now: now, calendar: calendar) { start, end in
            languageReviews.count { $0.event.timestamp >= start && $0.event.timestamp < end }
        }
        let spoken = languageReviews.filter { $0.event.isSpoken }
        let spokenWeekly = dayStats(now: now, calendar: calendar) { start, end in
            spoken.lazy.filter { $0.event.timestamp >= start && $0.event.timestamp < end }
                .reduce(0) { $0 + $1.event.spokenWordCount }
        }
        let thisWeekStart = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        let previousWeekStart = calendar.date(byAdding: .day, value: -13, to: startOfToday) ?? startOfToday
        let thisWeek = averageSeconds(spoken.filter { $0.event.timestamp >= thisWeekStart })
        let previousWeek = averageSeconds(spoken.filter {
            $0.event.timestamp >= previousWeekStart && $0.event.timestamp < thisWeekStart
        })
        let fluency: String? = thisWeek.map { current in
            guard let previousWeek, abs(previousWeek - current) >= 0.1 else {
                return String(format: "%.1f s", current)
            }
            return String(format: "%@ %.1f s", current < previousWeek ? "↓" : "↑", current)
        }
        let scenarioFractions = Dictionary(uniqueKeysWithValues: ScenarioDefinition.defaults.map { scenario in
            let ids = Set(languageTopics.lazy.filter {
                scenario.topicTerms.contains($0.baseName)
            }.flatMap(\.phraseIDs))
            return (scenario.id, LearningMotivation.strongRecallFraction(events: events, phraseIDs: ids))
        })
        let topicStats = languageTopics.filter { !$0.phraseIDs.isEmpty }.map { topic in
            ProgressTopicStat(
                id: topic.id,
                name: topic.name,
                isActive: topic.isActive,
                practised: topic.phraseIDs.intersection(introducedPhraseIDs).count,
                total: topic.phraseIDs.count
            )
        }.sorted {
            if $0.isActive != $1.isActive { return $0.isActive && !$1.isActive }
            return $0.name.localizedCompare($1.name) == .orderedAscending
        }

        return ProgressDashboardSnapshot(
            scenarioFractions: scenarioFractions,
            learningPatterns: learningPatterns(from: languageReviews),
            fastestRecall: LearningMotivation.fastestStrongRecall(events: events),
            phrasesProducedUnaided: Set(reviewRecordsProductivePhraseIDs(languageReviews)).count,
            dueNow: languageCards.count { $0.dueDate <= now && $0.state != .new },
            reviewedToday: languageReviews.count { $0.event.timestamp >= startOfToday },
            currentStreak: streak(reviews: languageReviews, now: now, calendar: calendar),
            newCount: languageCards.count { $0.state == .new },
            learningCount: languageCards.count { $0.state == .learning },
            reviewCount: languageCards.count { $0.state == .review },
            relearningCount: languageCards.count { $0.state == .relearning },
            weekly: weekly,
            spokenWeekly: spokenWeekly,
            spokenWordsTodayPractice: spoken.lazy.filter { $0.event.timestamp >= startOfToday }
                .reduce(0) { $0 + $1.event.spokenWordCount },
            fluencyLabel: fluency,
            reviewsByLanguage: reviews.reduce(into: [:]) { $0[$1.languageCode, default: 0] += 1 },
            topics: topicStats,
            leechCount: languageCards.count { $0.lapses >= DifficultPractice.leechLapseThreshold },
            spokenFromMemoryThisWeek: spoken.count {
                $0.event.timestamp >= thisWeekStart && $0.event.isStrongProductiveRecall
            },
            durableCount: languageCards.count { $0.introduced && $0.stability >= 21 }
        )
    }

    nonisolated private static func dayStats(
        now: Date,
        calendar: Calendar,
        count: (Date, Date) -> Int
    ) -> [ProgressDayStat] {
        let today = calendar.startOfDay(for: now)
        return (0..<7).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let next = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            return ProgressDayStat(date: date, count: count(date, next))
        }
    }

    nonisolated private static func averageSeconds(_ reviews: [ProgressReviewRecord]) -> Double? {
        let times = reviews.map(\.event.responseTimeMs).filter { $0 > 0 }
        guard !times.isEmpty else { return nil }
        return Double(times.reduce(0, +)) / Double(times.count) / 1_000
    }

    nonisolated private static func reviewRecordsProductivePhraseIDs(
        _ reviews: [ProgressReviewRecord]
    ) -> [ContentID] {
        reviews.compactMap {
            guard $0.event.isStrongProductiveRecall
            else { return nil }
            return $0.event.phraseID
        }
    }

    nonisolated private static func streak(
        reviews: [ProgressReviewRecord], now: Date, calendar: Calendar
    ) -> Int {
        let activeDays = Set(reviews.map { calendar.startOfDay(for: $0.event.timestamp) })
        var day = calendar.startOfDay(for: now)
        var result = 0
        while activeDays.contains(day) {
            result += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return result
    }

    nonisolated private static func learningPatterns(
        from reviews: [ProgressReviewRecord], limit: Int = 3
    ) -> [LearningPatternInsight] {
        var counts: [LearningErrorPattern: Int] = [:]
        var examples: [LearningErrorPattern: String] = [:]
        for review in reviews.filter({ $0.event.isProductive && !$0.userAnswer.isEmpty })
            .sorted(by: { $0.event.timestamp > $1.event.timestamp }).prefix(40) {
            let expected = words(review.expectedAnswer)
            let actual = words(review.userAnswer)
            if review.event.rating <= 2 {
                let pattern: LearningErrorPattern = actual.count < expected.count ? .omittedWords
                    : actual.count > expected.count ? .addedWords
                    : actual.sorted() == expected.sorted() && actual != expected ? .wordOrder : .wordForm
                counts[pattern, default: 0] += 1
                examples[pattern, default: review.event.sourceText] = review.event.sourceText
            }
        }
        return counts.map { LearningPatternInsight(
            pattern: $0.key, count: $0.value, exampleSource: examples[$0.key] ?? ""
        ) }.sorted {
            $0.count != $1.count ? $0.count > $1.count : $0.pattern.rawValue < $1.pattern.rawValue
        }.prefix(limit).map { $0 }
    }

    nonisolated private static func words(_ value: String) -> [String] {
        FuzzyMatcher.normalize(value).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    nonisolated private static func baseTopicName(_ name: String) -> String {
        name.replacingOccurrences(of: #"\s*\([A-Z]{2}\)$"#, with: "", options: .regularExpression)
    }
}
