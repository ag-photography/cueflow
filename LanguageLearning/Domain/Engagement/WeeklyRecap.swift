import Foundation

struct WeeklyRecapSummary: Equatable, Sendable {
    let answers: Int
    let newlyIntroduced: Int
    let successfulSpokenRecalls: Int

    var notificationBody: String {
        if answers == 0 {
            return "Diese Woche wartet noch auf deinen ersten gesprochenen Ausdruck."
        }
        return "Diese Woche: \(answers) Antworten, \(newlyIntroduced) neue Ausdrücke und \(successfulSpokenRecalls) erfolgreiche Sprechabrufe."
    }
}

enum WeeklyRecap {
    static func summary(
        reviews: [Review],
        languageCode: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> WeeklyRecapSummary {
        let interval = calendar.dateInterval(of: .weekOfYear, for: now)
        let relevant = reviews.filter {
            $0.card?.phrase?.language?.code == languageCode
                && (interval?.contains($0.timestamp) ?? false)
        }
        return WeeklyRecapSummary(
            answers: relevant.count,
            newlyIntroduced: relevant.filter(\.wasNew).count,
            successfulSpokenRecalls: relevant.filter {
                $0.modeRaw == CardDirection.speakDeToRu.rawValue
                    && $0.rating >= 3
                    && $0.gradeTier >= 2
            }.count
        )
    }
}
