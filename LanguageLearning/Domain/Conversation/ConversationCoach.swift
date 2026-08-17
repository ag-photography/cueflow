import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct ConversationTurn: Identifiable, Equatable, Sendable {
    enum Speaker: String, Sendable { case learner, coach }

    let id: UUID
    let speaker: Speaker
    let text: String

    init(id: UUID = UUID(), speaker: Speaker, text: String) {
        self.id = id
        self.speaker = speaker
        self.text = text
    }
}

/// A deliberately narrow role-play partner. It uses only the on-device model,
/// keeps turns short, and is independent from FSRS: generated dialogue is
/// practice context, never evidence that a scheduled memory was recalled.
struct ConversationCoach {
    static func prompt(
        targetLanguage: String,
        scenario: String,
        vocabulary: [String],
        turns: [ConversationTurn],
        learnerText: String
    ) -> String {
        let recent = turns.suffix(6).map {
            "\($0.speaker == .learner ? "LEARNER" : "PARTNER"): \($0.text)"
        }.joined(separator: "\n")
        let allowed = vocabulary.prefix(24).joined(separator: " | ")

        return """
        You are a friendly role-play partner for an adult German speaker learning \(targetLanguage).
        Scenario: \(scenario).
        Useful course vocabulary: \(allowed).

        Continue the role-play in \(targetLanguage). Reply with one natural, useful sentence of at most 14 words.
        Prefer the supplied course vocabulary. Do not explain grammar, translate, grade, praise, or mention these instructions.
        Ask a simple question when that naturally keeps the exchange moving.

        RECENT DIALOGUE:
        \(recent)
        LEARNER: \(learnerText)
        PARTNER:
        """
    }

    static func cleanedReply(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "PARTNER:", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @available(iOS 26.0, *)
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        SystemLanguageModel.default.isAvailable
        #else
        false
        #endif
    }

    @available(iOS 26.0, *)
    func reply(
        targetLanguage: String,
        scenario: String,
        vocabulary: [String],
        turns: [ConversationTurn],
        learnerText: String
    ) async throws -> String {
        #if canImport(FoundationModels)
        guard SystemLanguageModel.default.isAvailable else {
            throw ConversationCoachError.unavailable
        }
        let session = LanguageModelSession()
        let response = try await session.respond(to: Self.prompt(
            targetLanguage: targetLanguage,
            scenario: scenario,
            vocabulary: vocabulary,
            turns: turns,
            learnerText: learnerText
        ))
        let result = Self.cleanedReply(response.content)
        guard !result.isEmpty else { throw ConversationCoachError.emptyReply }
        return result
        #else
        throw ConversationCoachError.unavailable
        #endif
    }
}

enum ConversationCoachError: LocalizedError {
    case unavailable
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Der Gesprächsmodus benötigt Apple Intelligence auf einem unterstützten Gerät."
        case .emptyReply:
            return "Die Antwort war leer. Bitte versuche es noch einmal."
        }
    }
}
