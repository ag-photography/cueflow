import XCTest
@testable import LanguageLearning

final class NewCardOrderingTests: XCTestCase {
    private func candidate(
        source: PhraseContentSource = .bundled,
        level: PhraseLevel = .a2,
        frequency: Int? = nil,
        daysAgo: Double = 0
    ) -> NewCardOrdering.Candidate {
        NewCardOrdering.Candidate(
            provenanceRank: source.provenanceRank,
            level: level,
            frequencyRank: frequency,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 - daysAgo * 86_400)
        )
    }

    func testLearnerContentOutranksBundledContent() {
        let pasted = candidate(source: .tutorImport, level: .b2, frequency: 90_000, daysAgo: 30)
        let bundled = candidate(source: .bundled, level: .a2, frequency: 0)
        XCTAssertTrue(NewCardOrdering.precedes(pasted, bundled))
        XCTAssertFalse(NewCardOrdering.precedes(bundled, pasted))
    }

    func testLearnerContentKeepsNewestFirst() {
        let fresh = candidate(source: .tutorImport, daysAgo: 0)
        let older = candidate(source: .tutorImport, daysAgo: 7)
        XCTAssertTrue(NewCardOrdering.precedes(fresh, older), "You added it because you want it now")
    }

    func testBundledContentFollowsFrequencyNotInsertionOrder() {
        // The regression this exists to prevent: a rare word inserted later
        // outranking a common one purely because it is newer.
        let common = candidate(frequency: 3, daysAgo: 100)
        let rare = candidate(frequency: 900, daysAgo: 0)
        XCTAssertTrue(NewCardOrdering.precedes(common, rare))
    }

    func testEasierBandComesFirstEvenWhenLessFrequentWithinIt() {
        let a2 = candidate(level: .a2, frequency: 200)
        let b1 = candidate(level: .b1, frequency: 0)
        XCTAssertTrue(NewCardOrdering.precedes(a2, b1))
    }

    func testUnrankedBundledWordsSortAfterRankedOnes() {
        let ranked = candidate(frequency: 500)
        let unranked = candidate(frequency: nil)
        XCTAssertTrue(NewCardOrdering.precedes(ranked, unranked))
        XCTAssertFalse(NewCardOrdering.precedes(unranked, ranked))
    }

    func testUnlabelledLevelSitsWithA2RatherThanAheadOfEverything() {
        let a1 = candidate(level: .a1, frequency: 900)
        let unspecified = candidate(level: .unspecified, frequency: 0)
        XCTAssertTrue(NewCardOrdering.precedes(a1, unspecified), "A1 still leads")
        let b1 = candidate(level: .b1, frequency: 0)
        XCTAssertTrue(NewCardOrdering.precedes(unspecified, b1))
    }

    func testOrderingIsAStrictWeakOrdering() {
        let all = [
            candidate(source: .manual, daysAgo: 1),
            candidate(source: .tutorImport, daysAgo: 2),
            candidate(level: .a1, frequency: 10),
            candidate(level: .a2, frequency: 5),
            candidate(level: .a2, frequency: nil),
            candidate(level: .b2, frequency: 1),
        ]
        for item in all {
            XCTAssertFalse(NewCardOrdering.precedes(item, item), "must be irreflexive")
        }
        // Sorting must not trap, which it would on an inconsistent comparator.
        let sorted = all.sorted(by: NewCardOrdering.precedes)
        XCTAssertEqual(sorted.count, all.count)
        XCTAssertEqual(sorted.first?.provenanceRank, PhraseContentSource.manual.provenanceRank)
    }

    func testBundledFrequencyListIsLoadedAndOrdered() throws {
        // Sanity-check the real bundle: в is the most frequent A2 entry.
        let common = try XCTUnwrap(VocabFrequency.rank(forTarget: "в"))
        let rarer = try XCTUnwrap(VocabFrequency.rank(forTarget: "который"))
        XCTAssertLessThan(common, rarer)
        XCTAssertNil(VocabFrequency.rank(forTarget: "щмзщмз"), "Unknown words have no rank")
    }
}
