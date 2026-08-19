import Foundation
import SwiftData

/// The derived model behind the Lernweg screen.
///
/// Built once per refresh rather than per render. `ProgressionSystem` walks the
/// whole event list three times over (capabilities, weekly missions,
/// milestones), so recomputing it inside `body` — and once more inside the
/// capability `ForEach` — multiplied that by every node on screen.
struct SkillPathModel {
    var capabilities: [CapabilityProgress] = []
    var weeklyMissions: [WeeklyMissionProgress] = []
    var milestones: [LearningMilestone] = []

    init() {}

    @MainActor
    init(topics: [Topic], languageCode: String, events: [LearningEvent]) {
        // Each topic's phrases are faulted once here, not once per scenario.
        let languageTopics = topics.filter { $0.language?.code == languageCode }
        var phraseIDsByTopic: [PersistentIdentifier: Set<ContentID>] = [:]
        var baseNameByTopic: [PersistentIdentifier: String] = [:]
        for topic in languageTopics {
            phraseIDsByTopic[topic.persistentModelID] = Set((topic.phrases ?? []).map(\.contentID))
            baseNameByTopic[topic.persistentModelID] = Self.baseTopicName(topic.name)
        }

        let phraseIDsByScenario = Dictionary(
            uniqueKeysWithValues: ScenarioDefinition.defaults.map { scenario in
                let matching = languageTopics.filter {
                    scenario.topicTerms.contains(baseNameByTopic[$0.persistentModelID] ?? "")
                }
                return (
                    scenario.id,
                    Set(matching.flatMap { phraseIDsByTopic[$0.persistentModelID] ?? [] })
                )
            }
        )

        capabilities = ProgressionSystem.capabilities(
            scenarios: ScenarioDefinition.defaults,
            phraseIDsByScenario: phraseIDsByScenario,
            events: events
        )
        weeklyMissions = ProgressionSystem.weeklyMissions(events: events)
        milestones = ProgressionSystem.milestones(
            capabilities: capabilities,
            weeklyMissions: weeklyMissions,
            events: events
        )
    }

    private static func baseTopicName(_ name: String) -> String {
        name.replacingOccurrences(
            of: #"\s*\([A-Z]{2}\)$"#,
            with: "",
            options: .regularExpression
        )
    }
}
