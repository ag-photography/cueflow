import Foundation

/// Arcade games are presentations of the learner's Ausdrücke. Matching games are
/// recognition warm-ups; recall from memory feeds FSRS via `ActivityRecall`.
enum ArcadeMode: String, Identifiable, CaseIterable {
    case mix, snap, sound, swipe, builder, recall
    var id: String { rawValue }
    /// Games with their own entry in Frei üben. Hör hin, Satzbau and Aus dem
    /// Kopf do jobs Hörstudio, Üben and Sprint already own, so they appear only
    /// as steps inside the Spiele-Mix (docs/coherence.md → Subtraction).
    static let standalone: [ArcadeMode] = [.mix, .snap, .swipe]
    var symbol: String {
        switch self {
        case .mix, .snap: return "square.grid.2x2.fill"
        case .sound: return "waveform"
        case .swipe: return "arrow.left.arrow.right"
        case .builder: return "puzzlepiece.extension.fill"
        case .recall: return "brain.head.profile"
        }
    }
    var title: String {
        switch self { case .mix: return "Spiele-Mix"; case .snap: return "Paare finden"; case .sound: return "Hör hin"; case .swipe: return "Wisch & triff"; case .builder: return "Satzbau"; case .recall: return "Aus dem Kopf" }
    }
}

struct ArcadeWord: Identifiable, Equatable {
    let id: String
    let source: String
    let target: String
    let alternatives: [String]
}

enum VocabularyArcade {
    struct Board {
        let mode: ArcadeMode
        let words: [ArcadeWord]
    }

    static func plan(from candidates: [ArcadeWord], mode: ArcadeMode) -> [Board] {
        let pool = unique(candidates, limit: 64)
        let phrases = unique(candidates.filter { (2...8).contains(TileConstruction.tokens(for: $0.target).count) }, limit: 4)
        func board(_ kind: ArcadeMode, _ words: [ArcadeWord], _ index: Int) -> Board {
            Board(mode: kind, words: words.map {
                ArcadeWord(id: $0.id + ":\(index)", source: $0.source, target: $0.target, alternatives: $0.alternatives)
            })
        }
        if mode == .mix {
            guard pool.count >= 4 else { return [] }
            var result = [board(.snap, Array(pool.prefix(4)), 0),
                          board(.sound, [pool[1]], 1), board(.swipe, [pool[2]], 2)]
            if let phrase = phrases.first { result.append(board(.builder, [phrase], 3)) }
            result.append(board(.recall, [pool[0]], 4))
            return result
        }
        if mode == .builder || mode == .recall {
            let selected = Array((mode == .builder ? phrases : pool).prefix(4))
            return selected.isEmpty ? [] : [board(mode, selected, 0)]
        }
        guard pool.count >= 4 else { return [] }
        let count = pool.count >= 8 ? 8 : 4
        return stride(from: 0, to: count, by: 4).map { offset in
            board(mode, Array(pool.dropFirst(offset).prefix(4)), offset / 4)
        }
    }

    static func round(from candidates: [ArcadeWord], mode: ArcadeMode) -> [ArcadeWord] {
        plan(from: candidates, mode: mode).flatMap(\.words)
    }

    static func options(for word: ArcadeWord, from candidates: [ArcadeWord], count: Int = 4) -> [ArcadeWord] {
        Array(unique([word] + candidates, limit: count).shuffled())
    }

    static func accepts(_ input: String, for word: ArcadeWord) -> Bool {
        let normalized = answerKey(input)
        return !normalized.isEmpty && ([word.target] + word.alternatives).contains { answerKey($0) == normalized }
    }

    /// Lenient spoken check (recogniser noise, Arabic short vowels): did the
    /// running transcript end in the target or one of its alternatives?
    static func heard(_ transcript: String, for word: ArcadeWord) -> Bool {
        let spoken = answerKey(transcript)
        return ([word.target] + word.alternatives).contains {
            SprintMatcher.matches(spokenTail: spoken, target: answerKey($0))
        }
    }

    private static func answerKey(_ text: String) -> String {
        // Pasted RTL text may carry presentation controls; these are not letters.
        let plain = String(text.unicodeScalars.filter { scalar in
            !([0x061C, 0x200E, 0x200F].contains(scalar.value)
              || (0x202A...0x202E).contains(scalar.value)
              || (0x2066...0x2069).contains(scalar.value))
        })
        return ClozeBuilder.compareKey(FuzzyMatcher.normalize(plain))
    }

    static func key(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
    }

    /// Exclude duplicated translations and known synonyms, so every board has
    /// one unambiguous match. Keep Arabic letter and morphology distinctions.
    static func unique(_ words: [ArcadeWord], limit: Int = 8) -> [ArcadeWord] {
        var meanings: Set<String> = [], targets: Set<String> = [], ids: Set<String> = []
        var result: [ArcadeWord] = []
        for word in words {
            let source = Set(word.source.components(separatedBy: CharacterSet(charactersIn: ";/,"))
                .map(key).filter { !$0.isEmpty })
            let answers = Set(([word.target] + word.alternatives).map(key).filter { !$0.isEmpty })
            guard !source.isEmpty, !key(word.target).isEmpty, !ids.contains(word.id),
                  meanings.isDisjoint(with: source), targets.isDisjoint(with: answers) else { continue }
            meanings.formUnion(source); targets.formUnion(answers); ids.insert(word.id)
            result.append(word)
            if result.count >= max(1, limit) { break }
        }
        return result
    }
}

struct ArcadeScore {
    private(set) var resolved: Set<String> = []
    private(set) var missed: Set<String> = []
    private(set) var streak = 0
    private(set) var bestStreak = 0
    private(set) var firstTry = 0

    mutating func answer(id: String, correct: Bool) {
        guard !resolved.contains(id) else { return }
        guard correct else { missed.insert(id); streak = 0; return }
        resolved.insert(id)
        if !missed.contains(id) {
            firstTry += 1; streak += 1; bestStreak = max(bestStreak, streak)
        } else { streak = 0 }
    }
}
