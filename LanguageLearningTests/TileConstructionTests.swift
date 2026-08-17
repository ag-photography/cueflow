import XCTest
@testable import LanguageLearning

final class TileConstructionTests: XCTestCase {
    func testTokenizationCollapsesMixedWhitespace() {
        let tiles = TileConstruction.tokens(for: "  я\nхочу\tкофе  ")

        XCTAssertEqual(tiles.map(\.text), ["я", "хочу", "кофе"])
        XCTAssertEqual(tiles.map(\.id), [0, 1, 2])
    }

    func testDuplicateWordsRemainIndependentlySelectable() {
        let tiles = TileConstruction.tokens(for: "да да")

        XCTAssertEqual(tiles.count, 2)
        XCTAssertNotEqual(tiles[0].id, tiles[1].id)
        XCTAssertEqual(TileConstruction.answer(selectedIDs: [1, 0], from: tiles), "да да")
        XCTAssertTrue(TileConstruction.isComplete(selectedIDs: [1, 0], tiles: tiles))
    }

    func testArabicTextPreservesLogicalWordOrder() {
        let tiles = TileConstruction.tokens(for: "أريد قهوة من فضلك")

        XCTAssertEqual(tiles.map(\.text), ["أريد", "قهوة", "من", "فضلك"])
        XCTAssertEqual(
            TileConstruction.answer(selectedIDs: [0, 1, 2, 3], from: tiles),
            "أريد قهوة من فضلك"
        )
    }

    func testIncompleteAndDuplicateSelectionsAreRejected() {
        let tiles = TileConstruction.tokens(for: "я хочу кофе")

        XCTAssertFalse(TileConstruction.isComplete(selectedIDs: [0, 1], tiles: tiles))
        XCTAssertFalse(TileConstruction.isComplete(selectedIDs: [0, 1, 1], tiles: tiles))
    }
}
