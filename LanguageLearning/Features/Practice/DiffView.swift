import SwiftUI

/// Character-level diff. Expected row shows what the answer should be, with
/// any chars the user missed underlined. Actual row shows the user's answer,
/// with any wrong/extra chars in red. Insertions in either are highlighted so
/// the user can see exactly which character carries the morphology error.
struct DiffView: View {
    let expected: String
    let actual: String

    private var diff: (expected: [FuzzyMatcher.DiffOp], actual: [FuzzyMatcher.DiffOp]) {
        FuzzyMatcher.characterDiff(expected: expected, actual: actual)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            row(label: "Erwartet", text: render(diff.expected, isExpected: true))
            row(label: "Du", text: render(diff.actual, isExpected: false))
        }
    }

    private func row(label: String, text: Text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            text
                .font(.title3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func render(_ ops: [FuzzyMatcher.DiffOp], isExpected: Bool) -> Text {
        ops.reduce(Text("")) { acc, op in
            acc + segment(for: op, isExpected: isExpected)
        }
    }

    private func segment(for op: FuzzyMatcher.DiffOp, isExpected: Bool) -> Text {
        switch op {
        case .match(let ch):
            return Text(String(ch))
                .foregroundStyle(isExpected ? Color.green : Color.primary)
        case .mismatch(let ch):
            return Text(String(ch))
                .foregroundStyle(.red)
                .underline(true, color: .red)
        case .missing(let ch):
            // Only render in the expected row — the actual row didn't have it.
            return isExpected
                ? Text(String(ch)).foregroundStyle(.orange).underline(true, color: .orange)
                : Text("")
        case .extra(let ch):
            // Only render in the actual row — the expected didn't have it.
            return isExpected
                ? Text("")
                : Text(String(ch)).foregroundStyle(.red).strikethrough(true, color: .red)
        }
    }
}
