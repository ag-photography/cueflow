import XCTest
@testable import LanguageLearning

final class ProgressionSystemTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(
        dayOffset: Int = 0,
        phrase: String,
        topics: Set<String> = ["one"],
        rating: Int = 4,
        tier: Int = 3
    ) -> LearningEvent {
        LearningEvent(
            timestamp: Calendar.current.date(byAdding: .day, value: dayOffset, to: now)!,
            phraseID: phrase,
            sourceText: phrase,
            topicIDs: topics,
            exercise: .speech,
            rating: rating,
            gradeTier: tier,
            responseTimeMs: 2_000,
            spokenWordCount: 3
        )
    }

    func testCapabilityLevelsUseProductiveRecallFractions() {
        let scenario = ScenarioDefinition(
            id: "foundation", title: "Foundation", outcome: "Use it",
            systemImage: "star", topicTerms: [], prerequisiteIDs: []
        )
        let progress = ProgressionSystem.capabilities(
            scenarios: [scenario],
            phraseIDsByScenario: ["foundation": ["a", "b", "c", "d", "e"]],
            events: [event(phrase: "a"), event(phrase: "b")]
        )

        XCTAssertEqual(progress.first?.level, .use)
        XCTAssertEqual(progress.first?.productivePhraseCount, 2)
        XCTAssertEqual(progress.first?.fraction, 0.4)
    }

    func testPrerequisitesUnlockAtUseLevel() {
        let first = ScenarioDefinition(
            id: "first", title: "First", outcome: "", systemImage: "1.circle",
            topicTerms: [], prerequisiteIDs: []
        )
        let second = ScenarioDefinition(
            id: "second", title: "Second", outcome: "", systemImage: "2.circle",
            topicTerms: [], prerequisiteIDs: ["first"]
        )
        let ids: [String: Set<String>] = ["first": ["a", "b"], "second": ["c"]]

        let locked = ProgressionSystem.capabilities(
            scenarios: [first, second], phraseIDsByScenario: ids, events: []
        )
        XCTAssertFalse(locked[1].isUnlocked)

        let unlocked = ProgressionSystem.capabilities(
            scenarios: [first, second], phraseIDsByScenario: ids, events: [event(phrase: "a")]
        )
        XCTAssertTrue(unlocked[1].isUnlocked)
    }

    func testWeeklyMissionsCountDaysRecoveryAndBreadth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let events = [
            event(dayOffset: -2, phrase: "recover", topics: ["one"], rating: 1, tier: 1),
            event(dayOffset: -1, phrase: "recover", topics: ["two"]),
            event(dayOffset: 0, phrase: "other", topics: ["three"]),
        ]
        let missions = ProgressionSystem.weeklyMissions(events: events, now: now, calendar: calendar)

        XCTAssertEqual(missions.first { $0.kind == .productiveDays }?.current, 2)
        XCTAssertEqual(missions.first { $0.kind == .recoveredPhrases }?.current, 1)
        XCTAssertEqual(missions.first { $0.kind == .conversationBreadth }?.current, 2)
    }

    func testProgressionAnalysisRemainsFastForLargeHistory() {
        let events = (0..<20_000).map { index in
            event(phrase: "phrase-\(index % 2_000)", topics: ["topic-\(index % 20)"])
        }
        measure {
            _ = ProgressionSystem.weeklyMissions(events: events, now: now)
        }
    }

    func testMilestonesAreDerivedFromLearningEvidence() {
        let scenario = ScenarioDefinition(
            id: "one", title: "One", outcome: "", systemImage: "star",
            topicTerms: [], prerequisiteIDs: []
        )
        let capabilities = ProgressionSystem.capabilities(
            scenarios: [scenario],
            phraseIDsByScenario: ["one": ["a"]],
            events: [event(phrase: "a")]
        )
        let milestones = ProgressionSystem.milestones(
            capabilities: capabilities,
            weeklyMissions: [],
            events: [event(phrase: "a")]
        )

        XCTAssertTrue(milestones.first { $0.id == "first-recall" }?.isEarned == true)
        XCTAssertTrue(milestones.first { $0.id == "conversation-ready" }?.isEarned == true)
        XCTAssertTrue(milestones.first { $0.id == "weekly-flow" }?.isEarned == false)
    }
}
