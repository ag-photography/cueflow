import Foundation
import SwiftData

/// The derived model behind the Bibliothek "Lernen" tab.
///
/// Every value here used to be a computed property read straight from `body`.
/// Because each scenario card asked which scenario was recommended, and that
/// answer needed every scenario's fraction, four cards produced sixteen
/// fraction computations — each one re-deriving and re-sorting the topic list
/// underneath it. Building the whole screen once, off the view, keeps it linear.
struct LibraryJourneys {
    struct ScenarioCard: Identifiable {
        let id: String
        let scenario: ScenarioDefinition
        let matchedTopics: [Topic]
        let fraction: Double
        let hasContent: Bool
        let isRecommended: Bool
    }

    struct MissionRow: Identifiable {
        let id: PersistentIdentifier
        let topic: Topic
        let name: String
        let isActive: Bool
        let total: Int
        let introduced: Int
        let fraction: Double
    }

    var scenarioCards: [ScenarioCard] = []
    var missionRows: [MissionRow] = []
    var tutorTopics: [Topic] = []
    var tutorIntroduced = 0
    var tutorTotal = 0
    var tutorNextLesson: Date?

    init() {}

    @MainActor
    init(topics: [Topic], languageCode: String, events: [LearningEvent]) {
        let learningTopics = topics
            .filter { $0.language?.code == languageCode && $0.parent == nil && !($0.phrases?.isEmpty ?? true) }
            .sorted {
                if $0.isActive != $1.isActive { return $0.isActive && !$1.isActive }
                return $0.name.localizedCompare($1.name) == .orderedAscending
            }

        // Fault each topic's phrases exactly once and keep the results.
        var phraseIDsByTopic: [PersistentIdentifier: Set<ContentID>] = [:]
        var introducedByTopic: [PersistentIdentifier: Int] = [:]
        var baseNameByTopic: [PersistentIdentifier: String] = [:]
        for topic in learningTopics {
            let phrases = topic.phrases ?? []
            phraseIDsByTopic[topic.persistentModelID] = Set(phrases.map(\.contentID))
            introducedByTopic[topic.persistentModelID] = phrases.count { phrase in
                phrase.cards?.first?.state.isIntroduced == true
            }
            baseNameByTopic[topic.persistentModelID] = Self.baseTopicName(topic.name)
        }

        // Built once instead of per fraction — this set is the expensive half of
        // `LearningMotivation.strongRecallFraction`.
        let strongIDs = Set(events.lazy.filter(\.isStrongProductiveRecall).map(\.phraseID))
        func fraction(_ ids: Set<ContentID>) -> Double {
            guard !ids.isEmpty else { return 0 }
            return Double(strongIDs.intersection(ids).count) / Double(ids.count)
        }

        var matchedByScenario: [String: [Topic]] = [:]
        var idsByScenario: [String: Set<ContentID>] = [:]
        var fractionByScenario: [String: Double] = [:]
        for scenario in ScenarioDefinition.defaults {
            let matched = learningTopics.filter {
                scenario.topicTerms.contains(baseNameByTopic[$0.persistentModelID] ?? "")
            }
            let ids = Set(matched.flatMap { phraseIDsByTopic[$0.persistentModelID] ?? [] })
            matchedByScenario[scenario.id] = matched
            idsByScenario[scenario.id] = ids
            fractionByScenario[scenario.id] = fraction(ids)
        }
        let recommendedID = CurriculumPlanner.recommendation(
            from: CurriculumPlanner.progress(
                scenarios: ScenarioDefinition.defaults,
                fractions: fractionByScenario
            )
        )?.id

        scenarioCards = ScenarioDefinition.defaults.map { scenario in
            ScenarioCard(
                id: scenario.id,
                scenario: scenario,
                matchedTopics: matchedByScenario[scenario.id] ?? [],
                fraction: fractionByScenario[scenario.id] ?? 0,
                hasContent: !(idsByScenario[scenario.id] ?? []).isEmpty,
                isRecommended: recommendedID == scenario.id
            )
        }

        missionRows = learningTopics.map { topic in
            let ids = phraseIDsByTopic[topic.persistentModelID] ?? []
            return MissionRow(
                id: topic.persistentModelID,
                topic: topic,
                name: topic.name,
                isActive: topic.isActive,
                total: ids.count,
                introduced: introducedByTopic[topic.persistentModelID] ?? 0,
                fraction: fraction(ids)
            )
        }

        tutorTopics = learningTopics.filter(\.isTutorFocusActive).sorted {
            ($0.tutorNextLessonAt ?? .distantFuture) < ($1.tutorNextLessonAt ?? .distantFuture)
        }
        let tutorPhraseIDs = Set(tutorTopics.flatMap { phraseIDsByTopic[$0.persistentModelID] ?? [] })
        tutorTotal = tutorPhraseIDs.count
        tutorIntroduced = tutorTopics.reduce(into: Set<ContentID>()) { introduced, topic in
            for phrase in topic.phrases ?? [] where phrase.cards?.contains(where: { $0.state.isIntroduced }) == true {
                introduced.insert(phrase.contentID)
            }
        }.count
        tutorNextLesson = tutorTopics.compactMap(\.tutorNextLessonAt).min()
    }

    private static func baseTopicName(_ name: String) -> String {
        name.replacingOccurrences(
            of: #"\s*\([A-Z]{2}\)$"#,
            with: "",
            options: .regularExpression
        )
    }
}
