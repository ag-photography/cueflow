import Foundation
import SwiftData
import Testing
@testable import LanguageLearning

@MainActor
struct RoadmapIntegrationTests {
    @Test func explicitlyEndedOrExpiredPlansCannotResume() {
        let plan = PracticePlan(language: "ru", scope: "recommended", mode: CardDirection.speakDeToRu.rawValue, budget: 5, items: [])
        #expect(plan.canResume(language: "ru", scope: "recommended", mode: .speakDeToRu, budget: 5, endedIDs: []))
        #expect(!plan.canResume(language: "ru", scope: "recommended", mode: .speakDeToRu, budget: 5, endedIDs: [plan.id]))
        #expect(!plan.canResume(language: "ru", scope: "recommended", mode: .speakDeToRu, budget: 5, endedIDs: [], now: plan.createdAt.addingTimeInterval(86_400)))
        var data = LearningExperience()
        data.endedPlanIDs = [plan.id]
        data.merge(.init())
        #expect(data.endedPlanIDs?.contains(plan.id) == true)
    }
    @Test func episodeBranchingIsBoundedAndRejectsCyclesOrMissingDestinations() {
        var steps = EpisodeLibrary.all[0].steps
        steps[2].nextOnCorrect = "apply"
        let base = EpisodeLibrary.all[0]
        func episode(_ steps: [LearningEpisode.Step]) -> LearningEpisode {
            .init(id: "branch-test", version: 1, language: "ru", title: base.title, outcome: base.outcome,
                  hook: base.hook, symbol: base.symbol, interest: base.interest, topicTags: base.topicTags, steps: steps)
        }
        let branching = episode(steps)
        #expect(branching.validationErrors.isEmpty)
        #expect(branching.nextIndex(after: 2, attempt: .init(stepID: "recall-a", correct: true, supported: false, spoken: false, timestamp: .now)) == 4)
        #expect(branching.nextIndex(after: 2, attempt: .init(stepID: "recall-a", correct: false, supported: false, spoken: false, timestamp: .now)) == 3)
        steps[4].nextOnSupport = "recall-a"
        #expect(episode(steps).validationErrors.contains("Branch cannot finish"))
        steps[4].nextOnSupport = "missing"
        #expect(episode(steps).validationErrors.contains("Unknown branch destination"))
    }
    @Test func unscoredActivityIsPrivateIdempotentAndNeverSchedulesCards() throws {
        let container = try store()
        let context = container.mainContext
        let settings = AppSettings()
        context.insert(settings)
        let session = UUID()
        for _ in 0..<2 {
            try LearningActivityRecorder.record("listening_answer", language: "ru", session: session,
                step: "1", support: "recognition", matched: true, context: context)
        }
        let data = try settings.readExperience()
        #expect(data.events.count == 1)
        #expect(data.events.first?.support == "recognition")
        #expect(try context.fetchCount(FetchDescriptor<Review>()) == 0)
        #expect(data.learningDays(language: "ru") == 1)
        var reset = data
        reset.events = []
        reset.eventResetAt = .now
        try settings.writeExperience(reset)
        try context.save()
        #expect(try settings.readExperience().learningDays(language: "ru") == 1)
    }

    @Test func timingComparisonDoesNotMixSpeechTypingOrInterruptedAnswers() {
        let card = StudyCard(phrase: Phrase(sourceText: "Herbst", targetText: "осень"))
        let reviews = (0..<6).map { index -> Review in
            let review = Review(card: card, rating: 3, autoGradeRating: 3, userAnswer: "осень", mode: .typeDeToRu,
                responseTimeMs: index < 3 ? 5000 : 3000, gradeTier: 1, wasNew: false)
            review.timestamp = Date.now.addingTimeInterval(Double(index))
            review.evidence = .init(support: .none, inputWasSpeech: false, assessedCorrect: true, gradingMethod: 1)
            review.evidence?.inputAvailableMs = 1000
            review.evidence?.timingInterrupted = false
            return review
        }
        #expect(ComparableSubmissionTiming.report(reviews: reviews).contains("lower recent median: 1"))
        reviews[0].evidence?.timingInterrupted = true
        #expect(ComparableSubmissionTiming.report(reviews: reviews).contains("lower recent median: 0"))
        reviews[0].evidence = .init(support: .none, inputWasSpeech: true, assessedCorrect: true, gradingMethod: 1)
        reviews[0].evidence?.timingInterrupted = false
        reviews[0].evidence?.inputAvailableMs = 1000
        #expect(ComparableSubmissionTiming.report(reviews: reviews).contains("lower recent median: 0"))
    }

