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

    @State private var rawText: String = ""
    @State private var separator: String = "="

    private var parsedLines: [ParsedLine] {
        rawText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { ParsedLine(index: $0.offset, raw: String($0.element), separator: separator) }
            .filter { !$0.raw.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var validLines: [ParsedLine] { parsedLines.filter { $0.isValid } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Trennzeichen", selection: $separator) {
                        Text("=").tag("=")
                        Text("→").tag("→")
                        Text("Tab").tag("\t")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Format")
                } footer: {
                    Text("Pro Zeile: Deutsch \(separator) Russisch | Themenname (optional)")
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
                Text(line.source ?? "")
                    .font(.subheadline.weight(.medium))
                Text(line.target ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
        guard let language = languages.first(where: { $0.code == "ru" }) ?? languages.first else { return }
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
            for direction in CardDirection.allCases {
                context.insert(StudyCard(phrase: phrase, direction: direction))
            }
        }

        try? context.save()
        dismiss()
    }
}

private struct ParsedLine: Identifiable {
    let id: Int
    let raw: String
    let source: String?
    let target: String?
    let topic: String?

    var isValid: Bool { source != nil && target != nil }

    init(index: Int, raw: String, separator: String) {
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
        self.source = lhs.isEmpty ? nil : lhs
        self.target = rhs.isEmpty ? nil : rhs
        self.topic = (topic?.isEmpty ?? true) ? nil : topic
    }
}
