import Foundation
import Testing
@testable import LanguageLearning

struct StoryPassportTests {
    private let episode = EpisodeLibrary.all[0]

    private func finished(supported: Bool = false, delayed: Bool = false, gap: Double? = nil) -> EpisodeRun {
        var run = EpisodeRun(episodeID: episode.id, contentVersion: episode.version, language: episode.language)
        run.stepIndex = episode.steps.count
        run.completedAt = .now
        run.isDelayedCheck = delayed
        run.exposureGapSeconds = gap
        run.attempts = episode.steps.filter { $0.kind != .model }.map {
            .init(stepID: $0.id, correct: true, supported: supported, spoken: false, timestamp: .now)
        }
        return run
    }

    private func passport(_ runs: [EpisodeRun], language: String = "ru") -> StoryPassport {
        var data = LearningExperience(); data.runs = runs
        return .init(language: language, experience: data)
    }

    @Test func supportedCompletionCollectsWithoutClaimingRecall() {
        let book = passport([finished(supported: true)])
        #expect(book.collectedCount == 1)
        #expect(book.recalledCount == 0)
        #expect(book.rememberedCount == 0)
        #expect(book.stamp(for: episode).label == "Postkarte gesammelt")
    }

    @Test func repeatedRunsCannotFarmCollectionRewards() {
        let run = finished()
        let book = passport([run, run, finished(), finished()])
        #expect(book.collectedCount == 1)
        #expect(book.recalledCount == 1)
        #expect(book.rememberedCount == 0)
    }

    @Test func sevenDayMarkerNeedsKnownGapAndAllUnaidedAnswers() {
        #expect(passport([finished(delayed: true)]).rememberedCount == 0)
        #expect(passport([finished(delayed: true, gap: 86_400)]).rememberedCount == 0)
        #expect(passport([finished(supported: true, delayed: true, gap: 7 * 86_400)]).rememberedCount == 0)
        #expect(passport([finished(delayed: true, gap: 7 * 86_400)]).rememberedCount == 1)
        #expect(passport([finished(gap: 7 * 86_400)]).rememberedCount == 0)
    }

    @Test func failedOrPartialAnswersDoNotEarnUnaidedMarker() {
        var run = finished()
        run.attempts.removeLast()
        #expect(passport([run]).recalledCount == 0)
        run = finished()
        run.attempts[0] = .init(stepID: run.attempts[0].stepID, correct: false, supported: false, spoken: false, timestamp: .now)
        #expect(passport([run]).recalledCount == 0)
    }

    @Test func calibrationAndUnfinishedRoundsAreNotPostcards() {
        var calibration = finished(); calibration.calibration = true
        var paused = finished(); paused.completedAt = nil; paused.stepIndex = 2
        var ended = finished(); ended.endedAt = .now
        #expect(passport([calibration, paused, ended]).collectedCount == 0)
    }

    @Test func languageVersionAndInvalidAttemptsAreIsolated() {
        #expect(passport([finished()], language: "ar").collectedCount == 0)
        var run = finished(); run.attempts.append(run.attempts[0])
        #expect(passport([run]).collectedCount == 0)
        var data = LearningExperience(); data.runs = [finished()]
        let base = episode
        let newVersion = LearningEpisode(id: base.id, version: 2, language: base.language, title: base.title,
            outcome: base.outcome, hook: base.hook, symbol: base.symbol, interest: base.interest, topicTags: base.topicTags, steps: base.steps)
        #expect(StoryPassport(language: "ru", experience: data, episodes: [newVersion]).collectedCount == 0)
    }

    @Test func earnedEvidenceSurvivesLaterSupportedPracticeAndEventDeletion() {
        let book = passport([finished(delayed: true, gap: 7 * 86_400), finished(supported: true)])
        #expect(book.rememberedCount == 1)
        #expect(book.stamp(for: episode).label == "Nach 7 Tagen abgerufen")
    }

    @Test func existingBackupRoundTripReconstructsSameCollection() throws {
        var data = LearningExperience(); data.runs = [finished()]
        let restored = try JSONDecoder().decode(LearningExperience.self, from: JSONEncoder().encode(data))
        #expect(StoryPassport(language: "ru", experience: restored).stamp(for: episode) == passport(data.runs).stamp(for: episode))
    }
}
