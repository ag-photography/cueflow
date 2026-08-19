import SwiftData
import SwiftUI

struct SkillPathView: View {
    @Environment(\.modelContext) private var context
    @Query private var topics: [Topic]
    @Query private var reviews: [Review]
    @Query private var settings: [AppSettings]

    /// Precomputed once per refresh. Every value here used to be a computed
    /// property: `events` rebuilt the whole learning-event list from every
    /// review, `capabilities` was read again inside its own `ForEach`, and
    /// `milestones` pulled all three — so one render pass rebuilt the event list
    /// half a dozen times over.
    @State private var model = SkillPathModel()
    @State private var modelKey = ""

    private var languageCode: String { settings.first?.activeLanguageCode ?? "ru" }
    private var capabilities: [CapabilityProgress] { model.capabilities }
    private var weeklyMissions: [WeeklyMissionProgress] { model.weeklyMissions }
    private var milestones: [LearningMilestone] { model.milestones }

    private var refreshKey: String {
        "\(languageCode)|\(topics.count)|\(reviews.count)|\(LearningDataCache.shared.revision)"
    }

    @MainActor
    private func refresh() async {
        let key = refreshKey
        guard modelKey != key else { return }
        let cache = LearningDataCache.shared
        var events = cache.events(languageCode: languageCode)
        if !cache.isPrimed {
            events = LearningMotivation.events(from: reviews.filter {
                $0.card?.phrase?.language?.code == languageCode
            })
        }
        guard !Task.isCancelled else { return }
        model = SkillPathModel(topics: topics, languageCode: languageCode, events: events)
        modelKey = key
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
        .task(id: refreshKey) { await refresh() }
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
}
