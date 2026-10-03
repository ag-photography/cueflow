import Foundation

/// Grading route describes how an answer was checked, never how well it was recalled.
struct AttemptEvidence: Codable, Equatable, Sendable {
    enum Support: String, Codable { case none, tiles, revealed, retry, selfReported }
    let version: Int
    let id: UUID
    let support: Support
    let inputWasSpeech: Bool
    let assessedCorrect: Bool
    let gradingMethod: Int

    init(support: Support, inputWasSpeech: Bool, assessedCorrect: Bool, gradingMethod: Int) {
        version = 1
        id = UUID()
        self.support = support
        self.inputWasSpeech = inputWasSpeech
        self.assessedCorrect = assessedCorrect
        self.gradingMethod = gradingMethod
    }

    var encoded: String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

extension Review {
    var evidence: AttemptEvidence? {
        get {
            guard let evidenceJSON else { return nil }
            guard let decoded = try? JSONDecoder().decode(AttemptEvidence.self, from: Data(evidenceJSON.utf8)), decoded.version == 1 else {
                // Unknown metadata is not a legacy unaided success.
                return .init(support: .selfReported, inputWasSpeech: false, assessedCorrect: false, gradingMethod: 0)
            }
            return decoded
        }
        set { evidenceJSON = newValue?.encoded }
    }
}

enum LearningEvidencePolicy {
    static func productive(exercise: LearningExercise?, tier: Int, evidence: AttemptEvidence?) -> Bool {
        guard tier > 0, exercise == .speech || exercise == .typing || exercise == .cloze else { return false }
        // Historical records preserve recorded production, but cannot certify support.
        return evidence.map { $0.support == .none } ?? true
    }

    static func successful(exercise: LearningExercise?, tier: Int, rating: Int, evidence: AttemptEvidence?) -> Bool {
        productive(exercise: exercise, tier: tier, evidence: evidence)
            && rating >= 3 && (evidence?.assessedCorrect ?? true)
    }
}
