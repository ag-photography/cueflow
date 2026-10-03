import SwiftUI
import SwiftData

struct LearningPreferencesView: View {
    @Environment(\.modelContext) private var context
    @Query private var settings: [AppSettings]
    @State private var preference = LearningPreferences()
    @State private var hydrated = false
    @State private var error: String?
    @State private var confirmDelete = false
    private var language: String { settings.first?.activeLanguageCode ?? "ru" }
    private var experience: LearningExperience? { try? settings.first?.readExperience() }

    var body: some View {
        Form {
            Section("Dein Alltag") {
                Picker("Wofür lernst du?", selection: $preference.purpose) {
                    ForEach(["Reisen", "Menschen", "Beruf"], id: \.self) { Text($0).tag($0) }
                }
                Toggle("Leise starten", isOn: $preference.quiet)
                Stepper("\(preference.weeklyDays) Lerntage pro Woche", value: $preference.weeklyDays, in: 1...7)
            }
            Section {
                Text("Dein Ziel beeinflusst die Geschichten auf Heute. Aktive Unterrichtsthemen werden bevorzugt. Du kannst jederzeit eine andere Geschichte wählen. Eine Pause kostet keine Punkte.")
            }
            if let data = experience {
                Section("Diese Woche") {
                    LabeledContent("Tage mit abgeschlossener Geschichte", value: "\(data.learningDays(language: language))")
                    LabeledContent("Geschichten ausprobiert", value: "\(data.completed(in: language).count)")
                }
                Section {
                    ShareLink("Anonyme Zusammenfassung teilen", item: aggregate(data))
                    Button("Lokale Nutzungsereignisse löschen", role: .destructive) { confirmDelete = true }
                } header: { Text("Lernqualität prüfen") } footer: {
                    Text("Kein Tracking-Server: Ereignisse enthalten nur Schritt-IDs und Zeitpunkte, keine Antworten oder Sprachaufnahmen. Rohereignisse werden nach 90 Tagen bei der nächsten Speicherung entfernt. Dein Lernstand und deine Einstellungen bleiben beim Löschen erhalten.")
                }
            }
            if let error { Section { Text(error).foregroundStyle(DS.gradeWrong) } }
        }
        .disabled(!hydrated && error == nil)
        .navigationTitle("Mein Lernrhythmus")
        .task {
            do { preference = try settings.first?.readExperience().preference(for: language) ?? .init(); hydrated = true }
            catch { self.error = error.localizedDescription }
        }
        .onChange(of: preference) { _, _ in if hydrated { save() } }
        .confirmationDialog("Nutzungsereignisse löschen? Dein Lernstand bleibt erhalten.", isPresented: $confirmDelete) {
            Button("Ereignisse löschen", role: .destructive) { save(clearEvents: true) }
        }
    }
    private func save(clearEvents: Bool = false) {
        do {
            guard let row = settings.first else { return }
            var data = try row.readExperience()
            data.preferences[language] = preference
            if clearEvents { data.events = [] }
            try row.writeExperience(data)
            try context.save()
            error = nil
        } catch { context.rollback(); self.error = error.localizedDescription }
    }
    private func aggregate(_ data: LearningExperience) -> String {
        let runs = data.runs.filter { $0.language == language }
        let completed = runs.filter { $0.completedAt != nil }
        let attempts = runs.flatMap(\.attempts)
        return "CueFlow pilot summary\nLanguage: \(language)\nStarted: \(runs.count)\nCompleted: \(completed.count)\nIndependent first answers: \(attempts.filter { $0.correct && !$0.supported }.count)/\(attempts.count)\nDelayed checks completed: \(completed.filter(\.isDelayedCheck).count)\nWeekly learning days: \(data.learningDays(language: language))\nNo free-conversation proficiency claim."
    }
}
