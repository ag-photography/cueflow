import Testing
@testable import LanguageLearning

struct ContentQualityValidatorTests {
    @Test func acceptsStructurallyCompleteRussianDraft() {
        let candidate = ContentQualityCandidate(
            languageCode: "ru", sourceText: "Hallo", targetText: "Привет",
            alternatives: ["Здравствуйте"], exampleSentence: nil,
            exampleTranslation: nil, dialect: ""
        )
        #expect(ContentQualityValidator.issues(for: candidate).isEmpty)
    }

    @Test func flagsScriptDuplicatesIncompleteExampleAndArabicVariety() {
        let candidate = ContentQualityCandidate(
            languageCode: "ar", sourceText: "Hallo", targetText: "marhaban",
            alternatives: ["مرحبا", "مَرْحَبًا", "مرحبا"],
            exampleSentence: "مرحباً يا سارة", exampleTranslation: nil, dialect: ""
        )
        let issues = ContentQualityValidator.issues(for: candidate)
        #expect(issues.contains(.unexpectedScript))
        #expect(issues.contains(.duplicatedAlternative))
        #expect(issues.contains(.incompleteExample))
        #expect(issues.contains(.missingArabicVariety))
    }
}
