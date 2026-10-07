import Foundation
import Testing
@testable import LanguageLearning

struct VocabularyArcadeTests {
    private func word(_ id: String, _ source: String, _ target: String, alternatives: [String] = []) -> ArcadeWord {
        .init(id: id, source: source, target: target, alternatives: alternatives)
    }
    @Test func boardsExcludeDuplicatesAndKnownAmbiguity() {
        let words = [word("a", "Hallo / Guten Tag", "Привет", alternatives: ["Здравствуйте"]),
                     word("b", "Guten Tag", "Добрый день"), word("c", "Begrüßung", "Здравствуйте"),
                     word("d", "Danke", "Спасибо"), word("e", " Danke! ", "Благодарю"),
                     word("f", "", "пусто"), word("g", "leer", ""), word("a", "Nacht", "ночь")]
        #expect(VocabularyArcade.unique(words).map(\.id) == ["a", "d"])
    }
    @Test func roundsAreBoundedAndArabicDistinctionsRemain() {
        let words = (0..<20).map { word("\($0)", "Wort \($0)", "هدف \($0)") }
        #expect(VocabularyArcade.unique(words).count == 8)
        #expect(VocabularyArcade.unique([word("a", "Wissen", "علم"), word("b", "Flagge", "عَلَم")]).count == 2)
    }
    @Test func mixedRoundContainsFiveGamesAndRevisitsASeenWord() {
        let words = (0..<4).map { word("\($0)", "Wort \($0)", "هدف \($0)") }
        let plan = VocabularyArcade.plan(from: words, mode: .mix)
        #expect(plan.map(\.mode) == [.snap, .sound, .swipe, .builder, .recall])
        let mixed = plan.flatMap(\.words)
        #expect(mixed.count == 8)
        #expect(Set(mixed.map(\.id)).count == 8)
        #expect(plan.last?.words.first?.target == plan.first?.words.first?.target)
        #expect(VocabularyArcade.round(from: words, mode: .snap).count == 4)
        #expect(VocabularyArcade.round(from: Array(words.prefix(3)), mode: .mix).isEmpty)
    }
    @Test func builderRequiresRealPhrasesAndSearchesBeyondFirst64Words() {
        let singles = (0..<70).map { word("\($0)", "Wort \($0)", "Ziel\($0)") }
        #expect(VocabularyArcade.plan(from: singles, mode: .builder).isEmpty)
        #expect(VocabularyArcade.plan(from: singles, mode: .mix).map(\.mode) == [.snap, .sound, .swipe, .recall])
        let phrase = word("phrase", "Vielen Dank", "شكرا جزيلا")
        #expect(VocabularyArcade.plan(from: singles + [phrase], mode: .builder).first?.words.first?.target == phrase.target)
        #expect(VocabularyArcade.plan(from: [phrase], mode: .recall).count == 1)
    }
    @Test func typedAnswersAcceptStoredAlternativesAndOptionalMarksButNotDifferentLetters() {
        let russian = word("ru", "Abends", "ве́чером", alternatives: ["По вечерам"])
        #expect(VocabularyArcade.accepts("ВЕЧЕРОМ!", for: russian))
        #expect(VocabularyArcade.accepts(" по   вечерам ", for: russian))
        #expect(!VocabularyArcade.accepts("утром", for: russian))
        #expect(!VocabularyArcade.accepts("", for: russian))
        let arabic = word("ar", "Danke", "شُكْرًا")
        #expect(VocabularyArcade.accepts("شكرا", for: arabic))
        #expect(VocabularyArcade.accepts("\u{2068}شُكْرًا\u{2069}\u{2068}\u{2069}", for: arabic))
        #expect(!VocabularyArcade.accepts("\u{2068}\u{2069}", for: arabic))
        #expect(!VocabularyArcade.accepts("سكرا", for: arabic))
    }
    @Test func optionsKeepCorrectAttemptIdentityAndExcludeDuplicateMeanings() {
        let correct = word("attempt", "Hallo", "Привет")
        let pool = [word("prior", "Hallo", "Привет"), word("other", "Danke", "Спасибо")]
        let choices = VocabularyArcade.options(for: correct, from: pool, count: 2)
        #expect(Set(choices.map(\.id)) == ["attempt", "other"])
    }

