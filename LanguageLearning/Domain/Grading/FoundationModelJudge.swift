import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Tier-3 grading via Apple's on-device foundation model. Advisory only:
/// can soften a Tier-2 `wrong` to `minor` (or `hesitant` if the judge thinks
/// the answer is fully equivalent) and can soften `minor` to `hesitant`.
///
/// **Never promotes to `perfect`.** The judge is opinion, not truth — keep the
/// safety floor at `hesitant` so the user still gets their override row.
///
/// Requires iOS 26+ AND an Apple-Intelligence-capable device. Falls back
/// silently to nil otherwise. Hard latency cap of 600 ms; on timeout the
/// caller keeps the Tier-2 verdict.
@available(iOS 26.0, *)
struct FoundationModelJudge {

    enum Verdict: Equatable {
        case equivalent
        case minorMorphology(note: String?)
        case minorWordChoice(note: String?)
        case wrong
        case unparseable
    }

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    /// Returns nil if the model is unavailable, the call times out, or the
    /// session throws. Otherwise returns a parsed verdict (which may be
    /// `.unparseable` if the model wandered off-format — caller treats that as
    /// "no signal").
    func judge(
        german: String,
        expected: String,
        actual: String,
        timeoutMs: Int = 600
    ) async -> Verdict? {
        #if canImport(FoundationModels)
        guard SystemLanguageModel.default.isAvailable else { return nil }

        let prompt = Self.buildPrompt(german: german, expected: expected, actual: actual)
        let session = LanguageModelSession()

        return await withTaskGroup(of: Verdict?.self) { group in
            group.addTask {
                do {
                    let response = try await session.respond(to: prompt)
                    return Self.parse(response.content)
                } catch {
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
                return nil
            }
            // Take the first result, cancel the rest.
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? nil
        }
        #else
        return nil
        #endif
    }

    static func buildPrompt(german: String, expected: String, actual: String) -> String {
        """
        You are grading a learner translating from German into Russian.

        German source: "\(german)"
        Reference Russian translation: "\(expected)"
        Learner answered: "\(actual)"

        Decide how close the learner's answer is. Reply with EXACTLY one line, \
        in one of these formats (no extra text, no quotes):

        equivalent
        minor-morphology: <up to 6 words naming the issue>
        minor-word-choice: <up to 6 words naming the issue>
        wrong

        Use "equivalent" only when the meaning is the same and any differences are \
        purely orthographic. Use "minor-morphology" for case/aspect/agreement \
        slips. Use "minor-word-choice" for a different but acceptable synonym. \
        Use "wrong" if the meaning has changed.
        """
    }

    static func parse(_ raw: String) -> Verdict {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = trimmed
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? trimmed
        let lower = line.lowercased()

        if lower.hasPrefix("equivalent") {
            return .equivalent
        }
        if lower.hasPrefix("minor-morphology") {
            return .minorMorphology(note: noteAfterColon(in: line))
        }
        if lower.hasPrefix("minor-word-choice") {
            return .minorWordChoice(note: noteAfterColon(in: line))
        }
        if lower.hasPrefix("wrong") {
            return .wrong
        }
        return .unparseable
    }

    private static func noteAfterColon(in line: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let tail = line[line.index(after: colon)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.isEmpty ? nil : tail
    }
}
