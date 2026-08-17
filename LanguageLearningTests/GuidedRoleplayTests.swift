import Testing
@testable import LanguageLearning

struct GuidedRoleplayTests {
    @Test func shipsEquivalentScenarioCoverageForRussianAndArabic() {
        let russian = GuidedRoleplayLibrary.scenarios(languageCode: "ru")
        let arabic = GuidedRoleplayLibrary.scenarios(languageCode: "ar")

        #expect(russian.count == 6)
        #expect(arabic.count == 6)
        #expect(russian.map(\.title) == arabic.map(\.title))
        #expect(russian.allSatisfy { $0.steps.count >= 3 })
        #expect(arabic.allSatisfy { $0.steps.count >= 3 })
    }

    @Test func exactReferenceNeedsNoScaffoldAndAdvances() throws {
        let scenario = try #require(GuidedRoleplayLibrary.scenarios(languageCode: "ru").first)
        let progress = try #require(GuidedRoleplayEngine.progress(
            scenario: scenario,
            stepIndex: 0,
            learnerText: "кофе пожалуйста"
        ))

        #expect(progress.support == .independent)
        #expect(!progress.isComplete)
        #expect(progress.nextPartnerText != nil)
    }

    @Test func distantAnswerShowsModelWithoutClaimingItIsWrong() throws {
        let scenario = try #require(GuidedRoleplayLibrary.scenarios(languageCode: "ar").first)
        let progress = try #require(GuidedRoleplayEngine.progress(
            scenario: scenario,
            stepIndex: 0,
            learnerText: "مرحبا"
        ))

        guard case .model(let reference) = progress.support else {
            Issue.record("Expected model scaffold")
            return
        }
        #expect(reference == "قهوة من فضلك.")
    }

    @Test func finalStepCompletesScenario() throws {
        let scenario = try #require(GuidedRoleplayLibrary.scenarios(languageCode: "ru").first)
        let progress = try #require(GuidedRoleplayEngine.progress(
            scenario: scenario,
            stepIndex: 2,
            learnerText: "Спасибо"
        ))

        #expect(progress.isComplete)
        #expect(progress.nextPartnerText == nil)
    }

    @Test func authoredSignalsCreateARealConversationBranch() throws {
        let scenario = try #require(GuidedRoleplayLibrary.scenarios(languageCode: "ru")
            .first { $0.id == "ru-shopping" })
        let progress = try #require(GuidedRoleplayEngine.progress(
            scenario: scenario,
            stepIndex: 1,
            learnerText: "Синюю, пожалуйста."
        ))
        #expect(progress.partnerReply.contains("синяя"))
    }
}
