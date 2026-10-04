import Foundation
import SwiftData
import Testing
@testable import LanguageLearning

@MainActor
struct TutorFocusPlannerTests {
    @Test func todayChoosesOneActionWithResumeBeforeTutorBeforeGeneralPractice() {
        let now = Date.now
        #expect(TodayPracticeRecommendation.choose(tutorResume: nil, practiceResume: nil, situationResume: nil,
            hasTutor: true, hasPractice: true, hasSituation: true) == .tutor)
        #expect(TodayPracticeRecommendation.choose(tutorResume: nil, practiceResume: now, situationResume: nil,
            hasTutor: true, hasPractice: true, hasSituation: true) == .practice)
        #expect(TodayPracticeRecommendation.choose(tutorResume: now, practiceResume: now.addingTimeInterval(-60), situationResume: nil,
            hasTutor: true, hasPractice: true, hasSituation: true) == .tutor)
        #expect(TodayPracticeRecommendation.choose(tutorResume: nil, practiceResume: now, situationResume: now.addingTimeInterval(60),
            hasTutor: true, hasPractice: true, hasSituation: true) == .situation)
        #expect(TodayPracticeRecommendation.choose(tutorResume: nil, practiceResume: nil, situationResume: nil,
            hasTutor: false, hasPractice: true, hasSituation: true) == .practice)
        #expect(TodayPracticeRecommendation.choose(tutorResume: nil, practiceResume: nil, situationResume: nil,
            hasTutor: false, hasPractice: false, hasSituation: true) == .situation)
        #expect(TodayPracticeRecommendation.choose(tutorResume: nil, practiceResume: nil, situationResume: nil,
            hasTutor: false, hasPractice: false, hasSituation: false) == nil)
    }
    private func lesson(_ name: String, language: Language, count: Int = 5) -> (Topic, [StudyCard]) {
        let topic = Topic(name: name, language: language, isActive: true)
        topic.startTutorFocus(nextLessonAt: nil)
        let phrases = (0..<count).map {
            Phrase(sourceText: "\(name) \($0)", targetText: "Wort \($0)", language: language, topics: [topic])
        }
        topic.phrases = phrases
        return (topic, phrases.map { StudyCard(phrase: $0) })
    }

    @Test func quickRoundUsesOnlyActualLessonWordsAndThreeOpportunities() throws {
        let language = Language(code: "ru", name: "Русский")
        let (topic, cards) = lesson("Jahreszeiten", language: language)
        let (_, unrelated) = lesson("Essen", language: language)
        let rounds = TutorFocusPlanner.quickRounds(topics: [topic], cards: cards + unrelated,
            reviews: [], language: "ru", dailyLimit: 10)
        let round = try #require(rounds.first)
        #expect(round.remainingCount == 3)
        #expect(round.plan.budget == 3)
        #expect(round.plan.items.allSatisfy { item in cards.contains { PracticePlan.key($0) == item.key } })
        #expect(round.plan.items.allSatisfy { $0.reason == "Unterricht" })
    }

    @Test func quickRoundRespectsCapAndDoesNotFillWithUnrelatedWords() throws {
        let language = Language(code: "ru", name: "Русский")
        let (topic, cards) = lesson("Wetter", language: language)
        let limited = TutorFocusPlanner.quickRounds(topics: [topic], cards: cards,
            reviews: [], language: "ru", dailyLimit: 1)
        #expect(limited.first?.remainingCount == 1)
        let blocked = TutorFocusPlanner.quickRounds(topics: [topic], cards: cards,
            reviews: [], language: "ru", dailyLimit: 0)
        #expect(blocked.first?.remainingCount == 0)
    }

    @Test func quickRoundExcludesFinishedLessonsAndOtherLanguages() {
        let ru = Language(code: "ru", name: "Русский")
        let ar = Language(code: "ar", name: "العربية")
        let (finished, oldCards) = lesson("Alt", language: ru)
        finished.finishTutorFocus()
        let (arabic, arabicCards) = lesson("Arabisch", language: ar)
        #expect(TutorFocusPlanner.quickRounds(topics: [finished, arabic], cards: oldCards + arabicCards,
            reviews: [], language: "ru", dailyLimit: 10).isEmpty)
    }

    @Test func quickRoundsOrderConcurrentLessonsByDeadlineAndResumeSamePlan() throws {
        let ru = Language(code: "ru", name: "Русский")
        let (later, laterCards) = lesson("Später", language: ru)
        let (sooner, soonerCards) = lesson("Jetzt", language: ru)
        sooner.tutorNextLessonAt = Date.now.addingTimeInterval(86_400)
        let rounds = TutorFocusPlanner.quickRounds(topics: [later, sooner], cards: laterCards + soonerCards,
            reviews: [], language: "ru", dailyLimit: 10)
        let first = try #require(rounds.first)
        #expect(first.topic === sooner)
        let resumed = TutorFocusPlanner.quickRounds(topics: [later, sooner], cards: laterCards + soonerCards,
            reviews: [], language: "ru", dailyLimit: 10, savedPlans: [first.plan])
        #expect(resumed.first?.plan.id == first.plan.id)
        let ended = TutorFocusPlanner.quickRounds(topics: [sooner], cards: soonerCards,
            reviews: [], language: "ru", dailyLimit: 10, savedPlans: [first.plan], endedIDs: [first.plan.id])
        #expect(ended.first?.plan.id != first.plan.id)
    }

    @Test func quickRoundDoesNotPullFutureReviewsForward() {
        let ru = Language(code: "ru", name: "Русский")
        let (topic, cards) = lesson("Bekannt", language: ru)
        cards.forEach { $0.state = .review; $0.dueDate = .now.addingTimeInterval(86_400) }
        let rounds = TutorFocusPlanner.quickRounds(topics: [topic], cards: cards,
            reviews: [], language: "ru", dailyLimit: 10)
        #expect(rounds.first?.remainingCount == 0)
    }

    @Test func resumedQuickRoundRechecksAllowanceWithoutReplacingItsPlan() throws {
        let ru = Language(code: "ru", name: "Русский")
        let (topic, cards) = lesson("Weiterlernen", language: ru)
        let first = try #require(TutorFocusPlanner.quickRounds(topics: [topic], cards: cards,
            reviews: [], language: "ru", dailyLimit: 10).first)
        let resumed = try #require(TutorFocusPlanner.quickRounds(topics: [topic], cards: cards,
            reviews: [], language: "ru", dailyLimit: 1, savedPlans: [first.plan]).first)
        #expect(resumed.plan.id == first.plan.id)
        #expect(resumed.remainingCount == 1)
        #expect(resumed.plan.items.count == 3) // Deferred, not discarded.
        #expect(resumed.plan.remaining(in: cards, reviews: [], dailyNewLimit: 0).isEmpty)
    }

    @Test func existingTutorImportIsRecognisedAndPacedWithoutStoredFocusMetadata() throws {
        let language = Language(code: "ru", name: "Русский")
        let topic = Topic(name: "Jahreszeiten", language: language, isActive: true)
        var cards: [StudyCard] = []
        var phrases: [Phrase] = []
        for index in 0..<6 {
            let phrase = Phrase(
                sourceText: "Saison \(index)", targetText: "сезон \(index)",
                language: language, topics: [topic]
            )
            phrase.contentSource = .tutorImport
            let card = StudyCard(phrase: phrase)
            if index < 2 { card.state = .review }
            phrases.append(phrase)
            cards.append(card)
        }
        topic.phrases = phrases

        let pacing = try #require(TutorFocusPlanner.pacing(topics: [topic], cards: cards))

        #expect(topic.isTutorFocusActive)
        #expect(pacing.totalPhraseCount == 6)
        #expect(pacing.introducedPhraseCount == 2)
        #expect(pacing.remainingNewCount == 4)
        #expect(pacing.daysUntilLesson == 7)
        #expect(pacing.dailyNewTarget == 1)
    }

    @Test func nextLessonDateDeterminesDailyPreparationTarget() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_006_400)
        let topic = Topic(name: "Wetter", isActive: true)
        topic.startTutorFocus(
            nextLessonAt: calendar.date(byAdding: .day, value: 2, to: now),
            now: now,
            calendar: calendar
        )
        var phrases: [Phrase] = []
        let cards = (0..<5).map { index -> StudyCard in
            let phrase = Phrase(sourceText: "Wetter \(index)", targetText: "погода \(index)", topics: [topic])
            phrases.append(phrase)
            return StudyCard(phrase: phrase)
        }
        topic.phrases = phrases

        let pacing = try #require(TutorFocusPlanner.pacing(
            topics: [topic], cards: cards, now: now, calendar: calendar
        ))

        #expect(pacing.daysUntilLesson == 2)
        #expect(pacing.dailyNewTarget == 3)
    }

    @Test func finishingFocusKeepsTutorCardsButStopsSpecialTreatment() {
        let topic = Topic(name: "Vergangenheit", isActive: true)
        let phrase = Phrase(sourceText: "gestern", targetText: "вчера", topics: [topic])
        phrase.contentSource = .tutorImport
        topic.startTutorFocus(nextLessonAt: nil)
        topic.finishTutorFocus()

        #expect(!topic.isTutorFocusActive)
        #expect(!phrase.isTutorPriorityActive)
        #expect(topic.isActive)
    }
}
