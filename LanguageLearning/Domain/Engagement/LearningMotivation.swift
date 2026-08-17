import Foundation

enum LearningExercise: String {
    case speech = "speakDeToRu"
    case typing = "typeDeToRu"
    case choice = "chooseDeToRu"
    case flip = "flipDeToRu"
}

struct LearningEvent: Equatable {
    let timestamp: Date
    let phraseID: String
    let sourceText: String
    let topicIDs: Set<String>
    let exercise: LearningExercise?
    let rating: Int
    let gradeTier: Int
    let responseTimeMs: Int
    let spokenWordCount: Int

    var isProductive: Bool {
        gradeTier >= 1 && (exercise == .speech || exercise == .typing)
    }

    var isStrongProductiveRecall: Bool { isProductive && rating >= 3 && gradeTier >= 3 }
    var isSpoken: Bool { gradeTier >= 1 && exercise == .speech }
}

enum DailyQuestKind: String, CaseIterable, Identifiable {
    case retrieve
    case speak
    case deepenMission

    var id: String { rawValue }
}

struct DailyQuestProgress: Identifiable, Equatable {
    let kind: DailyQuestKind
    let title: String
    let detail: String
    let systemImage: String
    let current: Int
    let target: Int

    var id: String { kind.id }
    var isComplete: Bool { current >= target }
    var fraction: Double { min(1, Double(current) / Double(max(1, target))) }
}

struct ImprovingExpression: Equatable {
    let phraseID: String
    let sourceText: String
    let improvedAt: Date
}

enum LearningMotivation {
    static func dailyQuests(
        events: [LearningEvent],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [DailyQuestProgress] {
        let today = events.filter { calendar.isDate($0.timestamp, inSameDayAs: now) }
        let productive = today.filter(\.isProductive)
        let spokenWords = today.filter(\.isSpoken).reduce(0) { $0 + $1.spokenWordCount }
        let topicCounts = productive
            .flatMap { event in event.topicIDs.map { (topic: $0, count: 1) } }
            .reduce(into: [String: Int]()) { $0[$1.topic, default: 0] += $1.count }
        let deepestMission = topicCounts.values.max() ?? 0

        return [
            DailyQuestProgress(
                kind: .retrieve,
                title: "Selbst abrufen",
                detail: "8 Antworten ohne Lösung produzieren",
                systemImage: "text.bubble.fill",
                current: productive.count,
                target: 8
            ),
            DailyQuestProgress(
                kind: .speak,
                title: "Stimme einsetzen",
                detail: "40 Wörter laut sprechen",
                systemImage: "waveform",
                current: spokenWords,
                target: 40
            ),
            DailyQuestProgress(
                kind: .deepenMission,
                title: "Eine Mission vertiefen",
                detail: "5 produktive Antworten in einem Thema",
                systemImage: "map.fill",
                current: deepestMission,
                target: 5
            ),
        ]
    }

    static func fastestStrongRecall(events: [LearningEvent]) -> LearningEvent? {
        events
            .filter { $0.isStrongProductiveRecall && $0.responseTimeMs > 0 }
            .min { $0.responseTimeMs < $1.responseTimeMs }
    }

    /// Finds the most recent phrase that previously failed and was later
    /// produced successfully. This makes comeback copy a measured event.
    static func mostRecentImprovement(events: [LearningEvent]) -> ImprovingExpression? {
        let grouped = Dictionary(grouping: events, by: \.phraseID)
        return grouped.compactMap { phraseID, phraseEvents -> ImprovingExpression? in
            let ordered = phraseEvents.sorted { $0.timestamp < $1.timestamp }
            guard let successIndex = ordered.indices.reversed().first(where: {
                ordered[$0].isStrongProductiveRecall
            }), ordered[..<successIndex].contains(where: { $0.rating <= 2 }) else { return nil }
            let success = ordered[successIndex]
            return ImprovingExpression(
                phraseID: phraseID,
                sourceText: success.sourceText,
                improvedAt: success.timestamp
            )
        }.max { $0.improvedAt < $1.improvedAt }
    }

    static func strongRecallFraction(events: [LearningEvent], phraseIDs: Set<String>) -> Double {
        guard !phraseIDs.isEmpty else { return 0 }
        let strongIDs = Set(events.lazy.filter(\.isStrongProductiveRecall).map(\.phraseID))
        return Double(strongIDs.intersection(phraseIDs).count) / Double(phraseIDs.count)
    }

    static func events(from reviews: [Review]) -> [LearningEvent] {
        reviews.compactMap { review in
            guard let phrase = review.card?.phrase else { return nil }
            return LearningEvent(
                timestamp: review.timestamp,
                phraseID: String(describing: phrase.persistentModelID),
                sourceText: phrase.sourceText,
                topicIDs: Set(phrase.topics.map { String(describing: $0.persistentModelID) }),
                exercise: LearningExercise(rawValue: review.modeRaw),
                rating: review.rating,
                gradeTier: review.gradeTier,
                responseTimeMs: review.responseTimeMs,
                spokenWordCount: review.userAnswer.split(whereSeparator: { $0.isWhitespace }).count
            )
        }
    }
}

struct ScenarioDefinition: Identifiable, Equatable {
    let id: String
    let title: String
    let outcome: String
    let systemImage: String
    let topicTerms: Set<String>

    static let defaults: [ScenarioDefinition] = [
        ScenarioDefinition(
            id: "first-conversations",
            title: "Erste Gespräche",
            outcome: "Begrüßen, höflich reagieren und dich vorstellen",
            systemImage: "hand.wave.fill",
            topicTerms: ["Begrüßung", "Höflichkeit", "Sich vorstellen", "Verständigung"]
        ),
        ScenarioDefinition(
            id: "cafe-food",
            title: "Café & Essen",
            outcome: "Bestellen, nachfragen und Wünsche äußern",
            systemImage: "cup.and.saucer.fill",
            topicTerms: ["Im Restaurant", "Essen & Trinken"]
        ),
        ScenarioDefinition(
            id: "getting-around",
            title: "Unterwegs",
            outcome: "Den Weg finden, fahren und einkaufen",
            systemImage: "map.fill",
            topicTerms: ["Wegbeschreibung", "Verkehr", "Einkaufen"]
        ),
        ScenarioDefinition(
            id: "daily-life",
            title: "Alltag",
            outcome: "Über Familie, Zuhause, Zeit und Wetter sprechen",
            systemImage: "house.fill",
            topicTerms: ["Familie", "Zuhause", "Zeit", "Wetter"]
        ),
    ]
}
