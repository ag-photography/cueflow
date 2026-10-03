import Foundation
import SwiftData
import Testing
@testable import LanguageLearning

@MainActor
struct LearningExperienceTests {
    @Test func realGraderExactAnswersCountWithoutAI() {
        let result = GraderService().grade(expected: "Я люблю осень", actual: "Я люблю осень!", acceptedAlternatives: [], responseTimeMs: 8_000)
        #expect(result.tier == 1)
        #expect(LearningEvidencePolicy.successful(exercise: .typing, tier: result.tier, rating: result.autoGrade.suggestedRating, evidence: nil))
        for support in [AttemptEvidence.Support.tiles, .revealed, .retry, .selfReported] {
            let evidence = AttemptEvidence(support: support, inputWasSpeech: false, assessedCorrect: true, gradingMethod: 1)
            #expect(!LearningEvidencePolicy.successful(exercise: .typing, tier: 1, rating: 4, evidence: evidence))
        }
        #expect(!LearningEvidencePolicy.successful(exercise: .choice, tier: 1, rating: 4, evidence: nil))
        #expect(!LearningEvidencePolicy.successful(exercise: .speech, tier: 2, rating: 2, evidence: nil))
    }

    @Test func fiveCardPlanStaysBoundedAndReservesTutorSlots() throws {
        let topic = Topic(name: "Jahreszeiten", isActive: true)
        let due = (0..<100).map { n -> StudyCard in
            let card = StudyCard(phrase: Phrase(sourceText: "alt \(n)", targetText: "старый \(n)"))
            card.state = .review
            card.dueDate = .distantPast
            return card
        }
        let fresh = (0..<5).map { n in StudyCard(phrase: Phrase(sourceText: "neu \(n)", targetText: "новый \(n)", topics: [topic])) }
        let tutorIDs = Set(fresh.compactMap { $0.phrase?.contentID })
        let selected = SessionPlanner.cards(from: due + fresh, reviews: [], target: 5, dailyNewLimit: 2, tutorIDs: tutorIDs)
        #expect(selected.count == 5)
        #expect(selected.filter { $0.state == .new }.count == 2)
        #expect(Set(selected.map(\.contentID)).count == 5)
        #expect(selected.first?.state == .new)
        let capped = SessionPlanner.cards(from: due + fresh, reviews: [], target: 5, dailyNewLimit: 0, tutorIDs: tutorIDs)
        #expect(capped.allSatisfy { $0.state != .new })
    }

    @Test func recognitionExposureDoesNotConsumeNewAllowanceTwice() {
        let topic = Topic(name: "Wetter", isActive: true)
        let card = StudyCard(phrase: Phrase(sourceText: "Winter", targetText: "зима", topics: [topic]))
        let review = Review(card: card, rating: 3, autoGradeRating: 3, userAnswer: "зима", mode: .chooseDeToRu, responseTimeMs: 1000, gradeTier: 0, wasNew: true)
        let followup = SessionPlanner.cards(from: [card], reviews: [review], target: 5, dailyNewLimit: 0, tutorIDs: [])
        #expect(followup.count == 1)
        #expect(card.state == .new)
        #expect(card.reps == 0)
    }

    @Test func journalRoundTripResumeAndIdempotentMerge() throws {
        var data = LearningExperience()
        var run = EpisodeRun(episodeID: "ru-seasons-1", contentVersion: 1, language: "ru")
        run.stepIndex = 3
        run.modelRevealed = true
        run.attempts = [.init(stepID: "recall-a", correct: true, supported: false, spoken: false, timestamp: .now)]
        data.save(run)
        data.event("session_paused", run: run)
        data.preferences["ru"] = .init(purpose: "Beruf", quiet: true, weeklyDays: 4)
        let restored = try JSONDecoder().decode(LearningExperience.self, from: JSONEncoder().encode(data))
        data.merge(restored)
        data.merge(restored)
        #expect(data.runs.count == 1)
        #expect(data.events.count == 1)
        #expect(data.runs.first?.stepIndex == 3)
        #expect(data.runs.first?.modelRevealed == true)
        #expect(data.preference(for: "ru").quiet)
        #expect(data.preference(for: "ar").purpose == "Reisen")
        #expect(data.completed(in: "ru").isEmpty)
    }

    @Test func delayedChecksRequireElapsedTimeAndStayLanguageScoped() throws {
        let episode = try #require(EpisodeLibrary.all.first)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var run = EpisodeRun(episodeID: episode.id, contentVersion: episode.version, language: episode.language)
        run.completedAt = date
        var data = LearningExperience()
        data.save(run)
        #expect(!data.isCheckDue(episode, now: date.addingTimeInterval(23 * 3600)))
        #expect(data.isCheckDue(episode, now: date.addingTimeInterval(25 * 3600)))
        #expect(data.dueEpisode(language: "ar", now: date.addingTimeInterval(25 * 3600)) == nil)
        #expect(data.retainedCount(for: episode) == 0)
        var check = EpisodeRun(episodeID: episode.id, contentVersion: episode.version, language: episode.language)
        check.isDelayedCheck = true
        check.completedAt = date.addingTimeInterval(25 * 3600)
        data.save(check)
        #expect(!data.isCheckDue(episode, now: date.addingTimeInterval(2 * 86_400)))
        #expect(data.isCheckDue(episode, now: date.addingTimeInterval(9 * 86_400)))
    }

