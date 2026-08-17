import Foundation

enum CapabilityLevel: Int, CaseIterable, Comparable, Sendable {
    case discover
    case practise
    case use
    case fluent

    static func < (lhs: CapabilityLevel, rhs: CapabilityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .discover: return "Entdecken"
        case .practise: return "Festigen"
        case .use: return "Anwenden"
        case .fluent: return "Gesprächsbereit"
        }
    }

    var systemImage: String {
        switch self {
        case .discover: return "sparkles"
        case .practise: return "arrow.triangle.2.circlepath"
        case .use: return "bubble.left.and.bubble.right.fill"
        case .fluent: return "checkmark.seal.fill"
        }
    }
}

struct CapabilityProgress: Identifiable, Equatable, Sendable {
    let scenario: ScenarioDefinition
    let fraction: Double
    let level: CapabilityLevel
    let isUnlocked: Bool
    let productivePhraseCount: Int
    let totalPhraseCount: Int

    var id: String { scenario.id }
    var nextLevel: CapabilityLevel? {
        CapabilityLevel(rawValue: min(CapabilityLevel.fluent.rawValue, level.rawValue + 1))
            .flatMap { $0 == level ? nil : $0 }
    }
}

enum WeeklyMissionKind: String, CaseIterable, Identifiable, Sendable {
    case productiveDays
    case recoveredPhrases
    case conversationBreadth

    var id: String { rawValue }
}

struct WeeklyMissionProgress: Identifiable, Equatable, Sendable {
    let kind: WeeklyMissionKind
    let title: String
    let detail: String
    let systemImage: String
    let current: Int
    let target: Int

    var id: String { kind.id }
    var fraction: Double { min(1, Double(current) / Double(max(1, target))) }
    var isComplete: Bool { current >= target }
}

struct LearningMilestone: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let isEarned: Bool
}

enum ProgressionSystem {
    static func level(for fraction: Double) -> CapabilityLevel {
        switch fraction {
        case 0.8...: return .fluent
        case 0.4...: return .use
        case 0.01...: return .practise
        default: return .discover
        }
    }

    static func capabilities(
        scenarios: [ScenarioDefinition],
        phraseIDsByScenario: [String: Set<String>],
        events: [LearningEvent]
    ) -> [CapabilityProgress] {
        let strongIDs = Set(events.lazy.filter(\.isStrongProductiveRecall).map(\.phraseID))
        let fractions = Dictionary(uniqueKeysWithValues: scenarios.map { scenario in
            let phraseIDs = phraseIDsByScenario[scenario.id] ?? []
            let fraction = phraseIDs.isEmpty
                ? 0
                : Double(strongIDs.intersection(phraseIDs).count) / Double(phraseIDs.count)
            return (scenario.id, fraction)
        })

        return scenarios.map { scenario in
            let phraseIDs = phraseIDsByScenario[scenario.id] ?? []
            let fraction = fractions[scenario.id] ?? 0
            let unlocked = scenario.prerequisiteIDs.allSatisfy { (fractions[$0] ?? 0) >= 0.4 }
            return CapabilityProgress(
                scenario: scenario,
                fraction: fraction,
                level: level(for: fraction),
                isUnlocked: unlocked,
                productivePhraseCount: strongIDs.intersection(phraseIDs).count,
                totalPhraseCount: phraseIDs.count
            )
        }
    }

    static func weeklyMissions(
        events: [LearningEvent],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [WeeklyMissionProgress] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        let week = events.filter { interval.contains($0.timestamp) }
        let productive = week.filter { $0.isProductive && $0.rating >= 3 }
        let productiveDays = Set(productive.map { calendar.startOfDay(for: $0.timestamp) }).count

        let grouped = Dictionary(grouping: week, by: \.phraseID)
        let recovered = grouped.values.filter { phraseEvents in
            let ordered = phraseEvents.sorted { $0.timestamp < $1.timestamp }
            guard let strongIndex = ordered.indices.last(where: { ordered[$0].isStrongProductiveRecall }) else {
                return false
            }
            return ordered[..<strongIndex].contains { $0.rating <= 2 }
        }.count

        let productiveTopics = Set(productive.flatMap(\.topicIDs)).count
        return [
            WeeklyMissionProgress(
                kind: .productiveDays,
                title: "Drei echte Sprechtage",
                detail: "An drei Tagen selbst formulieren",
                systemImage: "calendar.badge.checkmark",
                current: productiveDays,
                target: 3
            ),
            WeeklyMissionProgress(
                kind: .recoveredPhrases,
                title: "Zurück ins Gedächtnis",
                detail: "Drei schwierige Ausdrücke wieder sicher abrufen",
                systemImage: "arrow.uturn.up.circle.fill",
                current: recovered,
                target: 3
            ),
            WeeklyMissionProgress(
                kind: .conversationBreadth,
                title: "Alltag erweitern",
                detail: "In drei Themen produktiv antworten",
                systemImage: "map.fill",
                current: productiveTopics,
                target: 3
            )
        ]
    }

    static func milestones(
        capabilities: [CapabilityProgress],
        weeklyMissions: [WeeklyMissionProgress],
        events: [LearningEvent]
    ) -> [LearningMilestone] {
        let strongCount = Set(events.filter(\.isStrongProductiveRecall).map(\.phraseID)).count
        let appliedScenarios = capabilities.filter { $0.level >= .use }.count
        return [
            LearningMilestone(
                id: "first-recall", title: "Erster eigener Satz",
                detail: "Einen Ausdruck ohne Lösung sicher abrufen",
                systemImage: "quote.bubble.fill", isEarned: strongCount >= 1
            ),
            LearningMilestone(
                id: "twenty-recalls", title: "Aktiver Wortschatz",
                detail: "20 verschiedene Ausdrücke produktiv abrufen",
                systemImage: "text.book.closed.fill", isEarned: strongCount >= 20
            ),
            LearningMilestone(
                id: "three-scenarios", title: "Alltagsentdecker:in",
                detail: "Drei Situationen auf Anwenden bringen",
                systemImage: "map.fill", isEarned: appliedScenarios >= 3
            ),
            LearningMilestone(
                id: "conversation-ready", title: "Gesprächsbereit",
                detail: "Eine Situation bis Gesprächsbereit entwickeln",
                systemImage: "person.2.wave.2.fill",
                isEarned: capabilities.contains { $0.level == .fluent }
            ),
            LearningMilestone(
                id: "weekly-flow", title: "Woche im Flow",
                detail: "Alle drei Wochenmissionen erfüllen",
                systemImage: "calendar.badge.checkmark",
                isEarned: !weeklyMissions.isEmpty && weeklyMissions.allSatisfy(\.isComplete)
            )
        ]
    }
}
