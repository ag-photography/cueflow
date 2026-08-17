import Foundation

/// A process-local read cache for navigation destinations. Today already owns
/// the live SwiftData queries needed by the primary action, so Library and
/// Progress can reuse those model instances instead of materializing the same
/// review graph again during a tab transition.
@MainActor
final class LearningDataCache {
    static let shared = LearningDataCache()

    private(set) var cards: [StudyCard] = []
    private(set) var reviews: [Review] = []
    private var eventsByLanguage: [String: [LearningEvent]] = [:]
    private(set) var isPrimed = false

    private init() {}

    func update(cards: [StudyCard], reviews: [Review]) {
        self.cards = cards
        self.reviews = reviews
        let grouped = Dictionary(grouping: reviews) {
            $0.card?.phrase?.language?.code ?? ""
        }
        eventsByLanguage = grouped.mapValues(LearningMotivation.events(from:))
        isPrimed = true
    }

    func events(languageCode: String) -> [LearningEvent] {
        eventsByLanguage[languageCode] ?? []
    }
}