    @Test func simultaneousCohortAssignmentHasDeterministicMerge() {
        let date = Date.now
        var first = LearningExperience(), second = LearningExperience()
        first.trial = .init(startedAt: date, variant: "stories-first")
        second.trial = .init(startedAt: date, variant: "cards-first")
        var left = first, right = second
        left.merge(second)
        right.merge(first)
        #expect(left.trial?.variant == right.trial?.variant)
    }
    @Test func unconfirmedRetryKeepsFirstAnswerAndSupportAcrossJournalMerge() throws {
        let result = GraderService().grade(expected: "осень", actual: "зима", acceptedAlternatives: [], responseTimeMs: 8000)
        var checkpoint = CardAttemptCheckpoint(planID: UUID(), cardKey: "canonical", result: result,
            answer: "зима", responseTimeMs: 8000, support: .none, spoken: true, firstAnswer: "зима", firstCorrect: false)
        var first = LearningExperience()
        first.save(checkpoint)
        checkpoint.updatedAt = checkpoint.updatedAt.addingTimeInterval(10)
        checkpoint.support = .retry
        checkpoint.answer = "осень"
        var second = LearningExperience()
        second.save(checkpoint)
        let restored = try JSONDecoder().decode(LearningExperience.self, from: JSONEncoder().encode(second))
        first.merge(restored)
        #expect(first.cardAttempts?.count == 1)
        #expect(first.cardAttempts?.first?.firstAnswer == "зима")
        #expect(first.cardAttempts?.first?.firstCorrect == false)
        #expect(first.cardAttempts?.first?.support == .retry)
    }

