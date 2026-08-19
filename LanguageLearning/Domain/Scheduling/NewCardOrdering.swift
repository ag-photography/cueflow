import Foundation
import SwiftData

/// Read-only frequency lookup over the bundled vocabulary list.
///
/// `openrussian-vocab.json` is already ordered by frequency inside each CEFR
/// band — the A2 band opens with в, на, а, как, но — but nothing used that
/// order, so the scheduler introduced bundled cards by creation date. Loaded
/// once, lazily, from the bundle; no schema change and no migration.
enum VocabFrequency {
    private static let ranks: [String: Int] = load()

    /// Bands in teaching order. Words outside the list have no rank.
    private static let bandOrder = ["A1", "A2", "B1", "B2", "C1"]

    private static func load() -> [String: Int] {
        guard
            let url = Bundle.main.url(forResource: "openrussian-vocab", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String: [Entry]].self, from: data)
        else { return [:] }

        var result: [String: Int] = [:]
        // Rank is band-major so a common B1 word never outranks a rare A2 one.
        for (band, entries) in decoded {
            let bandBase = (bandOrder.firstIndex(of: band) ?? bandOrder.count) * 100_000
            for (index, entry) in entries.enumerated() {
                let key = normalize(entry.ru)
                // First occurrence wins: the earlier position is the more
                // frequent sense of the same spelling.
                if result[key] == nil { result[key] = bandBase + index }
            }
        }
        return result
    }

    private struct Entry: Decodable {
        let ru: String
    }

    /// Lower is more frequent. `nil` when the expression isn't in the bundled
    /// list — user content, Arabic, and multi-word phrases mostly land here.
    static func rank(forTarget target: String) -> Int? {
        ranks[normalize(target)]
    }

    private static func normalize(_ word: String) -> String {
        ClozeBuilder.compareKey(word.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Decides which unseen card to introduce next.
///
/// Two populations with opposite needs share this queue. Content the learner
/// just added — a pasted lesson, a manual entry — should surface immediately,
/// so it stays newest-first. The bundled backlog should not: introducing it
/// newest-first meant a rare B2 word queued ahead of the most common
/// preposition in the language, purely because of insertion order.
enum NewCardOrdering {
    struct Candidate: Equatable, Sendable {
        let provenanceRank: Int
        let level: PhraseLevel
        let frequencyRank: Int?
        let createdAt: Date

        init(provenanceRank: Int, level: PhraseLevel, frequencyRank: Int?, createdAt: Date) {
            self.provenanceRank = provenanceRank
            self.level = level
            self.frequencyRank = frequencyRank
            self.createdAt = createdAt
        }
    }

    /// True when `lhs` should be introduced before `rhs`.
    static func precedes(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        // 1. Learner-supplied content first, by provenance.
        if lhs.provenanceRank != rhs.provenanceRank {
            return lhs.provenanceRank < rhs.provenanceRank
        }
        // 2. Learner-supplied content keeps newest-first: you added it because
        //    you want it now.
        let isLearnerContent = lhs.provenanceRank < PhraseContentSource.bundled.provenanceRank
        if isLearnerContent {
            return lhs.createdAt > rhs.createdAt
        }
        // 3. Bundled content follows the curriculum: easier band first…
        if lhs.level != rhs.level {
            return levelOrder(lhs.level) < levelOrder(rhs.level)
        }
        // …then frequency, with unranked words after ranked ones.
        switch (lhs.frequencyRank, rhs.frequencyRank) {
        case let (left?, right?) where left != right:
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            break
        }
        return lhs.createdAt > rhs.createdAt
    }

    private static func levelOrder(_ level: PhraseLevel) -> Int {
        switch level {
        case .a1: return 0
        case .a2: return 1
        case .b1: return 2
        case .b2: return 3
        case .c1: return 4
        // Unlabelled content sits with A2 rather than ahead of everything: it is
        // usually seed material without explicit metadata.
        case .unspecified: return 1
        }
    }
}

extension NewCardOrdering.Candidate {
    init(phrase: Phrase) {
        self.init(
            provenanceRank: phrase.contentSource.provenanceRank,
            level: phrase.level,
            frequencyRank: VocabFrequency.rank(forTarget: phrase.targetText),
            createdAt: phrase.createdAt
        )
    }
}
