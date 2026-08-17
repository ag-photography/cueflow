import Foundation

struct ProgressDayStat: Identifiable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    let count: Int
}

struct ProgressTopicStat: Identifiable, Equatable, Sendable {
    let id: String
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

    static let empty = ProgressDashboardSnapshot(
        scenarioFractions: [:], learningPatterns: [], fastestRecall: nil,
        phrasesProducedUnaided: 0, dueNow: 0, reviewedToday: 0,
        currentStreak: 0, newCount: 0, learningCount: 0,
        reviewCount: 0, relearningCount: 0, weekly: [], spokenWeekly: [],
        spokenWordsTodayPractice: 0, fluencyLabel: nil,
        reviewsByLanguage: [:], topics: []
    )
}

private struct ProgressCardRecord: Sendable {
    let phraseID: String
    let state: LearningState
    let dueDate: Date
}

private struct ProgressReviewRecord: Sendable {
    let languageCode: String
    let event: LearningEvent
    let expectedAnswer: String
    let userAnswer: String
}

private struct ProgressTopicRecord: Sendable {
    let id: String
    let name: String
    let languageCode: String
    let isActive: Bool
    let phraseIDs: Set<String>
}

/// A process-local read cache for navigation destinations. Today already owns
/// the live SwiftData queries needed by the primary action, so Library and
/// Progress can reuse those model instances instead of materializing the same
/// review graph again during a tab transition.
@MainActor
final class LearningDataCache {
    static let shared = LearningDataCache()

    private(set) var cards: [StudyCard] = []
    private(set) var reviews: [Review] = []
    private var eventsByLanguage: [String: [LearningEvent]] = [:]
    private(set) var isPrimed = false
    private(set) var revision = 0
    private var fingerprint: Int?
    private var dashboardTask: Task<[String: ProgressDashboardSnapshot], Never>?

    private init() {}

    func update(cards: [StudyCard], reviews: [Review], topics: [Topic]) {
        var signature = Hasher()
        signature.combine(cards.count)
        signature.combine(reviews.count)
        for topic in topics {
            signature.combine(String(describing: topic.persistentModelID))
            signature.combine(topic.name)
            signature.combine(topic.isActive)
            signature.combine(topic.phrases?.count ?? 0)
        }
        let nextFingerprint = signature.finalize()
        guard fingerprint != nextFingerprint else { return }
        fingerprint = nextFingerprint

        self.cards = cards
        self.reviews = reviews
        let reviewRecords = reviews.compactMap { review -> ProgressReviewRecord? in
            guard let phrase = review.card?.phrase else { return nil }
            return ProgressReviewRecord(
                languageCode: phrase.language?.code ?? "",
                event: LearningEvent(
                    timestamp: review.timestamp,
                    phraseID: String(describing: phrase.persistentModelID),
                    sourceText: phrase.sourceText,
                    topicIDs: Set((phrase.topics ?? []).map { String(describing: $0.persistentModelID) }),
                    exercise: LearningExercise(rawValue: review.modeRaw),
                    rating: review.rating,
                    gradeTier: review.gradeTier,
                    responseTimeMs: review.responseTimeMs,
                    spokenWordCount: review.userAnswer.split(whereSeparator: \.isWhitespace).count
                ),
                expectedAnswer: phrase.targetText,
                userAnswer: review.userAnswer
            )
        }
        let cardRecords = cards.compactMap { card -> ProgressCardRecord? in
            guard let phrase = card.phrase else { return nil }
            return ProgressCardRecord(
                phraseID: String(describing: phrase.persistentModelID),
                state: card.state,
                dueDate: card.dueDate
            )
        }
        let topicRecords = topics.map {
            ProgressTopicRecord(
                id: String(describing: $0.persistentModelID),
                name: $0.name,
                languageCode: $0.language?.code ?? "",
                isActive: $0.isActive,
                phraseIDs: Set(($0.phrases ?? []).map { String(describing: $0.persistentModelID) })
            )
        }
        eventsByLanguage = Dictionary(grouping: reviewRecords, by: \.languageCode)
            .mapValues { $0.map(\.event) }
        revision += 1
        dashboardTask?.cancel()
        dashboardTask = Task.detached(priority: .utility) {
            let codes = Set(reviewRecords.map(\.languageCode) + topicRecords.map(\.languageCode) + ["ru", "ar"])
            return Dictionary(uniqueKeysWithValues: codes.map { code in
                (code, Self.makeDashboard(
                    activeLanguageCode: code,
                    cards: cardRecords,
                    reviews: reviewRecords,
                    topics: topicRecords
                ))
            })
        }
        isPrimed = true
    }

