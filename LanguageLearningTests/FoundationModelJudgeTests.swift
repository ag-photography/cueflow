import Testing
@testable import LanguageLearning

struct FoundationModelJudgeTests {
    @available(iOS 26.0, *)
    @Test func promptUsesSelectedTargetLanguage() {
        let prompt = FoundationModelJudge.buildPrompt(
            german: "Guten Morgen",
            expected: "صباح الخير",
            actual: "صباح الخير",
            targetLanguage: "Arabic"
        )

        #expect(prompt.contains("German into Arabic"))
        #expect(prompt.contains("Reference Arabic translation"))
        #expect(!prompt.contains("Russian"))
    }
}
