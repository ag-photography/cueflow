import Foundation

/// Auto-graded outcome before any user override. Drives the suggested FSRS rating
/// and the reveal-screen colour chip.
enum AutoGrade {
    case perfect    // Tier 1 exact match, fast
    case hesitant   // Tier 1 exact match, slow (or via accepted alternative)
    case minor      // Tier 2: 1–2 char edits in a single word (likely morphology)
    case wrong      // Tier 2: multi-word or major edits
    case studied    // User pressed "Ich weiß es nicht", then copied the answer
                    // correctly. SRS-wise this is still rating 1 (didn't
                    // recall) but the UI label is encouraging rather than
                    // punitive — they did real work.
}

extension AutoGrade {
    /// FSRS rating value (1=Again, 2=Hard, 3=Good, 4=Easy).
    var suggestedRating: Int {
        switch self {
        case .perfect: return 4
        case .hesitant: return 3
        case .minor: return 2
        case .wrong: return 1
        case .studied: return 1
        }
    }

    var label: String {
        switch self {
        case .perfect: return "Perfekt"
        case .hesitant: return "Zögernd"
        case .minor: return "Fast"
        case .wrong: return "Falsch"
        case .studied: return "Geübt"
        }
    }
}

struct GradeResult {
    let autoGrade: AutoGrade
    let tier: Int   // 1, 2, or 3
    let normalizedExpected: String
    let normalizedActual: String
    let editedWords: Int
    let totalEdits: Int
}
