import Testing
@testable import LanguageLearning

struct ListeningPracticeTests {
    @Test func buildsChallengeWithUniquePlausibleOptions() throws {
        let challenge = try #require(ListeningPracticeBuilder.challenge(
            phraseID: "coffee",
            spokenText: "Кофе, пожалуйста.",
            meaning: "Kaffee, bitte.",
            languageCode: "ru",
            locale: "ru-RU",
            distractorMeanings: ["Tee, bitte.", "Die Rechnung, bitte.", "Tee, bitte.", "Danke."]
        ))

        #expect(challenge.options.count == 4)
        #expect(Set(challenge.options).count == 4)
        #expect(challenge.options.contains(challenge.correctMeaning))
    }

    @Test func rejectsEmptyOrUnderspecifiedChallenge() {
        #expect(ListeningPracticeBuilder.challenge(
            phraseID: "", spokenText: "", meaning: "Hallo", languageCode: "ru",
            locale: "ru-RU", distractorMeanings: ["A", "B"]
        ) == nil)
        #expect(ListeningPracticeBuilder.challenge(
            phraseID: "x", spokenText: "Привет", meaning: "Hallo", languageCode: "ru",
            locale: "ru-RU", distractorMeanings: ["Hallo", "Tschüss"]
        ) == nil)
    }
}
