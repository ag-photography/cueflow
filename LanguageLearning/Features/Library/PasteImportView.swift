import SwiftUI
import SwiftData

/// Paste-import: one phrase per line, separator `=`, optional ` | Topic` suffix.
/// Live-parsed preview lets the user fix lines before commit. New topics are
/// created on the fly and tagged onto the inserted phrases.
struct PasteImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existingTopics: [Topic]
    @Query private var languages: [Language]
    @Query private var settings: [AppSettings]

    @State private var rawText: String
    @State private var separator: String = "="
    @State private var order: LineOrder

    /// Imported phrases are filed under the active target language.
    private var targetLanguage: Language? {
        let code = settings.first?.activeLanguageCode ?? "ru"
        return languages.first { $0.code == code } ?? languages.first
    }
    private var targetLabel: String { targetLanguage?.germanLabel ?? "Zielsprache" }
    private var targetCode: String { (targetLanguage?.code ?? "ru").uppercased() }

    private func orderLabel(_ ord: LineOrder) -> String {
        switch ord {
        case .deRu: return "Deutsch → \(targetLabel)"
        case .ruDe: return "\(targetLabel) → Deutsch"
        }
    }

    init(initialText: String = "", initialOrder: LineOrder = .deRu) {
        self._rawText = State(initialValue: initialText)
        self._order = State(initialValue: initialOrder)
    }

    private var parsedLines: [ParsedLine] {
        rawText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map {
                ParsedLine(
                    index: $0.offset,
                    raw: String($0.element),
                    separator: separator,
                    order: order
                )
            }
            .filter { !$0.raw.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var validLines: [ParsedLine] { parsedLines.filter { $0.isValid } }

    private var formatHintText: String {
        let leftLabel = order == .deRu ? "Deutsch" : targetLabel
        let rightLabel = order == .deRu ? targetLabel : "Deutsch"
        return "Pro Zeile: \(leftLabel) \(separator) \(rightLabel) | Themenname (optional)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reihenfolge", selection: $order) {
                        ForEach(LineOrder.allCases) { ord in
                            Text(orderLabel(ord)).tag(ord)
                        }
                    }
                    Picker("Trennzeichen", selection: $separator) {
                        Text("=").tag("=")
                        Text("→").tag("→")
                        Text("Tab").tag("\t")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Format")
                } footer: {
                    Text(formatHintText)
                }

                Section("Einfügen") {
                    TextEditor(text: $rawText)
                        .font(.body.monospaced())
                        .frame(minHeight: 160)
                }

                if !parsedLines.isEmpty {
                    Section("Vorschau (\(validLines.count) gültig / \(parsedLines.count))") {
                        ForEach(parsedLines) { line in
                            previewRow(line: line)
                        }
                    }
                }
            }
            .navigationTitle("Importieren")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { commit() }
                        .disabled(validLines.isEmpty)
                }
            }
        }
    }

    private func previewRow(line: ParsedLine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if line.isValid {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("DE")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    Text(line.source ?? "")
                        .font(.subheadline.weight(.medium))
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(targetCode)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    Text(line.target ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let topic = line.topic {
                    Text(topic)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            } else {
                Text(line.raw)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                Text("Trennzeichen fehlt: \(separator)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func commit() {
        guard let language = targetLanguage else { return }
        var topicCache: [String: Topic] = Dictionary(uniqueKeysWithValues: existingTopics.map { ($0.name, $0) })

        for line in validLines {
            let phrase = Phrase(
                sourceText: line.source!,
                targetText: line.target!,
                language: language,
                topics: []
            )
            if let topicName = line.topic {
                let topic: Topic
                if let existing = topicCache[topicName] {
                    topic = existing
                } else {
                    topic = Topic(name: topicName, language: language, isActive: false)
                    context.insert(topic)
                    topicCache[topicName] = topic
                }
                phrase.topics = [topic]
            }
            context.insert(phrase)
            context.insert(StudyCard(phrase: phrase))
        }

        try? context.save()
        dismiss()
    }
}

enum LineOrder: String, CaseIterable, Identifiable {
    case deRu   // German first, target language second
    case ruDe   // target language first, German second
    var id: String { rawValue }
}

private struct ParsedLine: Identifiable {
    let id: Int
    let raw: String
    /// Always German — regardless of the side the user typed it on.
    let source: String?
    /// Always the target language (the one being learned).
    let target: String?
    let topic: String?

    var isValid: Bool { source != nil && target != nil }

    init(index: Int, raw: String, separator: String, order: LineOrder) {
        self.id = index
        self.raw = raw
        let parts = raw.components(separatedBy: separator)
        guard parts.count >= 2 else {
            self.source = nil
            self.target = nil
            self.topic = nil
            return
        }
        let lhs = parts[0].trimmingCharacters(in: .whitespaces)
        let rhsRaw = parts.dropFirst().joined(separator: separator)
        let rhsParts = rhsRaw.components(separatedBy: "|")
        let rhs = rhsParts[0].trimmingCharacters(in: .whitespaces)
        let topic = rhsParts.count > 1
            ? rhsParts[1].trimmingCharacters(in: .whitespaces)
            : nil

        // Canonicalise: regardless of typed order, store German in `source`
        // and the target language in `target`. The Phrase model is direction-
        // agnostic at storage, but the practice loop expects sourceText = prompt.
        let german: String
        let target: String
        switch order {
        case .deRu:
            german = lhs
            target = rhs
        case .ruDe:
            german = rhs
            target = lhs
        }
        self.source = german.isEmpty ? nil : german
        self.target = target.isEmpty ? nil : target
        self.topic = (topic?.isEmpty ?? true) ? nil : topic
    }
}
