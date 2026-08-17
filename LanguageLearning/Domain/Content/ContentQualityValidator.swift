import Foundation

enum ContentQualityIssue: String, CaseIterable, Identifiable, Sendable {
    case missingSource
    case missingTarget
    case unexpectedScript
    case duplicatedAlternative
    case incompleteExample
    case missingArabicVariety

    var id: String { rawValue }
    var message: String {
        switch self {
        case .missingSource: return "Deutsche Bedeutung fehlt"
        case .missingTarget: return "Zielsprachlicher Ausdruck fehlt"
        case .unexpectedScript: return "Zieltext verwendet nicht die erwartete Schrift"
        case .duplicatedAlternative: return "Zulässige Varianten enthalten Duplikate"
        case .incompleteExample: return "Beispielsatz oder Übersetzung fehlt"
        case .missingArabicVariety: return "Arabische Varietät noch nicht angegeben"
        }
    }
}

struct ContentQualityCandidate: Equatable, Sendable {
    let languageCode: String
    let sourceText: String
    let targetText: String
    let alternatives: [String]
    let exampleSentence: String?
    let exampleTranslation: String?
    let dialect: String
}

enum ContentQualityValidator {
    static func issues(for candidate: ContentQualityCandidate) -> [ContentQualityIssue] {
        var issues: [ContentQualityIssue] = []
        if candidate.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.missingSource)
        }
        if candidate.targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.missingTarget)
        }
        if !candidate.targetText.isEmpty && !usesExpectedScript(candidate.targetText, code: candidate.languageCode) {
            issues.append(.unexpectedScript)
        }
        let normalizedAlternatives = candidate.alternatives.map(Phrase.normalize)
        if Set(normalizedAlternatives).count != normalizedAlternatives.count {
            issues.append(.duplicatedAlternative)
        }
        if (candidate.exampleSentence == nil) != (candidate.exampleTranslation == nil) {
            issues.append(.incompleteExample)
        }
        if candidate.languageCode == "ar"
            && candidate.dialect.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.missingArabicVariety)
        }
        return issues
    }

    private static func usesExpectedScript(_ value: String, code: String) -> Bool {
        switch code {
        case "ru": return value.unicodeScalars.contains { (0x0400...0x052F).contains($0.value) }
        case "ar": return value.unicodeScalars.contains {
            (0x0600...0x06FF).contains($0.value)
                || (0x0750...0x077F).contains($0.value)
                || (0x08A0...0x08FF).contains($0.value)
        }
        default: return true
        }
    }
}

extension ContentQualityCandidate {
    init(phrase: Phrase) {
        self.init(
            languageCode: phrase.language?.code ?? "",
            sourceText: phrase.sourceText,
            targetText: phrase.targetText,
            alternatives: phrase.acceptedAlternatives,
            exampleSentence: phrase.exampleSentence,
            exampleTranslation: phrase.exampleSentenceTranslation,
            dialect: phrase.dialect
        )
    }
}
