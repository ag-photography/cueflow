import Foundation

enum AdaptivePresentation: Equatable, Sendable {
    case choice
    case tiles
    case speech
}

enum AdaptiveExercisePolicy {
    static func presentation(
        state: LearningState,
        targetWordCount: Int,
        speechAvailable: Bool,
        recentRatings: [Int]
    ) -> AdaptivePresentation {
        if state == .new { return .choice }
        if !speechAvailable { return targetWordCount > 1 ? .tiles : .choice }

        let recentFailures = recentRatings.prefix(3).filter { $0 <= 2 }.count
        if targetWordCount > 1 && recentFailures >= 2 { return .tiles }
        return .speech
    }
}
