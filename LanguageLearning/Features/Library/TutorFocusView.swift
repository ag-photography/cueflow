import SwiftUI
import SwiftData

/// A short path from the current real-world lesson to the practice queue.
/// Tutor phrases are activated and prioritised for two weeks, while still
/// using the same FSRS schedule as every other phrase.
struct TutorFocusView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existingTopics: [Topic]
    @Query private var existingPhrases: [Phrase]
    @Query private var languages: [Language]
    @Query private var settings: [AppSettings]

    @State private var topicName = ""
    @State private var rawText = ""
    @State private var order: LineOrder = .deRu
    @State private var saveErrorMessage: String?

    private var targetLanguage: Language? {
        let code = settings.first?.activeLanguageCode ?? "ru"
        return languages.first { $0.code == code } ?? languages.first
    }

    private var targetLabel: String { targetLanguage?.germanLabel ?? "Zielsprache" }

    private var parsedLines: [ParsedLine] {
        rawText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { ParsedLine(index: $0.offset, raw: String($0.element), separator: "=", order: order) }
            .filter { !$0.raw.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var validLines: [ParsedLine] { parsedLines.filter(\.isValid) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("z. B. Jahreszeiten", text: $topicName)
                        .textInputAutocapitalization(.sentences)
                } header: {
                    Text("Thema aus deinem Unterricht")
                } footer: {
                    Text("CueFlow aktiviert dieses Thema und bevorzugt seine Ausdrücke 14 Tage lang.")
                }

                Section {
                    Picker("Reihenfolge", selection: $order) {
                        Text("Deutsch → \(targetLabel)").tag(LineOrder.deRu)
                        Text("\(targetLabel) → Deutsch").tag(LineOrder.ruDe)
                    }

                    ZStack(alignment: .topLeading) {
                        if rawText.isEmpty {
                            Text(exampleText)
                                .font(.body.monospaced())
                                .foregroundStyle(DS.textTertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $rawText)
                            .font(.body.monospaced())
                            .frame(minHeight: 170)
                            .scrollContentBackground(.hidden)
                    }
                } header: {
                    Text("Vokabeln einfügen")
                } footer: {
                    Text("Eine Vokabel oder Redewendung pro Zeile, getrennt mit =. Du kannst die Liste direkt aus den Notizen deines Tutors kopieren.")
                }

                if !parsedLines.isEmpty {
                    Section("Vorschau") {
                        Label(
                            "\(validLines.count) von \(parsedLines.count) Zeilen bereit",
                            systemImage: validLines.count == parsedLines.count ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(validLines.count == parsedLines.count ? DS.gradePerfect : DS.gradeHesitant)
                    }
                }

                Section {
                    Label("Erscheint zuerst in fokussierten Einheiten", systemImage: "scope")
                    Label("Bleibt Teil deines langfristigen Lernplans", systemImage: "calendar.badge.clock")
                } header: {
                    Text("So wirkt der Tutor-Fokus")
                }
            }
            .navigationTitle("Tutor-Fokus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fokus erstellen") { commit() }
                        .disabled(trimmedTopicName.isEmpty || validLines.isEmpty)
                        .accessibilityIdentifier("tutor-focus-save")
                }
            }
            .alert("Tutor-Fokus konnte nicht gespeichert werden", isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "Bitte versuche es erneut.")
            }
        }
    }

    private var trimmedTopicName: String {
        topicName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var exampleText: String {
        order == .deRu
            ? "Frühling = …\nSommer = …\nIm Herbst wird es kühler = …"
            : "… = Frühling\n… = Sommer\n… = Im Herbst wird es kühler"
    }

    private func commit() {
        guard let language = targetLanguage else { return }
        let topic = existingTopics.first {
            $0.language?.code == language.code
                && $0.name.compare(trimmedTopicName, options: .caseInsensitive) == .orderedSame
        } ?? Topic(name: trimmedTopicName, language: language, isActive: true)

        if topic.modelContext == nil { context.insert(topic) }
        topic.isActive = true

        var signatures = Set(existingPhrases.map {
            "\($0.language?.code ?? "")|\(Phrase.normalize($0.sourceText))|\(Phrase.normalize($0.targetText))"
        })
        let priorityEnd = Calendar.current.date(byAdding: .day, value: 14, to: .now)

        for line in validLines {
            guard let source = line.source, let target = line.target else { continue }
            let signature = "\(language.code)|\(Phrase.normalize(source))|\(Phrase.normalize(target))"

            if let existing = existingPhrases.first(where: {
                "\($0.language?.code ?? "")|\(Phrase.normalize($0.sourceText))|\(Phrase.normalize($0.targetText))" == signature
            }) {
                if !(existing.topics ?? []).contains(where: { $0 === topic }) {
                    existing.topics = (existing.topics ?? []) + [topic]
                }
                existing.isPriority = true
                existing.priorityUntil = priorityEnd
                continue
            }
            guard signatures.insert(signature).inserted else { continue }

            let phrase = Phrase(sourceText: source, targetText: target, language: language, topics: [topic])
            phrase.contentSource = .tutorImport
            phrase.qualityStatus = .unreviewed
            phrase.isPriority = true
            phrase.priorityUntil = priorityEnd
            context.insert(phrase)
            context.insert(StudyCard(phrase: phrase))
        }

        do {
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            saveErrorMessage = error.localizedDescription
        }
    }
}
