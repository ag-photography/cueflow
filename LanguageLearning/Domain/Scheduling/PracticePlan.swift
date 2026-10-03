import Foundation

struct PracticePlan: Codable, Equatable, Identifiable {
    var id = UUID()
    var version = 1
    var createdAt = Date.now
    let language: String
    let scope: String
    let mode: String
    let budget: Int
    let items: [Item]
    struct Item: Codable, Equatable {
        let key: String
        let reason: String
    }
    var estimatedSeconds: Int { items.count * 33 }
    func canResume(language: String, scope: String, mode: CardDirection, budget: Int,
                   endedIDs: [UUID], now: Date = .now) -> Bool {
        version == 1 && self.language == language && self.scope == scope && self.mode == mode.rawValue
            && self.budget == budget && !endedIDs.contains(id)
            && now >= createdAt && now.timeIntervalSince(createdAt) < 86_400
    }

    static func key(_ card: StudyCard) -> String {
        guard let phrase = card.phrase else { return "" }
        // Portable across backup restore. Do not persist store-local object IDs.
        return [phrase.language?.code ?? "", Phrase.normalize(phrase.sourceText), Phrase.normalize(phrase.targetText)].joined(separator: "\u{1F}")
    }
    func remaining(in cards: [StudyCard], reviews: [Review]) -> [StudyCard] {
        let done = Set(reviews.filter { $0.evidence?.sessionID == id && $0.evidence?.kind != "exposure" }
            .compactMap { $0.card.map(Self.key) })
        let grouped = Dictionary(grouping: cards, by: Self.key)
        return items.filter { !done.contains($0.key) }.compactMap { grouped[$0.key]?.first }
    }
    static func make(cards: [StudyCard], reviews: [Review], language: String, scope: String,
                     mode: CardDirection, budget: Int, dailyLimit: Int, tutorIDs: Set<ContentID>) -> Self {
        let selected = scope == "difficult" ? Array(cards.prefix(max(0, budget))) : SessionPlanner.cards(from: cards, reviews: reviews, target: budget,
            dailyNewLimit: dailyLimit, tutorIDs: tutorIDs, allowInactiveTopics: scope != "recommended")
        return .init(language: language, scope: scope, mode: mode.rawValue, budget: budget,
            items: selected.map { card in
                .init(key: key(card), reason: card.phrase.map { tutorIDs.contains($0.contentID) } == true ? "Unterricht" :
                    ProductionFollowUp.pending(card.reviews ?? []) ? "Ohne Hilfe abrufen" : card.state == .new ? "Neu" : "Wiederholung")
            })
    }
}

extension PracticeScope {
    var planKey: String {
        switch self {
        case .recommended: return "recommended"
        case .difficultThisWeek: return "difficult"
        case .scenario(let id): return "scenario:" + id
        case .topic(let id): return "topic:" + String(describing: id)
        }
    }
}
