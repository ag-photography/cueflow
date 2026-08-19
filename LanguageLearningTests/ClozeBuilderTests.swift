import XCTest
@testable import LanguageLearning

final class ClozeBuilderTests: XCTestCase {
    private func item(
        _ sentence: String,
        target: String,
        language: String = "ru",
        translation: String? = "Übersetzung",
        transliteration: String? = nil
    ) -> ClozeItem? {
        ClozeBuilder.item(
            sentence: sentence,
            translation: translation,
            transliteration: transliteration,
            target: target,
            languageCode: language
        )
    }

    // MARK: - The point of the exercise

    func testBlanksTheInflectedFormNotTheHeadword() throws {
        // "вечер" is the flashcard; the sentence needs the instrumental "вечером".
        let cloze = try XCTUnwrap(item("Сегодня вечером я свободен.", target: "вечер"))

        XCTAssertEqual(cloze.answer, "вечером")
        XCTAssertEqual(cloze.prompt, "Сегодня \(ClozeBuilder.blank) я свободен.")
        XCTAssertTrue(cloze.teachesInflection, "This item exists to teach the ending")
        XCTAssertEqual(cloze.sentence, "Сегодня вечером я свободен.")
        XCTAssertEqual(cloze.headword, "вечер")
    }

    func testExactFormIsStillAValidItemButNotFlaggedAsInflection() throws {
        let cloze = try XCTUnwrap(item("Мы едем в Петербург.", target: "Петербург"))

        XCTAssertEqual(cloze.answer, "Петербург")
        XCTAssertFalse(cloze.teachesInflection)
    }

    func testPunctuationOutsideTheWordIsPreserved() throws {
        let cloze = try XCTUnwrap(item("Где мой телефон?", target: "телефон"))
        XCTAssertEqual(cloze.prompt, "Где мой \(ClozeBuilder.blank)?")
    }

    func testStressMarksDoNotBlockTheMatch() throws {
        let cloze = try XCTUnwrap(item("Сего́дня ве́чером я свобо́ден.", target: "вечер"))
        XCTAssertEqual(cloze.answer, "ве́чером", "The surface form keeps its stress mark")
    }

    func testMultiWordTargetBlanksTheWholeSpan() throws {
        let cloze = try XCTUnwrap(item("Я говорю добрый день соседу.", target: "добрый день"))
        XCTAssertEqual(cloze.answer, "добрый день")
        XCTAssertEqual(cloze.prompt, "Я говорю \(ClozeBuilder.blank) соседу.")
    }

    // MARK: - Refusing to build a bad item

    func testReturnsNilWhenTheWordIsAbsent() {
        XCTAssertNil(item("Сегодня хорошая погода.", target: "телефон"))
    }

    func testReturnsNilForSentencesTooShortToGiveContext() {
        XCTAssertNil(item("Добрый день.", target: "день"), "Two words leave nothing to reason from")
    }

    func testReturnsNilWhenRemovingTheAnswerLeavesTooLittle() {
        XCTAssertNil(item("Добрый день сегодня.", target: "добрый день сегодня"))
    }

    func testUnrelatedWordSharingAShortPrefixIsNotMatched() {
        // "стол" vs "столица" — same first four letters, unrelated words.
        XCTAssertNil(item("Москва это столица России.", target: "стол"))
    }

    func testRealInflectionsStillMatchAfterTighteningTheRule() throws {
        // Each of these is a genuine form of the headword and must survive the
        // guard that rejects стол/столица.
        let cases: [(sentence: String, target: String, expected: String)] = [
            ("Я вижу моего друга сегодня.", "друг", "друга"),
            ("Мой телефона нет дома.", "телефон", "телефона"),
            ("Я говорю по-русски дома.", "говорить", "говорю"),
            ("Я жду свою матери долго.", "мать", "матери"),
        ]
        for testCase in cases {
            let cloze = try XCTUnwrap(
                item(testCase.sentence, target: testCase.target),
                "Expected a match for \(testCase.target)"
            )
            XCTAssertEqual(cloze.answer, testCase.expected, "for \(testCase.target)")
        }
    }

    func testArabicUsesExactMatchingOnly() throws {
        // A prefix heuristic would mangle non-concatenative morphology, so only
        // the definite article is stripped.
        XCTAssertNotNil(item("هذا هو البيت الكبير", target: "بيت", language: "ar"))
        XCTAssertNil(item("هذا هو المكتب الكبير", target: "كتاب", language: "ar"))
    }

    func testArabicDiacriticsAreIgnoredWhenMatching() throws {
        let cloze = try XCTUnwrap(item("هذا هو البَيت الكبير", target: "بيت", language: "ar"))
        XCTAssertEqual(cloze.answer, "البَيت", "Surface form is preserved verbatim")
    }

    // MARK: - Model integration

    @MainActor
    func testBuildsFromAPhraseAndSkipsPhrasesWithoutASentence() throws {
        let language = Language(code: "ru", name: "Русский")
        let phrase = Phrase(sourceText: "Abend", targetText: "вечер", language: language)
        XCTAssertNil(ClozeBuilder.item(for: phrase), "No sentence, no item")

        phrase.exampleSentence = "Сегодня вечером я свободен."
        phrase.exampleSentenceTranslation = "Heute Abend bin ich frei."
        let cloze = try XCTUnwrap(ClozeBuilder.item(for: phrase))
        XCTAssertEqual(cloze.answer, "вечером")
        XCTAssertEqual(cloze.translation, "Heute Abend bin ich frei.")
    }
}
