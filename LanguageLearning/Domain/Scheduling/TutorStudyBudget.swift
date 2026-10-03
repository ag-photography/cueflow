import Foundation

struct TutorStudyBudget: Equatable {
    let opportunities: Int
    let remaining: Int
    let dailyLimit: Int
    var requiredPerOpportunity: Int { Int(ceil(Double(remaining) / Double(max(1, opportunities)))) }
    var shortfall: Int { max(0, remaining - opportunities * max(0, dailyLimit)) }
    static func make(remaining: Int, deadline: Date?, weekdays: [Int]?, dailyLimit: Int,
                     now: Date = .now, calendar: Calendar = .current) -> Self {
        let end = deadline ?? calendar.date(byAdding: .day, value: 7, to: now) ?? now
        guard end >= now else { return .init(opportunities: 0, remaining: max(0, remaining), dailyLimit: dailyLimit) }
        var date = calendar.startOfDay(for: now)
        let days = Set(weekdays ?? Array(1...7))
        var count = 0
        // Bounded even for corrupt/imported dates centuries into the future.
        for _ in 0..<366 {
            guard date <= end else { break }
            if days.contains(calendar.component(.weekday, from: date)) { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return .init(opportunities: count, remaining: max(0, remaining), dailyLimit: dailyLimit)
    }
}

enum DurableRecall {
    /// A later exposure invalidates current retention evidence, but does not
    /// erase the historical achievement. Unknown legacy support cannot certify it.
    static func demonstrated(_ reviews: [Review], after barrier: Date? = nil) -> Bool {
        let ordered = reviews.sorted { $0.timestamp < $1.timestamp }
        guard let last = ordered.last, let evidence = last.evidence,
              evidence.support == .none, evidence.assessedCorrect, last.gradeTier > 0,
              evidence.kind != "exposure" else { return false }
        let previous = max(ordered.dropLast().map(\.timestamp).max() ?? .distantPast,
                           evidence.previousExposureAt ?? .distantPast, barrier ?? .distantPast)
        guard previous != .distantPast else { return false }
        return last.timestamp.timeIntervalSince(previous) >= 7 * 86_400
    }
}
