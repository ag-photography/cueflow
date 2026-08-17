import Foundation

enum LearningErrorPattern: String, CaseIterable, Identifiable, Sendable {
    case omittedWords
    case addedWords
    case wordOrder
    case wordForm
    case slowRetrieval

    var id: String { rawValue }

    var title: String {
        switch self {
        case .omittedWords: return "Wörter vollständig abrufen"
        case .addedWords: return "Antwort präziser halten"
        case .wordOrder: return "Wortfolge festigen"
        case .wordForm: return "Wortformen genauer bilden"
        case .slowRetrieval: return "Schneller ins Sprechen kommen"
        }
    }

    var guidance: String {
        switch self {
        case .omittedWords: return "Sprich die ganze Modellantwort einmal langsam nach."
        case .addedWords: return "Vergleiche deine Antwort mit der kürzeren Kursformulierung."
        case .wordOrder: return "Baue die Antwort einmal mit Wortbausteinen auf."
        case .wordForm: return "Achte beim Wiederholen auf die markierten Unterschiede."
        case .slowRetrieval: return "Nutze eine kurze Sprint-Runde für häufige Ausdrücke."
        }
    }

    var systemImage: String {
        switch self {
        case .omittedWords: return "text.badge.minus"
        case .addedWords: return "text.badge.plus"
        case .wordOrder: return "arrow.left.arrow.right"
        case .wordForm: return "character.cursor.ibeam"
        case .slowRetrieval: return "timer"
        }
    }
}

struct LearningPatternInsight: Identifiable, Equatable, Sendable {
    let pattern: LearningErrorPattern
    let count: Int
    let exampleSource: String

    var id: String { pattern.id }
}

enum LearningInsightAnalyzer {
    static func patterns(from reviews: [Review], limit: Int = 3) -> [LearningPatternInsight] {
        let candidates = reviews
            .filter { $0.gradeTier >= 1 && !$0.userAnswer.isEmpty }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(40)

        var counts: [LearningErrorPattern: Int] = [:]
        var examples: [LearningErrorPattern: String] = [:]
        for review in candidates {
            guard let phrase = review.card?.phrase else { continue }
            let expected = words(phrase.targetText)
            let actual = words(review.userAnswer)

            if review.rating <= 2 {
                let pattern: LearningErrorPattern
                if actual.count < expected.count {
                    pattern = .omittedWords
                } else if actual.count > expected.count {
                    pattern = .addedWords
                } else if actual.sorted() == expected.sorted(), actual != expected {
                    pattern = .wordOrder
                } else {
                    pattern = .wordForm
                }
                counts[pattern, default: 0] += 1
                examples[pattern, default: phrase.sourceText] = phrase.sourceText
            }

            if review.responseTimeMs >= 9_000,
               review.rating >= 3,
               review.modeRaw == CardDirection.speakDeToRu.rawValue {
                counts[.slowRetrieval, default: 0] += 1
                examples[.slowRetrieval, default: phrase.sourceText] = phrase.sourceText
            }
        }

        return counts.map { pattern, count in
            LearningPatternInsight(
                pattern: pattern,
                count: count,
                exampleSource: examples[pattern] ?? ""
            )
        }
        .sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.pattern.rawValue < $1.pattern.rawValue
        }
        .prefix(limit)
        .map { $0 }
    }

    private static func words(_ value: String) -> [String] {
        FuzzyMatcher.normalize(value)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }
}

enum CurriculumReadiness: Equatable, Sendable {
    case foundationsNeeded
    case ready
    case inProgress
    case conversationReady
}

struct CurriculumStepProgress: Identifiable, Equatable, Sendable {
    let scenario: ScenarioDefinition
    let fraction: Double
    let readiness: CurriculumReadiness

    var id: String { scenario.id }
}

enum CurriculumPlanner {
    static func progress(
        scenarios: [ScenarioDefinition],
        fractions: [String: Double]
    ) -> [CurriculumStepProgress] {
        scenarios.map { scenario in
            let fraction = fractions[scenario.id] ?? 0
            let prerequisitesReady = scenario.prerequisiteIDs.allSatisfy {
                (fractions[$0] ?? 0) >= 0.4
            }
            let readiness: CurriculumReadiness
            if fraction >= 0.8 {
                readiness = .conversationReady
            } else if !prerequisitesReady {
                readiness = .foundationsNeeded
            } else if fraction > 0 {
                readiness = .inProgress
            } else {
                readiness = .ready
            }
            return CurriculumStepProgress(
                scenario: scenario,
                fraction: fraction,
                readiness: readiness
            )
        }
    }

    static func recommendation(from progress: [CurriculumStepProgress]) -> CurriculumStepProgress? {
        progress.first { $0.readiness == .inProgress }
            ?? progress.first { $0.readiness == .ready }
            ?? progress.first { $0.readiness == .foundationsNeeded }
    }
}
