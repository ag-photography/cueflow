import SwiftUI
import SwiftData

/// Edit (or create) a topic. Active topics drive the new-card source in the
/// scheduler — reviews come from all topics regardless.
struct TopicEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var languages: [Language]
    @Query private var settings: [AppSettings]

    let topic: Topic?

    /// New topics are filed under the active target language (not hardcoded ru).
    private var activeLanguage: Language? {
        let code = settings.first?.activeLanguageCode ?? "ru"
        return languages.first { $0.code == code } ?? languages.first
    }

    @State private var name: String = ""
    @State private var isActive: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("z.B. Genitiv mit Verneinung", text: $name)
                }
                Section {
                    Toggle("Aktiv", isOn: $isActive)
                } footer: {
                    Text("Aktive Themen liefern neue Karten. Wiederholungen kommen aus allen Themen.")
                }
            }
            .navigationTitle(topic == nil ? "Neues Thema" : "Thema bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { hydrate() }
        }
    }

    private func hydrate() {
        guard let topic else { return }
        name = topic.name
        isActive = topic.isActive
    }

    private func save() {
        if let topic {
            topic.name = name
            topic.isActive = isActive
        } else {
            let topic = Topic(name: name, language: activeLanguage, isActive: isActive)
            context.insert(topic)
        }
        try? context.save()
        dismiss()
    }
}