    @Test func pilotContentValidatesAndTutorTopicWinsRecommendation() {
        #expect(EpisodeLibrary.all.count == 9)
        #expect(Set(EpisodeLibrary.all.map(\.id)).count == EpisodeLibrary.all.count)
        #expect(EpisodeLibrary.all.allSatisfy { $0.validationErrors.isEmpty })
        #expect(EpisodeLibrary.recommendation(language: "ru", purpose: "Beruf", focusNames: ["Jahreszeiten"], completed: [])?.id == "ru-seasons-1")
        #expect(EpisodeLibrary.recommendation(language: "ar", purpose: "Beruf", focusNames: [], completed: [])?.id == "ar-work-1")
        #expect(EpisodeLibrary.recommendation(language: "xx", purpose: "Reisen", focusNames: [], completed: []) == nil)
    }

    @Test func pacingUsesEachDeadlineAndDeduplicatesSharedPhrases() throws {
        let now = Date.now
        let data = try #require(TutorFocusPlanner.pacing(focusedTopics: [
            .init(phraseIDs: ["a", "b"], nextLessonAt: now.addingTimeInterval(86_400)),
            .init(phraseIDs: ["b", "c", "d", "e", "f"], nextLessonAt: now.addingTimeInterval(4 * 86_400))
        ], cards: [], now: now))
        #expect(data.totalPhraseCount == 6)
        #expect(data.dailyNewTarget == 3) // 2 tomorrow + 4 / 4 days, not 6 tomorrow.
    }

    @Test func frozenV1MigratesOnDiskWithoutLosingProgress() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Migration.store")
        try writeLegacyStore(url)
        let schema = Schema(versionedSchema: SchemaV2.self)
        let container = try ModelContainer(for: schema, migrationPlan: LanguageLearningMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let phrase = try #require(context.fetch(FetchDescriptor<Phrase>()).first)
        #expect(phrase.targetText == "осень")
        #expect(phrase.cards?.first?.reps == 7)
        #expect(phrase.cards?.first?.reviews?.first?.evidenceJSON == nil)
        #expect(phrase.topics?.first?.isTutorFocus == true)
        let settings = try #require(context.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(settings.dailyNewLimit == 6)
        #expect(settings.experienceJSON == nil)
        var data = LearningExperience()
        data.save(.init(episodeID: "ru-seasons-1", contentVersion: 1, language: "ru"))
        try settings.writeExperience(data)
        try context.save()
        #expect(try settings.readExperience().runs.count == 1)
    }

    @Test func interveningPracticePostponesDelayedProbeAndPastTutorLessonsStayActive() throws {
        let episode = try #require(EpisodeLibrary.all.first)
        let now = Date.now
        var data = LearningExperience()
        var completed = EpisodeRun(episodeID: episode.id, contentVersion: 1, language: "ru")
        completed.completedAt = now.addingTimeInterval(-2 * 86_400)
        completed.updatedAt = completed.completedAt!
        data.save(completed)
        #expect(data.isCheckDue(episode, now: now))
        var exposure = EpisodeRun(episodeID: episode.id, contentVersion: 1, language: "ru")
        exposure.updatedAt = now
        exposure.endedAt = now
        data.save(exposure)
        #expect(!data.isCheckDue(episode, now: now))
        let topic = Topic(name: "Jahreszeiten")
        topic.startTutorFocus(nextLessonAt: now.addingTimeInterval(-30 * 86_400))
        #expect(topic.isTutorFocusActive(at: now))
        topic.finishTutorFocus()
        #expect(!topic.isTutorFocusActive(at: now.addingTimeInterval(1)))
    }

    private func writeLegacyStore(_ url: URL) throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let language = SchemaV1.Language(code: "ru", name: "Русский")
        let topic = SchemaV1.Topic(name: "Jahreszeiten", language: language, isActive: true)
        topic.isTutorFocus = true
        let phrase = SchemaV1.Phrase(sourceText: "Herbst", targetText: "осень", language: language, topics: [topic])
        let card = SchemaV1.StudyCard(phrase: phrase)
        card.reps = 7
        card.state = .review
        let review = SchemaV1.Review(card: card, rating: 3, autoGradeRating: 3, userAnswer: "осень", mode: .typeDeToRu, responseTimeMs: 5000, gradeTier: 1, wasNew: false)
        context.insert(language)
        context.insert(topic)
        context.insert(phrase)
        context.insert(card)
        context.insert(review)
        context.insert(SchemaV1.AppSettings(dailyNewLimit: 6))
        try context.save()
    }
}