    @Test func earnedMilestoneIdentitySurvivesLaterWeakerStateAndBackup() throws {
        var data = LearningExperience()
        let earnedAt = Date.now.addingTimeInterval(-8 * 86_400)
        data.earnedMilestones = ["ru:weekly-flow": earnedAt]
        var newer = LearningExperience()
        newer.earnedMilestones = [:]
        data.merge(newer)
        let decoded = try JSONDecoder().decode(LearningExperience.self, from: JSONEncoder().encode(data))
        #expect(decoded.earnedMilestones?["ru:weekly-flow"] == earnedAt)
        #expect(CapabilityLevel.fluent.title != "Gesprächsbereit")
    }
    @Test func frozenV2StoreUpgradesToIndependentJournalRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("V2.store")
        try writeV2(url)
        let schema = Schema(versionedSchema: SchemaV3.self)
        let container = try ModelContainer(for: schema, migrationPlan: LanguageLearningMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let context = container.mainContext
        let settings = try #require(context.fetch(FetchDescriptor<AppSettings>()).first)
        let journal = try settings.readExperience()
        #expect(journal.runs.count == 1)
        #expect(settings.dailyNewLimit == 6)
        try settings.writeExperience(journal)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<LearningJournalRecord>()) == 1)
        let backedUp = BackupService.makeBackup(languages: [], topics: [], phrases: [], settings: settings, appVersion: "test")
        #expect(backedUp.settings?.experienceJSON != nil)
    }

    private func writeV2(_ url: URL) throws {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let context = container.mainContext
        let settings = AppSettings(dailyNewLimit: 6)
        context.insert(settings)
        var data = LearningExperience()
        data.save(.init(episodeID: "ru-seasons-1", contentVersion: 1, language: "ru"))
        try settings.writeExperience(data)
        try context.save()
    }

    @Test func explicitTopicScopeIncludesInactiveNewMaterialWithoutExceedingCap() {
        let topic = Topic(name: "Unterricht", isActive: false)
        let cards = (0..<5).map { StudyCard(phrase: Phrase(sourceText: "\($0)", targetText: "\($0)", topics: [topic])) }
        #expect(SessionPlanner.cards(from: cards, reviews: [], target: 5, dailyNewLimit: 2, tutorIDs: []).isEmpty)
        #expect(SessionPlanner.cards(from: cards, reviews: [], target: 5, dailyNewLimit: 2, tutorIDs: [], allowInactiveTopics: true).count == 2)
    }

    @Test func aggregateDoesNotExportAnswersOrPhraseIdentity() {
        let phrase = Phrase(sourceText: "PRIVATE_GERMAN", targetText: "PRIVATE_RUSSIAN")
        let review = Review(card: StudyCard(phrase: phrase), rating: 3, autoGradeRating: 3, userAnswer: "PRIVATE_ANSWER", mode: .typeDeToRu, responseTimeMs: 2000, gradeTier: 1, wasNew: false)
        review.evidence = .init(support: .none, inputWasSpeech: false, assessedCorrect: true, gradingMethod: 1)
        let report = ExposureMatchedAnalysis.report(reviews: [review], since: .distantPast)
        #expect(!report.contains("PRIVATE"))
        #expect(report.contains("attempts 1, correct 1"))
    }

    @Test func aSingleAnswerDoesNotProveRetentionAndExposureInvalidatesProof() {
        let card = StudyCard(phrase: Phrase(sourceText: "Herbst", targetText: "осень"))
        func review(_ date: Date, supported: Bool) -> Review {
            let item = Review(card: card, rating: 3, autoGradeRating: 3, userAnswer: "", mode: .typeDeToRu, responseTimeMs: 1000, gradeTier: 1, wasNew: false)
            item.timestamp = date
            item.evidence = .init(support: supported ? .revealed : .none, inputWasSpeech: false, assessedCorrect: true, gradingMethod: 1)
            return item
        }
        let now = Date.now
        let first = review(now.addingTimeInterval(-8 * 86_400), supported: false)
        let delayed = review(now, supported: false)
        #expect(!DurableRecall.demonstrated([first]))
        #expect(DurableRecall.demonstrated([first, delayed]))
        #expect(!DurableRecall.demonstrated([first, review(now.addingTimeInterval(-60), supported: true), delayed]))
        #expect(!DurableRecall.demonstrated([first, delayed], after: now.addingTimeInterval(-60)))
    }
    private func store() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV3.self)
        return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    @Test func storyUsesCanonicalCardAndSchedulesFirstOpportunityOnly() throws {
        let container = try store()
        let context = container.mainContext
        let language = Language(code: "ru", name: "Русский")
        context.insert(language)
        let episode = EpisodeLibrary.all[0]
        let run = EpisodeRun(episodeID: episode.id, contentVersion: 1, language: "ru")
        let model = episode.steps[1]
        try EpisodeVocabulary.record(episode: episode, run: run, step: model, attempt: nil, context: context)
        try context.save()
        let card = try #require(context.fetch(FetchDescriptor<StudyCard>()).first)
        #expect(card.reps == 0)
        #expect(card.hasBeenIntroduced)
        #expect(ProductionFollowUp.pending(card.reviews ?? []))
        #expect(LearningMotivation.events(from: card.reviews ?? []).isEmpty)
        try EpisodeVocabulary.record(episode: episode, run: run, step: model, attempt: nil, context: context)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Review>()) == 1)
        for index in [3, 3, 4] {
            let step = episode.steps[index]
            let attempt = EpisodeAttempt(stepID: step.id, correct: true, supported: false, spoken: false, timestamp: .now)
            try EpisodeVocabulary.record(episode: episode, run: run, step: step, attempt: attempt, context: context)
            try context.save()
        }
        #expect(try context.fetchCount(FetchDescriptor<Phrase>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Review>()) == 3)
        #expect(card.reps == 1)
        #expect(!ProductionFollowUp.pending(card.reviews ?? []))
        #expect(!DurableRecall.demonstrated(card.reviews ?? []))
    }

    @Test func failedRecallAndAssistedRepeatNeverScheduleGood() throws {
        let container = try store()
        let context = container.mainContext
        context.insert(Language(code: "ru", name: "Русский"))
        let episode = EpisodeLibrary.all[0]
        let run = EpisodeRun(episodeID: episode.id, contentVersion: 1, language: "ru")
        let recall = episode.steps[3], transfer = episode.steps[4]
        try EpisodeVocabulary.record(episode: episode, run: run, step: recall,
            attempt: .init(stepID: recall.id, correct: false, supported: false, spoken: false, timestamp: .now), context: context)
        try context.save()
        let card = try #require(context.fetch(FetchDescriptor<StudyCard>()).first)
        let due = card.dueDate
        try EpisodeVocabulary.record(episode: episode, run: run, step: transfer,
            attempt: .init(stepID: transfer.id, correct: true, supported: true, spoken: false, timestamp: .now), context: context)
        try context.save()
        #expect(card.reps == 1)
        #expect(card.dueDate == due)
        #expect(ProductionFollowUp.pending(card.reviews ?? []))
    }

    @Test func savedPlanSurvivesRoundTripAndSkipsCommittedAnswer() throws {
        let topic = Topic(name: "Wetter", isActive: true)
        let cards = (0..<8).map { StudyCard(phrase: Phrase(sourceText: "\($0)", targetText: "слово \($0)", topics: [topic])) }
        let plan = PracticePlan.make(cards: cards, reviews: [], language: "ru", scope: "recommended", mode: .speakDeToRu,
            budget: 5, dailyLimit: 10, tutorIDs: [])
        #expect(plan.items.count == 5)
        let restored = try JSONDecoder().decode(PracticePlan.self, from: JSONEncoder().encode(plan))
        let first = try #require(restored.remaining(in: cards, reviews: []).first)
        let review = Review(card: first, rating: 3, autoGradeRating: 3, userAnswer: "", mode: .chooseDeToRu, responseTimeMs: 0, gradeTier: 0, wasNew: true)
        review.evidence = .init(support: .tiles, inputWasSpeech: false, assessedCorrect: true, gradingMethod: 0)
        review.evidence?.sessionID = plan.id
        #expect(restored.remaining(in: cards.reversed(), reviews: [review]).map(PracticePlan.key) == Array(plan.items.dropFirst().map(\.key)))
    }

    @Test func independentJournalFragmentsMergeAndResetDoesNotResurrectEvents() throws {
        let container = try store()
        let context = container.mainContext
        var first = LearningExperience(), second = LearningExperience()
        let a = EpisodeRun(episodeID: "ru-seasons-1", contentVersion: 1, language: "ru")
        let b = EpisodeRun(episodeID: "ru-cafe-1", contentVersion: 1, language: "ru")
        first.save(a); first.event("session_started", run: a)
        second.save(b); second.event("session_started", run: b)
        try LearningJournalStore.persist(first, in: context)
        try LearningJournalStore.persist(second, in: context)
        try context.save()
        let records = try context.fetch(FetchDescriptor<LearningJournalRecord>())
        var merged = try LearningJournalStore.merged(first, records: records)
        #expect(merged.runs.count == 2)
        #expect(merged.events.count == 2)
        try LearningJournalStore.persist(merged, in: context)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<LearningJournalRecord>()) == records.count)
        merged.events = []
        merged.eventResetAt = Date.now.addingTimeInterval(1)
        merged = try LearningJournalStore.merged(merged, records: records)
        #expect(merged.events.isEmpty)
        #expect(merged.runs.count == 2)
    }

    @Test func legacyJournalDecodesWithoutNewFields() throws {
        let json = "{\"version\":1,\"preferences\":{\"ru\":{\"purpose\":\"Reisen\",\"quiet\":true,\"weeklyDays\":3}},\"runs\":[],\"events\":[]}"
        let data = try JSONDecoder().decode(LearningExperience.self, from: Data(json.utf8))
        #expect(data.practicePlans == nil)
        #expect(data.preference(for: "ru").effectiveStudyWeekdays == [2, 4, 6])
    }

    @Test func legacyModeExposurePostponesStoryCheckAcrossRestart() throws {
        let now = Date.now
        let episode = EpisodeLibrary.all[0]
        var data = LearningExperience()
        var run = EpisodeRun(episodeID: episode.id, contentVersion: 1, language: "ru")
        run.updatedAt = now.addingTimeInterval(-2 * 86_400)
        run.completedAt = run.updatedAt
        data.save(run)
        #expect(data.isCheckDue(episode, now: now))
        data.otherModeExposureAt = ["ru": now]
        let decoded = try JSONDecoder().decode(LearningExperience.self, from: JSONEncoder().encode(data))
        #expect(!decoded.isCheckDue(episode, now: now))
    }

    @Test func tutorBudgetUsesSelectedDaysAndShowsImpossibleDeadline() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))! // Monday
        let budget = TutorStudyBudget.make(remaining: 15, deadline: now.addingTimeInterval(4 * 86_400), weekdays: [2, 4], dailyLimit: 5, now: now, calendar: calendar)
        #expect(budget.opportunities == 2)
        #expect(budget.requiredPerOpportunity == 8)
        #expect(budget.shortfall == 5)
        #expect(TutorStudyBudget.make(remaining: 5, deadline: now.addingTimeInterval(-1), weekdays: [2], dailyLimit: 10, now: now).shortfall == 5)
        #expect(TutorStudyBudget.make(remaining: 5, deadline: nil, weekdays: [], dailyLimit: 10, now: now).opportunities == 0)
    }

    @Test func analyticsDistinguishPauseFromAbandonmentAndMissingCohort() {
        let now = Date.now
        var data = LearningExperience()
        var recent = EpisodeRun(episodeID: "one", contentVersion: 1, language: "ru")
        recent.startedAt = now.addingTimeInterval(-100)
        recent.updatedAt = recent.startedAt
        data.save(recent)
        let analysis = LearningAnalysis(experience: data, language: "ru", now: now)
        #expect(analysis.paused == 1)
        #expect(analysis.abandoned == 0)
        #expect(analysis.returnStatus(day: 7) == "not yet observable")
        #expect(LearningAnalysis(experience: data, language: "ru", now: now.addingTimeInterval(86_400)).abandoned == 1)
    }
}
