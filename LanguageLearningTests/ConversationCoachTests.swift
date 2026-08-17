import Testing
@testable import LanguageLearning

struct ConversationCoachTests {
    @Test func promptIsLanguageAndVocabularyScoped() {
        let result = ConversationCoach.prompt(
            targetLanguage: "Arabisch",
            scenario: "Im Café",
            vocabulary: ["قهوة", "من فضلك"],
            turns: [.init(speaker: .coach, text: "مرحباً")],
            learnerText: "قهوة من فضلك"
        )

        #expect(result.contains("Arabisch"))
        #expect(result.contains("Im Café"))
        #expect(result.contains("قهوة | من فضلك"))
        #expect(result.contains("LEARNER: قهوة من فضلك"))
        #expect(result.contains("at most 14 words"))
    }

    @Test func replyCleanupRemovesRolePrefixAndWhitespace() {
        #expect(ConversationCoach.cleanedReply("  PARTNER: Привет!  \n") == "Привет!")
    }
}
