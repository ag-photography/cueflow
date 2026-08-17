import Foundation
import SwiftData
import Testing
@testable import LanguageLearning

@MainActor
struct TutorFocusPlannerTests {
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
