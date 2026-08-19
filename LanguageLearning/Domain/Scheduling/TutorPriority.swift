import Foundation
import SwiftData

/// Resolves which phrases currently count as tutor-priority — once, from the
/// topic side.
///
/// `Phrase.isTutorPriorityActive` reads like a stored flag but expands into
/// `Topic.isTutorFocusActive` → `Topic.containsTutorMaterial`, which scans
/// *every phrase of every topic the phrase belongs to*. Asking each card the
/// question separately made that scan run once per card: profiling the practice
/// loop measured 526 ms to evaluate it across 2,010 cards, of which only 1.3 ms
/// was the phrase's own relationship fault. The rest was the same topic
/// contents walked over and over.
///
/// Resolving it here costs one pass over the topic graph regardless of how many
/// cards ask.
enum TutorPriority {
    static func phraseIDs(
        topics: [Topic],
        cards: [StudyCard],
        now: Date = .now
    ) -> Set<ContentID> {
        var ids: Set<ContentID> = []
        // Lesson focus: evaluate `isTutorFocusActive` once per topic.
        for topic in topics where topic.isTutorFocusActive(at: now) {
            for phrase in topic.phrases ?? [] {
                ids.insert(phrase.contentID)
            }
        }
        // The legacy per-phrase boost, which reads only stored scalars.
        for card in cards {
            guard let phrase = card.phrase, phrase.isPriorityActive else { continue }
            ids.insert(phrase.contentID)
        }
        return ids
    }
}
