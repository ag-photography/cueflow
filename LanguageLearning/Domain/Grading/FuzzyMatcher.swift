import Foundation

enum FuzzyMatcher {
    /// NFC-normalise, lowercase, trim, collapse internal whitespace, strip a
    /// short list of punctuation that's noise for grading purposes.
    static func normalize(_ s: String) -> String {
        let stripped = s.precomposedStringWithCanonicalMapping
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPunct = stripped.unicodeScalars
            .filter { !punctuationToStrip.contains($0) }
            .reduce(into: "") { $0.append(Character($1)) }
        return collapseWhitespace(withoutPunct)
    }

    /// Standard Levenshtein distance over Character.
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let s = Array(a)
        let t = Array(b)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }

        var prev = Array(0...t.count)
        var curr = Array(repeating: 0, count: t.count + 1)

        for i in 1...s.count {
            curr[0] = i
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                curr[j] = Swift.min(
                    prev[j] + 1,
                    curr[j - 1] + 1,
                    prev[j - 1] + cost
                )
            }
            swap(&prev, &curr)
        }
        return prev[t.count]
    }

    /// Compares the answer to the expected, word-by-word when the word counts
    /// match. Returns the number of words with any difference and the total
    /// character edits across those words. When word counts differ, returns
    /// the higher word count and overall string-level edit distance.
    static func wordEditAnalysis(
        expected: String,
        actual: String
    ) -> (editedWords: Int, totalEdits: Int) {
        let expectedWords = expected.split(separator: " ").map(String.init)
        let actualWords = actual.split(separator: " ").map(String.init)

        if expectedWords.count != actualWords.count {
            return (
                editedWords: Swift.max(expectedWords.count, actualWords.count),
                totalEdits: levenshtein(expected, actual)
            )
        }

        var editedWords = 0
        var totalEdits = 0
        for (expectedWord, actualWord) in zip(expectedWords, actualWords) where expectedWord != actualWord {
            editedWords += 1
            totalEdits += levenshtein(expectedWord, actualWord)
        }
        return (editedWords, totalEdits)
    }

    enum DiffOp {
        case match(Character)
        case mismatch(Character)   // wrong char in actual / missed char in expected
        case extra(Character)      // present in actual, not expected
        case missing(Character)    // present in expected, not actual
    }

    /// Aligned character-level diff. Returns the diff from the perspective of
    /// `expected` (what the answer should be) and `actual` (what the user typed).
    /// Both sequences read left-to-right and are useful for stacked-display.
    static func characterDiff(
        expected: String,
        actual: String
    ) -> (expected: [DiffOp], actual: [DiffOp]) {
        let s = Array(expected)
        let t = Array(actual)
        let n = s.count
        let m = t.count

        // dp[i][j] = edit distance between s[0..<i] and t[0..<j]
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = i }
        for j in 0...m { dp[0][j] = j }
        for i in 1...max(n, 1) where i <= n {
            for j in 1...max(m, 1) where j <= m {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                dp[i][j] = Swift.min(
                    dp[i - 1][j] + 1,        // delete from s (missing in actual)
                    dp[i][j - 1] + 1,        // insert into s (extra in actual)
                    dp[i - 1][j - 1] + cost  // match or substitute
                )
            }
        }

        var expectedOps: [DiffOp] = []
        var actualOps: [DiffOp] = []
        var i = n
        var j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0, s[i - 1] == t[j - 1] {
                expectedOps.append(.match(s[i - 1]))
                actualOps.append(.match(t[j - 1]))
                i -= 1; j -= 1
            } else if i > 0, j > 0, dp[i][j] == dp[i - 1][j - 1] + 1 {
                expectedOps.append(.mismatch(s[i - 1]))
                actualOps.append(.mismatch(t[j - 1]))
                i -= 1; j -= 1
            } else if i > 0, dp[i][j] == dp[i - 1][j] + 1 {
                expectedOps.append(.missing(s[i - 1]))
                i -= 1
            } else {
                actualOps.append(.extra(t[j - 1]))
                j -= 1
            }
        }
        return (expectedOps.reversed(), actualOps.reversed())
    }

    private static let punctuationToStrip: Set<Unicode.Scalar> = {
        // ASCII punctuation + German guillemets + curly/typographic quotes.
        let chars = ".,!?;:\"'()[]{}\u{00AB}\u{00BB}\u{201E}\u{201C}\u{201D}\u{2018}\u{2019}"
        return Set(chars.unicodeScalars)
    }()

    private static func collapseWhitespace(_ s: String) -> String {
        var result = ""
        var lastWasSpace = false
        for ch in s {
            if ch.isWhitespace {
                if !lastWasSpace, !result.isEmpty { result.append(" ") }
                lastWasSpace = true
            } else {
                result.append(ch)
                lastWasSpace = false
            }
        }
        if result.last == " " { result.removeLast() }
        return result
    }
}
