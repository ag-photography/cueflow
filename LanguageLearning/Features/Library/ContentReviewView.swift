import SwiftData
import SwiftUI

struct ContentReviewView: View {
    @Environment(\.modelContext) private var context
    @Query private var phrases: [Phrase]
    @Query private var settings: [AppSettings]
    @State private var selectedPhrase: Phrase?
    @State private var saveError: String?

    private var queue: [Phrase] {
        let code = settings.first?.activeLanguageCode ?? "ru"
        return phrases
            .filter { $0.language?.code == code && $0.qualityStatus == .unreviewed }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List {
            Section {
                Text("Prüfe Zieltext, Register, Dialekt und zulässige Varianten. Der Status beschreibt die tatsächliche Prüfung — nicht den Lernfortschritt.")
                    .font(.subheadline)
                    .foregroundStyle(DS.textSecondary)
            }
            Section("Offen · \(queue.count)") {
                if queue.isEmpty {
                    ContentUnavailableView(
                        "Alles geprüft",
                        systemImage: "checkmark.seal",
                        description: Text("Neue manuelle und Tutor-Importe erscheinen automatisch hier.")
                    )
                }
                ForEach(queue) { phrase in
                    Button { selectedPhrase = phrase } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(phrase.sourceText).foregroundStyle(DS.textPrimary)
                            Text(phrase.targetText)
                                .font(.subheadline)
                                .foregroundStyle(DS.textSecondary)
                            Label(sourceLabel(phrase.contentSource), systemImage: "tray.and.arrow.down")
                                .font(.caption2)
                                .foregroundStyle(DS.textTertiary)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button { mark(phrase, as: .editorial) } label: {
                            Label("Redaktionell", systemImage: "checkmark")
                        }
                        .tint(DS.accent)
                        Button { mark(phrase, as: .nativeVerified) } label: {
                            Label("Native", systemImage: "checkmark.seal.fill")
                        }
                        .tint(DS.gradePerfect)
                    }
                }
            }
        }
        .navigationTitle("Inhalte prüfen")
        .sheet(item: $selectedPhrase) { PhraseEditorView(phrase: $0) }
        .alert("Status konnte nicht gespeichert werden", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(saveError ?? "Bitte versuche es erneut.") }
    }

    private func mark(_ phrase: Phrase, as status: PhraseQualityStatus) {
        phrase.qualityStatus = status
        do { try context.save() }
        catch {
            context.rollback()
            saveError = error.localizedDescription
        }
    }

    private func sourceLabel(_ source: PhraseContentSource) -> String {
        switch source {
        case .bundled: return "Mitgeliefert"
        case .manual: return "Manuell hinzugefügt"
        case .tutorImport: return "Tutor-Import"
        }
    }
}
