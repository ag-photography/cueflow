import Foundation

/// Lesson composition is bounded; FSRS still owns memory dates, not session length.
enum SessionPlanner {
    static func cards(
        from cards: [StudyCard], reviews: [Review], target: Int,
        dailyNewLimit: Int, tutorIDs: Set<ContentID>, now: Date = .now, allowInactiveTopics: Bool = false
    ) -> [StudyCard] {
        let introduced = Set(reviews.compactMap { $0.card?.contentID })
        let newToday = Set(reviews.filter { $0.wasNew && Calendar.current.isDate($0.timestamp, inSameDayAs: now) }
            .compactMap { $0.card?.contentID }).count
        var remainingNew = max(0, dailyNewLimit - newToday)
        let due = cards.filter { $0.state != .new && $0.dueDate <= now }.sorted { $0.dueDate < $1.dueDate }
        let byCard = Dictionary(grouping: reviews.filter { $0.card != nil }, by: { $0.card!.contentID })
        let followups = cards.filter {
            ($0.state == .new && introduced.contains($0.contentID)) || ProductionFollowUp.pending(byCard[$0.contentID] ?? [])
        }
        let fresh = cards.filter {
            $0.state == .new && !introduced.contains($0.contentID)
                && (allowInactiveTopics || ($0.phrase?.topics?.contains(where: \.isActive) ?? false)
                    || $0.phrase.map { tutorIDs.contains($0.contentID) } == true)
        }.sorted {
            guard let lhs = $0.phrase, let rhs = $1.phrase else { return false }
            return NewCardOrdering.precedes(.init(phrase: lhs), .init(phrase: rhs))
        }
        let all = followups + due + fresh
        var selected: [StudyCard] = []
        var used: Set<ContentID> = []
        func take(_ candidates: [StudyCard]) {
            guard selected.count < target else { return }
            for card in candidates where !used.contains(card.contentID) {
                let isNew = card.state == .new && !introduced.contains(card.contentID)
                if isNew && remainingNew == 0 { continue }
                selected.append(card)
                used.insert(card.contentID)
                if isNew { remainingNew -= 1 }
                return
            }
        }
        let tutor = all.filter { $0.phrase.map { tutorIDs.contains($0.contentID) } == true }
        for slot in 0..<max(0, target) {
            if slot.isMultiple(of: 2) { take(tutor) }
            if selected.count <= slot { take(all) }
        }
        return selected
    }
}
