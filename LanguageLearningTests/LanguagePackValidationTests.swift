import Testing
@testable import LanguageLearning

struct LanguagePackValidationTests {
    @Test func bundledPacksAreInternallyConsistent() {
        #expect(LanguagePack.validationIssues(in: LanguagePack.supported).isEmpty)
        #expect(LanguagePack.supported.allSatisfy { $0.supportedFeatures.contains(.listeningLab) })
    }

    @Test func detectsDuplicateLanguageCodes() {
        #expect(LanguagePack.validationIssues(in: [.russian, .russian])
            .contains("Sprachcode mehrfach vorhanden: ru"))
    }
}
