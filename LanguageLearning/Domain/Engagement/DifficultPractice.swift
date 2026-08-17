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
        let eligibleIDs = Set(cards.compactMap { card -> String? in
            guard card.phrase?.language?.code == languageCode else { return nil }
            return String(describing: card.persistentModelID)
        })

        var evidence: [String: (errors: Int, latest: Date)] = [:]
        for review in reviews where review.timestamp >= start && review.timestamp <= now {
            guard review.rating <= 2 || review.autoGradeRating <= 2,
                  let card = review.card
            else { continue }
            let id = String(describing: card.persistentModelID)
            guard eligibleIDs.contains(id) else { continue }
            let old = evidence[id]
            evidence[id] = ((old?.errors ?? 0) + 1, max(old?.latest ?? .distantPast, review.timestamp))
        }

        return cards
            .filter { evidence[String(describing: $0.persistentModelID)] != nil }
            .sorted { lhs, rhs in
                let left = evidence[String(describing: lhs.persistentModelID)]!
                let right = evidence[String(describing: rhs.persistentModelID)]!
                if left.errors != right.errors { return left.errors > right.errors }
                return left.latest > right.latest
            }
    }
}
