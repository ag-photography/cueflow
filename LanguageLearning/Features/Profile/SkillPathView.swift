import SwiftData
import SwiftUI

struct SkillPathView: View {
    @Query private var topics: [Topic]
    @Query private var reviews: [Review]
    @Query private var settings: [AppSettings]

    private var languageCode: String { settings.first?.activeLanguageCode ?? "ru" }
    private var events: [LearningEvent] {
        LearningMotivation.events(from: reviews.filter {
            $0.card?.phrase?.language?.code == languageCode
        })
    }
    private var phraseIDsByScenario: [String: Set<String>] {
        Dictionary(uniqueKeysWithValues: ScenarioDefinition.defaults.map { scenario in
            let matching = topics.filter {
                $0.language?.code == languageCode
                    && scenario.topicTerms.contains(baseTopicName($0.name))
            }
            return (scenario.id, Set(matching.flatMap { $0.phrases ?? [] }.map {
                String(describing: $0.persistentModelID)
            }))
        })
    }
    private var capabilities: [CapabilityProgress] {
        ProgressionSystem.capabilities(
            scenarios: ScenarioDefinition.defaults,
            phraseIDsByScenario: phraseIDsByScenario,
            events: events
        )
    }
    private var weeklyMissions: [WeeklyMissionProgress] {
        ProgressionSystem.weeklyMissions(events: events)
    }
    private var milestones: [LearningMilestone] {
        ProgressionSystem.milestones(
            capabilities: capabilities,
            weeklyMissions: weeklyMissions,
            events: events
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space.lg) {
                VStack(alignment: .leading, spacing: DS.space.xs) {
                    Text("Dein Weg ins Gespräch")
                        .font(.largeTitle.bold())
                        .foregroundStyle(DS.textPrimary)
                    Text("Jeder Schritt wächst nur durch Antworten, die du selbst formulierst.")
                        .font(.subheadline)
                        .foregroundStyle(DS.textSecondary)
                }
                .accessibilityElement(children: .combine)

                ForEach(Array(capabilities.enumerated()), id: \.element.id) { index, capability in
                    capabilityNode(capability, index: index)
                }

                weeklySection
                milestoneSection
            }
            .padding(DS.space.md)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(DS.surface0.ignoresSafeArea())
        .navigationTitle("Lernweg")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("skill-path")
    }

    private func capabilityNode(_ capability: CapabilityProgress, index: Int) -> some View {
        HStack(alignment: .top, spacing: DS.space.md) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(capability.isUnlocked ? DS.accent : DS.surface2)
                    Image(systemName: capability.isUnlocked ? capability.level.systemImage : "lock.fill")
                        .font(.headline)
                        .foregroundStyle(capability.isUnlocked ? .white : DS.textTertiary)
                }
                .frame(width: 48, height: 48)
                if index < capabilities.count - 1 {
                    Rectangle()
                        .fill(capability.level >= .use ? DS.accent.opacity(0.5) : DS.surface2)
                        .frame(width: 3, height: 84)
                }
            }

            VStack(alignment: .leading, spacing: DS.space.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(capability.scenario.title)
                            .font(.headline)
                            .foregroundStyle(DS.textPrimary)
                        Text(capability.isUnlocked ? capability.level.title : "Grundlagen zuerst")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(capability.isUnlocked ? DS.accent : DS.textTertiary)
                    }
                    Spacer()
                    Text("\(capability.productivePhraseCount)/\(capability.totalPhraseCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DS.textSecondary)
                }
                Text(capability.scenario.outcome)
                    .font(.subheadline)
                    .foregroundStyle(DS.textSecondary)
                ProgressView(value: capability.fraction)
                    .tint(capability.level == .fluent ? DS.gradePerfect : DS.accent)
                if let next = capability.nextLevel, capability.isUnlocked {
                    Text("Nächstes Ziel: \(next.title)")
                        .font(.caption)
                        .foregroundStyle(DS.textTertiary)
                }
            }
            .padding(DS.space.md)
            .background(DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.lg))
            .opacity(capability.isUnlocked ? 1 : 0.72)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(capability.scenario.title), \(capability.isUnlocked ? capability.level.title : "gesperrt"), \(capability.productivePhraseCount) von \(capability.totalPhraseCount) Ausdrücken")
    }

    private var weeklySection: some View {
        VStack(alignment: .leading, spacing: DS.space.md) {
            Text("Diese Woche")
                .font(.title2.bold())
                .foregroundStyle(DS.textPrimary)
            ForEach(weeklyMissions) { mission in
                HStack(spacing: DS.space.sm) {
                    Image(systemName: mission.isComplete ? "checkmark.circle.fill" : mission.systemImage)
                        .foregroundStyle(mission.isComplete ? DS.gradePerfect : DS.accent)
                        .frame(width: 36, height: 36)
                        .background((mission.isComplete ? DS.gradePerfect : DS.accent).opacity(0.1))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(mission.title).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(min(mission.current, mission.target))/\(mission.target)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(DS.textSecondary)
                        }
                        ProgressView(value: mission.fraction)
                            .tint(mission.isComplete ? DS.gradePerfect : DS.accent)
                        Text(mission.detail).font(.caption).foregroundStyle(DS.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(DS.space.md)
        .background(DS.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.lg))
    }

    private var milestoneSection: some View {
        VStack(alignment: .leading, spacing: DS.space.md) {
            HStack {
                Text("Deine Sammlung")
                    .font(.title2.bold())
                    .foregroundStyle(DS.textPrimary)
                Spacer()
                Text("\(milestones.filter(\.isEarned).count)/\(milestones.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DS.textSecondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: DS.space.sm)], spacing: DS.space.sm) {
                ForEach(milestones) { milestone in
                    VStack(spacing: DS.space.sm) {
                        Image(systemName: milestone.isEarned ? milestone.systemImage : "lock.fill")
                            .font(.title2)
                            .foregroundStyle(milestone.isEarned ? DS.accent : DS.textTertiary)
                            .frame(width: 52, height: 52)
                            .background((milestone.isEarned ? DS.accent : DS.textTertiary).opacity(0.1))
                            .clipShape(Circle())
                        Text(milestone.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DS.textPrimary)
                            .multilineTextAlignment(.center)
                        Text(milestone.detail)
                            .font(.caption2)
                            .foregroundStyle(DS.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(DS.space.sm)
                    .frame(maxWidth: .infinity, minHeight: 174)
                    .background(DS.surface1)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
                    .opacity(milestone.isEarned ? 1 : 0.65)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(milestone.title), \(milestone.isEarned ? "erreicht" : "noch nicht erreicht")")
                }
            }
        }
    }

    private func baseTopicName(_ name: String) -> String {
        name.replacingOccurrences(of: #"\s*\([A-Z]{2}\)$"#, with: "", options: .regularExpression)
    }
}
