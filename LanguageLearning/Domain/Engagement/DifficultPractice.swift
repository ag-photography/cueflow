import Foundation
import SwiftData

enum PracticeScope: Equatable, Sendable {
    case recommended
    case difficultThisWeek
    case topic(id: PersistentIdentifier)

    func includes(_ card: StudyCard) -> Bool {
        switch self {
        case .recommended, .difficultThisWeek:
            return true
        case .topic(let id):
            return card.phrase?.topics?.contains {
                $0.persistentModelID == id
            } ?? false
        }
    }
}

struct DifficultPractice {
    static func candidates(
        cards: [StudyCard],
        reviews: [Review],
        languageCode: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [StudyCard] {
        guard let start = calendar.date(byAdding: .day, value: -7, to: now) else { return [] }
        let eligibleIDs = Set(cards.compactMap { card -> ContentID? in
            guard card.phrase?.language?.code == languageCode else { return nil }
            return card.contentID
        })

        var evidence: [ContentID: (errors: Int, latest: Date)] = [:]
        for review in reviews where review.timestamp >= start && review.timestamp <= now {
            guard review.rating <= 2 || review.autoGradeRating <= 2,
                  let card = review.card
            else { continue }
            let id = card.contentID
            guard eligibleIDs.contains(id) else { continue }
            let old = evidence[id]
            evidence[id] = ((old?.errors ?? 0) + 1, max(old?.latest ?? .distantPast, review.timestamp))
        }
        guard !evidence.isEmpty else { return [] }

        // Decorate before sorting: looking the evidence up inside the comparator
        // would repeat the lookup O(n log n) times for no benefit.
        return cards
            .compactMap { card in evidence[card.contentID].map { (card: card, weight: $0) } }
            .sorted { lhs, rhs in
                if lhs.weight.errors != rhs.weight.errors { return lhs.weight.errors > rhs.weight.errors }
                return lhs.weight.latest > rhs.weight.latest
            }
            .map(\.card)
    }
}