    func dashboard(languageCode: String) async -> (revision: Int, snapshot: ProgressDashboardSnapshot) {
        let requestedRevision = revision
        guard let dashboardTask else { return (requestedRevision, .empty) }
        let snapshots = await dashboardTask.value
        return (requestedRevision, snapshots[languageCode] ?? .empty)
    }

    func events(languageCode: String) -> [LearningEvent] {
        eventsByLanguage[languageCode] ?? []
    }

    nonisolated private static func makeDashboard(
        activeLanguageCode: String,
        cards: [ProgressCardRecord],
        reviews: [ProgressReviewRecord],
        topics: [ProgressTopicRecord],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ProgressDashboardSnapshot {
        let events = reviews.filter { $0.languageCode == activeLanguageCode }.map(\.event)
        let startOfToday = calendar.startOfDay(for: now)
        let phraseStates = Dictionary(uniqueKeysWithValues: cards.map { ($0.phraseID, $0.state) })
        let weekly = dayStats(now: now, calendar: calendar) { start, end in
            reviews.count { $0.event.timestamp >= start && $0.event.timestamp < end }
        }
        let spoken = reviews.filter { $0.event.isSpoken }
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
            let ids = Set(topics.lazy.filter {
                $0.languageCode == activeLanguageCode
                    && scenario.topicTerms.contains(baseTopicName($0.name))
            }.flatMap(\.phraseIDs))
            return (scenario.id, LearningMotivation.strongRecallFraction(events: events, phraseIDs: ids))
        })
        let topicStats = topics.filter { !$0.phraseIDs.isEmpty }.map { topic in
            ProgressTopicStat(
                id: topic.id,
                name: topic.name,
                isActive: topic.isActive,
                practised: topic.phraseIDs.count { phraseStates[$0]?.isIntroduced == true },
                total: topic.phraseIDs.count
            )
        }.sorted {
            if $0.isActive != $1.isActive { return $0.isActive && !$1.isActive }
            return $0.name.localizedCompare($1.name) == .orderedAscending
        }

        return ProgressDashboardSnapshot(
            scenarioFractions: scenarioFractions,
            learningPatterns: learningPatterns(from: reviews.filter { $0.languageCode == activeLanguageCode }),
            fastestRecall: LearningMotivation.fastestStrongRecall(events: events),
            phrasesProducedUnaided: Set(reviewRecordsProductivePhraseIDs(reviews)).count,
            dueNow: cards.count { $0.dueDate <= now && $0.state != .new },
            reviewedToday: reviews.count { $0.event.timestamp >= startOfToday },
            currentStreak: streak(reviews: reviews, now: now, calendar: calendar),
            newCount: cards.count { $0.state == .new },
            learningCount: cards.count { $0.state == .learning },
            reviewCount: cards.count { $0.state == .review },
            relearningCount: cards.count { $0.state == .relearning },
            weekly: weekly,
            spokenWeekly: spokenWeekly,
            spokenWordsTodayPractice: spoken.lazy.filter { $0.event.timestamp >= startOfToday }
                .reduce(0) { $0 + $1.event.spokenWordCount },
            fluencyLabel: fluency,
            reviewsByLanguage: reviews.reduce(into: [:]) { $0[$1.languageCode, default: 0] += 1 },
            topics: topicStats
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
    ) -> [String] {
        reviews.compactMap {
            guard $0.event.gradeTier >= 3,
                  $0.event.exercise == .speech || $0.event.exercise == .typing
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
        for review in reviews.filter({ $0.event.gradeTier >= 1 && !$0.userAnswer.isEmpty })
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
            if review.event.responseTimeMs >= 9_000, review.event.rating >= 3,
               review.event.exercise == .speech {
                counts[.slowRetrieval, default: 0] += 1
                examples[.slowRetrieval, default: review.event.sourceText] = review.event.sourceText
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
