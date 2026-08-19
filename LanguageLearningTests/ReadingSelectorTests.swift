import XCTest
@testable import LanguageLearning

final class ReadingSelectorTests: XCTestCase {
    private func known(_ target: String, stability: Double = 30, introduced: Bool = true) -> ReadingSelector.KnownPhrase {
        ReadingSelector.KnownPhrase(target: target, stability: stability, isIntroduced: introduced)
    }

    private func sentence(_ text: String, id: String) -> ReadingSelector.SentenceSource {
        ReadingSelector.SentenceSource(
            id: ContentID(id), sentence: text, translation: "de", transliteration: nil
        )
    }

    func testSentencesWithMoreThanOneUnknownWordAreExcluded() {
        let result = ReadingSelector.passages(
            sentences: [sentence("Собака ест мясо каждый день", id: "a")],
            known: [known("день")]
        )
        XCTAssertTrue(result.isEmpty, "Three unknown content words is not i+1")
    }

    func testExactlyOneUnknownWordQualifies() throws {
        let result = ReadingSelector.passages(
            sentences: [sentence("Я читаю книгу", id: "a")],
            known: [known("читать"), known("книга")]
        )
        let passage = try XCTUnwrap(result.first)
        XCTAssertEqual(passage.unknownWords, [], "я is a function word, читаю/книгу are known forms")
    }

    func testOneNewWordIsPreferredOverAFullyKnownSentence() throws {
        let result = ReadingSelector.passages(
            sentences: [
                sentence("Я читаю книгу", id: "known"),
                sentence("Я читаю газету", id: "oneNew"),
            ],
            known: [known("читать"), known("книга")]
        )
        XCTAssertEqual(result.count, 2)
        let first = try XCTUnwrap(result.first)
        XCTAssertEqual(first.id, ContentID("oneNew"), "Acquisition happens on the new word")
        XCTAssertEqual(first.unknownWords, ["газету"])
    }

    func testInflectedFormsOfKnownWordsCountAsKnown() throws {
        // "вечером" is the instrumental of the stabilised "вечер".
        let result = ReadingSelector.passages(
            sentences: [sentence("Сегодня вечером я работаю", id: "a")],
            known: [known("вечер"), known("сегодня"), known("работать")]
        )
        let passage = try XCTUnwrap(result.first)
        XCTAssertEqual(passage.unknownWords, [])
        XCTAssertEqual(passage.knownWordCount, passage.totalWordCount)
    }

    func testUnstableAndUnintroducedPhrasesDoNotCountAsKnown() {
        let shaky = ReadingSelector.passages(
            sentences: [sentence("Я читаю книгу", id: "a")],
            known: [known("читать", stability: 1), known("книга", stability: 1)]
        )
        XCTAssertTrue(shaky.isEmpty, "A memory that has not survived a week is not known")

        let unseen = ReadingSelector.passages(
            sentences: [sentence("Я читаю книгу", id: "a")],
            known: [known("читать", introduced: false), known("книга", introduced: false)]
        )
        XCTAssertTrue(unseen.isEmpty)
    }

    func testReturnsNothingWhenTheLearnerKnowsNothingYet() {
        XCTAssertTrue(
            ReadingSelector.passages(sentences: [sentence("Я читаю книгу", id: "a")], known: []).isEmpty
        )
    }

    func testVeryShortSentencesAreSkipped() {
        XCTAssertTrue(
            ReadingSelector.passages(
                sentences: [sentence("Добрый день", id: "a")],
                known: [known("добрый"), known("день")]
            ).isEmpty,
            "Two words is a flashcard, not reading"
        )
    }

    func testIrregularPronounCaseFormsAreNotReportedAsNewVocabulary() throws {
        // Observed on device: `нам` and `моей` were flagged as new words. They
        // are case forms of мы and мой, which no stem matcher can reach.
        let pronouns = ["нам", "моей", "мне", "свою", "этом", "него"]
        for sentence in [
            "Он часто приходит к нам в гости",
            "Это была лучшая ночь в моей жизни",
            "Она дала мне свою книгу",
            "В этом году я думаю о нём",
        ] {
            let result = ReadingSelector.passages(
                sentences: [self.sentence(sentence, id: sentence)],
                known: [
                    known("приходить"), known("гость"), known("часто"),
                    known("быть"), known("лучший"), known("ночь"), known("жизнь"),
                    known("дать"), known("книга"), known("год"), known("думать"),
                ]
            )
            let passage = try XCTUnwrap(result.first, "expected a passage for: \(sentence)")
            for pronoun in pronouns {
                XCTAssertFalse(
                    passage.unknownWords.contains(pronoun),
                    "\(pronoun) is grammar, not vocabulary — in: \(sentence)"
                )
            }
        }
    }

    func testIrregularVerbStemsAreStillCountedAsUnfamiliar() throws {
        // A documented limitation rather than a bug: быть → была shares only two
        // characters, so the prefix matcher cannot connect them. The sentence
        // still qualifies (one unknown is the target), it is just labelled with
        // a verb form rather than a genuinely new word.
        let result = ReadingSelector.passages(
            sentences: [sentence("Это была моя книга", id: "a")],
            known: [known("быть"), known("книга")]
        )
        let passage = try XCTUnwrap(result.first)
        XCTAssertEqual(passage.unknownWords, ["была"])
    }

    func testRespectsTheLimit() {
        let sentences = (0..<20).map { sentence("Я читаю книгу номер \($0 % 3)", id: "s\($0)") }
        let result = ReadingSelector.passages(
            sentences: sentences, known: [known("читать"), known("книга")], limit: 5
        )
        XCTAssertLessThanOrEqual(result.count, 5)
    }

    func testKnownFractionIsReported() throws {
        let result = ReadingSelector.passages(
            sentences: [sentence("Я читаю газету", id: "a")],
            known: [known("читать")]
        )
        let passage = try XCTUnwrap(result.first)
        XCTAssertEqual(passage.totalWordCount, 3)
        XCTAssertEqual(passage.knownWordCount, 2)      // я (function) + читаю
        XCTAssertEqual(passage.knownFraction, 2.0 / 3.0, accuracy: 0.001)
    }
}
