import SwiftUI
import SwiftData

/// Edit (or create) a phrase, including its topic membership, transliteration,
/// notes, and the accepted-alternatives list that grading uses for Tier 1
/// matching.
struct PhraseEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allTopics: [Topic]
    @Query private var languages: [Language]
    @Query private var settings: [AppSettings]

    let phrase: Phrase?

    /// The phrase's own language when editing; the active language when creating.
    /// Drives the target-field label and the language a new phrase is filed under.
    private var targetLanguage: Language? {
        if let phrase, let lang = phrase.language { return lang }
        let code = settings.first?.activeLanguageCode ?? "ru"
        return languages.first { $0.code == code } ?? languages.first
    }

    @State private var sourceText: String = ""
    @State private var targetText: String = ""
    @State private var transliteration: String = ""
    @State private var notes: String = ""
    @State private var selectedTopicIDs: Set<PersistentIdentifier> = []
    @State private var alternatives: [String] = []
    @State private var newAlternative: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Deutsch") {
                    TextField("Quelltext", text: $sourceText, axis: .vertical)
                }
                Section(targetLanguage?.germanLabel ?? "Zielsprache") {
                    TextField("Zieltext", text: $targetText, axis: .vertical)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(targetLanguage?.isRTL == true ? .trailing : .leading)
                }
                Section("Transliteration") {
                    TextField("Optional", text: $transliteration)
                        .autocorrectionDisabled()
                }
                Section("Notizen") {
                    TextField("Optional", text: $notes, axis: .vertical)
                }
                Section("Themen") {
                    if allTopics.isEmpty {
                        Text("Keine Themen — füge eines hinzu.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(allTopics) { topic in
                            Button {
                                toggleTopic(topic)
                            } label: {
                                HStack {
                                    Text(topic.name)
                                        .foregroundStyle(Color.primary)
                                    Spacer()
                                    if selectedTopicIDs.contains(topic.persistentModelID) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                }
                Section {
                    ForEach(alternatives, id: \.self) { alt in
                        HStack {
                            Text(alt)
                            Spacer()
                            Button(role: .destructive) {
                                alternatives.removeAll { $0 == alt }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        TextField("Akzeptierte Alternative", text: $newAlternative)
                            .autocorrectionDisabled()
                        Button("Hinzufügen") {
                            let trimmed = newAlternative.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty, !alternatives.contains(trimmed) {
                                alternatives.append(trimmed)
                            }
                            newAlternative = ""
                        }
                        .disabled(newAlternative.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Akzeptierte Alternativen")
                } footer: {
                    Text("Antworten, die als richtig gewertet werden — nützlich bei Synonymen oder zulässigen Varianten.")
                }
            }
            .navigationTitle(phrase == nil ? "Neue Phrase" : "Phrase bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(sourceText.trimmingCharacters(in: .whitespaces).isEmpty
                                  || targetText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { hydrate() }
        }
    }

    private func toggleTopic(_ topic: Topic) {
        if selectedTopicIDs.contains(topic.persistentModelID) {
            selectedTopicIDs.remove(topic.persistentModelID)
        } else {
            selectedTopicIDs.insert(topic.persistentModelID)
        }
    }

    private func hydrate() {
        guard let phrase else { return }
        sourceText = phrase.sourceText
        targetText = phrase.targetText
        transliteration = phrase.transliteration ?? ""
        notes = phrase.notes ?? ""
        selectedTopicIDs = Set(phrase.topics.map { $0.persistentModelID })
        alternatives = phrase.acceptedAlternatives
    }

    private func save() {
        let topics = allTopics.filter { selectedTopicIDs.contains($0.persistentModelID) }
        if let phrase {
            phrase.sourceText = sourceText
            phrase.targetText = targetText
            phrase.targetTextNormalized = Phrase.normalize(targetText)
            phrase.transliteration = transliteration.isEmpty ? nil : transliteration
            phrase.notes = notes.isEmpty ? nil : notes
            phrase.topics = topics
            phrase.acceptedAlternatives = alternatives
        } else {
            let language = targetLanguage
            let phrase = Phrase(
                sourceText: sourceText,
                targetText: targetText,
                language: language,
                topics: topics,
                transliteration: transliteration.isEmpty ? nil : transliteration,
                notes: notes.isEmpty ? nil : notes
            )
            phrase.acceptedAlternatives = alternatives
            context.insert(phrase)
            context.insert(StudyCard(phrase: phrase))
        }
        try? context.save()
        dismiss()
    }
}
