import Foundation

/// Private learning state, not an analytics event. Preserves the first attempt
/// and visible support across interruption before the learner confirms a grade.
struct CardAttemptCheckpoint: Codable, Identifiable {
    var id = UUID()
    let planID: UUID
    let cardKey: String
    var updatedAt = Date.now
    var result: GradeResult?
    var answer: String
    var responseTimeMs: Int
    var support: AttemptEvidence.Support
    var spoken: Bool
    var firstAnswer: String?
    var firstCorrect: Bool?
    var reviewMode: String?
    var inputAvailableMs: Int? = nil
    var gradingWaitMs: Int? = nil
    var timingInterrupted: Bool? = nil
}

extension LearningExperience {
    mutating func save(_ checkpoint: CardAttemptCheckpoint) {
        var values = cardAttempts ?? []
        if let index = values.firstIndex(where: { $0.id == checkpoint.id }) { values[index] = checkpoint }
        else { values.append(checkpoint) }
        cardAttempts = values
    }
}
