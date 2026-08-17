import Foundation

/// Stable, duplicate-safe token used by the productive no-microphone fallback.
/// Identity is positional, so a sentence such as "да да" keeps both tiles.
struct WordTile: Identifiable, Equatable {
    let id: Int
    let text: String
}

enum TileConstruction {
    static func tokens(for target: String) -> [WordTile] {
        target
            .split(whereSeparator: { $0.isWhitespace })
            .enumerated()
            .map { WordTile(id: $0.offset, text: String($0.element)) }
    }

    static func answer(selectedIDs: [Int], from tiles: [WordTile]) -> String {
        selectedIDs
            .compactMap { id in tiles.first { $0.id == id }?.text }
            .joined(separator: " ")
    }

    static func isComplete(selectedIDs: [Int], tiles: [WordTile]) -> Bool {
        selectedIDs.count == tiles.count && Set(selectedIDs).count == tiles.count
    }
}
