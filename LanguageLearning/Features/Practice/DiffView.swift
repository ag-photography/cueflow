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
        VStack(alignment: .leading, spacing: DS.space.md) {
            row(label: "Erwartet", text: render(diff.expected, isExpected: true))
            row(label: "Du", text: render(diff.actual, isExpected: false))
        }
    }

    private func row(label: String, text: Text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DS.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)
            text
                .font(.system(.title3, design: .rounded))
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
                .foregroundStyle(isExpected ? DS.gradePerfect : DS.textPrimary)
        case .mismatch(let ch):
            return Text(String(ch))
                .foregroundStyle(DS.gradeWrong)
                .underline(true, color: DS.gradeWrong)
        case .missing(let ch):
            return isExpected
                ? Text(String(ch)).foregroundStyle(DS.gradeMinor).underline(true, color: DS.gradeMinor)
                : Text("")
        case .extra(let ch):
            return isExpected
                ? Text("")
                : Text(String(ch)).foregroundStyle(DS.gradeWrong).strikethrough(true, color: DS.gradeWrong)
        }
    }
}
