import XCTest
@testable import LanguageLearning

/// `Phrase.isTutorPriorityActive` walks every phrase of every topic it belongs
/// to, so the practice loop resolves the answer once per pass instead of once
/// per card. These pin the two paths together.
@MainActor
final class TutorPriorityTests: XCTestCase {
    private func makeTopic(
        name: String,
        tutorImported: Bool,
        isTutorFocus: Bool = false
    ) -> (Topic, [Phrase], [StudyCard]) {
        let language = Language(code: "ru", name: "Русский")
        let topic = Topic(name: name, language: language, isActive: true)
        var phrases: [Phrase] = []
        var cards: [StudyCard] = []
        for index in 0..<4 {
            let phrase = Phrase(
                sourceText: "\(name) \(index)",
                targetText: "цель \(index)",
                language: language,
                topics: [topic]
            )
            if tutorImported { phrase.contentSource = .tutorImport }
            phrases.append(phrase)
            cards.append(StudyCard(phrase: phrase))
        }
        topic.phrases = phrases
        if isTutorFocus { topic.startTutorFocus(nextLessonAt: .now.addingTimeInterval(86_400)) }
        return (topic, phrases, cards)
    }

    func testResolvedSetMatchesThePerPhraseAnswer() {
        let (tutorTopic, _, tutorCards) = makeTopic(name: "Jahreszeiten", tutorImported: true)
        let (plainTopic, _, plainCards) = makeTopic(name: "Vokabeln", tutorImported: false)
        let cards = tutorCards + plainCards

        let ids = TutorPriority.phraseIDs(topics: [tutorTopic, plainTopic], cards: cards)

        for card in cards {
            let phrase = try! XCTUnwrap(card.phrase)
            XCTAssertEqual(
                ids.contains(phrase.contentID),
                phrase.isTutorPriorityActive,
                "Resolved set disagrees with the per-phrase answer for \(phrase.sourceText)"
            )
        }
        XCTAssertEqual(ids.count, 4, "Only the tutor topic's phrases are priority")
    }

    func testExpiredFocusDropsOutOfTheSet() {
        let (topic, _, cards) = makeTopic(name: "Vergangenheit", tutorImported: false, isTutorFocus: true)
        XCTAssertEqual(TutorPriority.phraseIDs(topics: [topic], cards: cards).count, 4)

        topic.finishTutorFocus()
        XCTAssertTrue(
            TutorPriority.phraseIDs(topics: [topic], cards: cards).isEmpty,
            "A finished lesson stops conferring priority"
        )
    }

    func testSchedulerPicksTheSameCardWithAndWithoutThePrecomputedSet() {
        let (tutorTopic, _, tutorCards) = makeTopic(name: "Jahreszeiten", tutorImported: true)
        let (plainTopic, _, plainCards) = makeTopic(name: "Vokabeln", tutorImported: false)
        for card in tutorCards + plainCards {
            card.state = .review
            card.dueDate = .distantPast
        }
        let cards = plainCards + tutorCards
        let scheduler = SchedulerService()
        let ids = TutorPriority.phraseIDs(topics: [tutorTopic, plainTopic], cards: cards)

        let derived = scheduler.nextCard(from: cards, reviews: [], dailyNewLimit: 10)
        let precomputed = scheduler.nextCard(
            from: cards, reviews: [], dailyNewLimit: 10, tutorPriorityPhraseIDs: ids
        )

        XCTAssertNotNil(derived)
        XCTAssertTrue(derived === precomputed, "Both paths must choose the same card")
        XCTAssertTrue(
            tutorCards.contains { $0 === precomputed },
            "Tutor material still outranks regular due cards"
        )
    }
}
