import Foundation

/// Cosmetic collection, derived from durable learning history. No currency,
/// extra FSRS grades, streak loss or reward for replaying the same scene.
struct StoryPassport {
    struct Stamp: Equatable {
        let collected: Bool
        let recalled: Bool
        let remembered: Bool

        var label: String {
            if remembered { return "Nach 7 Tagen abgerufen" }
            if recalled { return "Ohne Hilfe abgerufen" }
            if collected { return "Situation geübt" }
            return "Noch nicht geübt"
        }
    }

    let episodes: [LearningEpisode]
    private let runs: [EpisodeRun]

    init(language: String, experience: LearningExperience, episodes: [LearningEpisode] = EpisodeLibrary.all) {
        self.episodes = episodes.filter { $0.language == language && $0.validationErrors.isEmpty }
        self.runs = experience.runs.filter { $0.language == language && $0.calibration != true }
    }

    func stamp(for episode: LearningEpisode) -> Stamp {
        guard episodes.contains(where: { $0.id == episode.id && $0.version == episode.version }) else {
            return .init(collected: false, recalled: false, remembered: false)
        }
        let finished = runs.filter { $0.completedAt != nil && $0.endedAt == nil && $0.isValid(for: episode) }
        let prompts = Set(episode.steps.filter { $0.kind != .model }.map(\.id))
        // All authored answer prompts in one completed run. Partial branches,
        // repeated callbacks, supported answers and calibration cannot award it.
        func independentlyAnswered(_ run: EpisodeRun) -> Bool {
            !prompts.isEmpty && prompts.isSubset(of: Set(run.attempts.filter { $0.correct && !$0.supported }.map(\.stepID)))
        }
        return .init(
            collected: !finished.isEmpty,
            recalled: finished.contains(where: independentlyAnswered),
            remembered: finished.contains { $0.isDelayedCheck && ($0.exposureGapSeconds ?? 0) >= 7 * 86_400 && independentlyAnswered($0) }
        )
    }

    var collectedCount: Int { episodes.filter { stamp(for: $0).collected }.count }
    var recalledCount: Int { episodes.filter { stamp(for: $0).recalled }.count }
    var rememberedCount: Int { episodes.filter { stamp(for: $0).remembered }.count }
}