    @Test func onlyCompletedArcadeRoundsCountAsLearningDays() {
        var data = LearningExperience()
        data.events.append(.init(name: "arcade_started", language: "ru", sessionID: UUID(), timestamp: .now, stepID: nil))
        #expect(data.learningDays(language: "ru") == 0)
        data.events.append(.init(name: "arcade_completed", language: "ru", sessionID: UUID(), timestamp: .now, stepID: "mix", support: "recognition"))
        #expect(data.learningDays(language: "ru") == 1)
        #expect(data.learningDays(language: "ar") == 0)
    }

    @Test func retriesAndRevealsCannotEarnFirstTryOrFarmStreaks() {
        var score = ArcadeScore()
        score.answer(id: "a", correct: true)
        score.answer(id: "a", correct: true)
        score.answer(id: "b", correct: false)
        score.answer(id: "b", correct: true)
        #expect(score.firstTry == 1)
        #expect(score.resolved.count == 2)
        #expect(score.streak == 0)
        score.answer(id: "c", correct: true)
        score.answer(id: "d", correct: true)
        #expect(score.bestStreak == 2)
        score.answer(id: "d", correct: false)
        #expect(score.streak == 2)
    }

    @Test func spokenAnswersTolerateRecogniserNoiseButNotOtherWords() {
        let hello = word("a", "Hallo", "Привет", alternatives: ["Здравствуйте"])
        #expect(VocabularyArcade.heard("привет", for: hello))
        #expect(VocabularyArcade.heard("ну привет!", for: hello))
        #expect(VocabularyArcade.heard("здравствуй те", for: hello))
        #expect(!VocabularyArcade.heard("пока", for: hello))
        #expect(!VocabularyArcade.heard("", for: hello))
        let thanks = word("b", "Danke", "شُكْرًا")
        #expect(VocabularyArcade.heard("شكرا", for: thanks))
    }
    @Test func activityRecallSchedulesOnlyUnsupportedDueIntroducedCardsOncePerRound() {
        let free = ActivityRecall.decision(supported: false, correct: true, introduced: true, due: true, alreadyScheduled: false)
        #expect(free == .init(schedules: true, rating: 3))
        #expect(ActivityRecall.decision(supported: false, correct: false, introduced: true, due: true, alreadyScheduled: false) == .init(schedules: true, rating: 1))
        #expect(!ActivityRecall.decision(supported: true, correct: true, introduced: true, due: true, alreadyScheduled: false).schedules)
        #expect(!ActivityRecall.decision(supported: false, correct: true, introduced: false, due: true, alreadyScheduled: false).schedules)
        #expect(!ActivityRecall.decision(supported: false, correct: true, introduced: true, due: false, alreadyScheduled: false).schedules)
        #expect(!ActivityRecall.decision(supported: false, correct: true, introduced: true, due: true, alreadyScheduled: true).schedules)
    }
    @Test func conversationCreditsOnlyWholeKnownExpressionsUsed() {
        let candidates: [(id: String, answers: [String])] = [
            ("water", ["вода"]), ("thanks", ["спасибо", "благодарю"]), ("house", ["дом"]), ("much", ["большое спасибо"])]
        let used = ActivityRecall.itemsUsed(in: "Большое спасибо, вода есть?", candidates: candidates)
        #expect(Set(used) == ["water", "thanks", "much"])
        #expect(ActivityRecall.itemsUsed(in: "домой", candidates: candidates).isEmpty)
        #expect(ActivityRecall.itemsUsed(in: "", candidates: candidates).isEmpty)
    }
}
