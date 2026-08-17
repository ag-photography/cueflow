import XCTest
@testable import LanguageLearning

final class LearningMotivationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(
        minutesAgo: Double = 0,
        phrase: String = UUID().uuidString,
        source: String = "Kaffee, bitte",
        topics: Set<String> = ["cafe"],
        exercise: LearningExercise = .speech,
        rating: Int = 4,
        tier: Int = 3,
        milliseconds: Int = 1_800,
        words: Int = 4
    ) -> LearningEvent {
        LearningEvent(
            timestamp: now.addingTimeInterval(-minutesAgo * 60),
            phraseID: phrase,
            sourceText: source,
            topicIDs: topics,
            exercise: exercise,
            rating: rating,
            gradeTier: tier,
            responseTimeMs: milliseconds,
            spokenWordCount: words
        )
    }

    func testDailyQuestsCountOnlyProductiveOutput() {
        let events = [
            event(words: 12),
            event(exercise: .typing, words: 0),
            event(exercise: .choice, tier: 0, words: 0),
            event(exercise: .flip, tier: 0, words: 0),
        ]

        let quests = LearningMotivation.dailyQuests(events: events, now: now)
        XCTAssertEqual(quests.first { $0.kind == .retrieve }?.current, 2)
        XCTAssertEqual(quests.first { $0.kind == .speak }?.current, 12)
        XCTAssertEqual(quests.first { $0.kind == .deepenMission }?.current, 2)
    }

    func testMissionQuestUsesSingleDeepestTopicRatherThanTotal() {
        let events = [
            event(topics: ["cafe"]), event(topics: ["cafe"]), event(topics: ["cafe"]),
            event(topics: ["travel"]), event(topics: ["travel"]),
        ]
        let quest = LearningMotivation.dailyQuests(events: events, now: now)
            .first { $0.kind == .deepenMission }

        XCTAssertEqual(quest?.current, 3)
        XCTAssertFalse(quest?.isComplete ?? true)
    }

    func testFastestRecordRequiresStrongProductiveRecall() {
        let valid = event(phrase: "valid", milliseconds: 1_900)
        let recognition = event(phrase: "choice", exercise: .choice, tier: 0, milliseconds: 200)
        let weak = event(phrase: "weak", rating: 2, tier: 1, milliseconds: 500)

        XCTAssertEqual(
            LearningMotivation.fastestStrongRecall(events: [valid, recognition, weak])?.phraseID,
            "valid"
        )
    }

    func testImprovementRequiresFailureBeforeLaterStrongRecall() {
        let failed = event(minutesAgo: 10, phrase: "coffee", rating: 1, tier: 1)
        let recovered = event(minutesAgo: 2, phrase: "coffee", rating: 4, tier: 3)
        let alwaysStrong = event(minutesAgo: 1, phrase: "hello", rating: 4, tier: 3)

        XCTAssertEqual(
            LearningMotivation.mostRecentImprovement(events: [failed, recovered, alwaysStrong])?.phraseID,
            "coffee"
        )
    }

    func testCapabilityFractionCountsDistinctStrongPhrases() {
        let events = [
            event(phrase: "one"), event(phrase: "one"), event(phrase: "two"),
        ]

        XCTAssertEqual(
            LearningMotivation.strongRecallFraction(events: events, phraseIDs: ["one", "two", "three", "four"]),
            0.5
        )
    }
}
