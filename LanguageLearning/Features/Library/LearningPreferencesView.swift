import SwiftUI
import SwiftData

struct LearningPreferencesView: View {
    @Environment(\.modelContext) private var context
    @Query private var settings: [AppSettings]
    @Query private var reviews: [Review]
    @State private var preference = LearningPreferences()
    @State private var hydrated = false
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var calibrationEpisode: LearningEpisode?
    private var language: String { settings.first?.activeLanguageCode ?? "ru" }
    private var experience: LearningExperience? { try? settings.first?.readExperience() }

    var body: some View {
        Form {
            Section("Dein Alltag") {
                Picker("Wofür lernst du?", selection: $preference.purpose) {
                    ForEach(["Reisen", "Menschen", "Beruf"], id: \.self) { Text($0).tag($0) }
                }
                Toggle("Leise starten", isOn: $preference.quiet)
                Text("\(preference.effectiveStudyWeekdays.count) Lerntage pro Woche")
                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                    Toggle(Calendar.current.weekdaySymbols[day - 1], isOn: Binding(get: {
                        preference.effectiveStudyWeekdays.contains(day)
                    }, set: { selected in
                        var days = Set(preference.effectiveStudyWeekdays)
                        if selected { days.insert(day) } else { days.remove(day) }
                        preference.studyWeekdays = days.sorted()
                        preference.weeklyDays = max(1, days.count)
                    }))
                }
                Text("Die gewählten Wochentage bestimmen die verbleibenden Übungsgelegenheiten vor deinem Unterricht. Das Tageslimit bleibt unverändert.")
                    .font(.footnote).foregroundStyle(DS.textSecondary)
            }
            Section {
                Text("Dein Ziel beeinflusst die Situationen auf Heute. Aktive Unterrichtsthemen werden bevorzugt. Du kannst jederzeit eine andere Situation wählen. Eine Pause kostet keine Punkte.")
            }
            Section("Freiwilliger Startcheck") {
                Text("Drei Antworten ohne Vorlage helfen dir einzuschätzen, ob du zuerst mit Beispielen üben möchtest. Das ist keine Prüfung und kein Nachweis für langfristiges Können.")
                    .font(.footnote)
                if let correct = preference.calibrationCorrect {
                    Text("Letzter Check: \(correct) von 3 ohne Hilfe getroffen.")
                    Text(correct >= 2 ? "Du kannst direkt kurze Abrufrunden probieren." : "Starte gern mit den Beispielen einer Situation.")
                }
                Button(preference.calibrationAt == nil ? "Startcheck ausprobieren" : "Startcheck wiederholen") {
                    calibrationEpisode = EpisodeLibrary.recommendation(language: language, purpose: preference.purpose, focusNames: [], completed: [])
                }
            }
            if let data = experience {
                Section("Freiwilliger lokaler Lerntest") {
                    Text("Vergleiche über mehrere Wochen eine Situation zuerst mit einer Kartenrunde zuerst. Die Variante wird einmal zufällig gewählt; keine Daten werden automatisch geteilt. Alle Varianten behalten dieselben Korrekturen und Lernregeln.")
                        .font(.footnote)
                    if let trial = data.trial {
                        Text("Variante: \(trial.variant == "stories-first" ? "Situation zuerst" : "Karten zuerst") · seit \(trial.startedAt.formatted(date: .abbreviated, time: .omitted))")
                        if trial.endedAt == nil { Button("Lerntest beenden") { setTrial(active: false) } }
                        else { Text("Beendet · bisherige Ergebnisse bleiben erhalten.").font(.caption) }
                    } else { Button("Freiwillig teilnehmen") { setTrial(active: true) } }
                }
                Section("Diese Woche") {
                    LabeledContent("Tage mit Lernaktivität", value: "\(data.learningDays(language: language))")
                    LabeledContent("Situationen geübt", value: "\(data.completed(in: language).count)")
                }
                Section {
                    ShareLink("Anonyme Zusammenfassung teilen", item: LearningAnalysis(experience: data, language: language).report
                        + "\nCohort: \(data.trial?.variant ?? "not enrolled"); policy: \(data.trial?.policyVersion ?? 0)"
                        + "\n" + ExposureMatchedAnalysis.report(reviews: reviews.filter { $0.card?.phrase?.language?.code == language }, since: data.trial?.startedAt, until: data.trial?.endedAt)
                        + "\n" + ComparableSubmissionTiming.report(reviews: reviews.filter { $0.card?.phrase?.language?.code == language }))
                    Button("Lokale Nutzungsereignisse löschen", role: .destructive) { confirmDelete = true }
                } header: { Text("Lernqualität prüfen") } footer: {
                    Text("Kein Tracking-Server: Ereignisse enthalten nur Schritt-IDs und Zeitpunkte, keine Antworten oder Sprachaufnahmen. Rohereignisse werden nach 90 Tagen bei der nächsten Speicherung entfernt. Dein Lernstand und deine Einstellungen bleiben beim Löschen erhalten.")
                }
            }
            if let error { Section { Text(error).foregroundStyle(DS.gradeWrong) } }
        }
        .disabled(!hydrated && error == nil)
        .navigationTitle("Mein Lernrhythmus")
        .sheet(item: $calibrationEpisode, onDismiss: {
            if let updated = try? settings.first?.readExperience().preference(for: language) { preference = updated }
        }) { EpisodeView(episode: $0, calibration: true) }
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
            if clearEvents { data.events = []; data.eventResetAt = .now }
            try row.writeExperience(data)
            try context.save()
            Task { await NotificationService.shared.refreshLearningReminder(settings: row, experience: data) }
            error = nil
        } catch { context.rollback(); self.error = error.localizedDescription }
    }
    private func setTrial(active: Bool) {
        do {
            guard let row = settings.first else { return }
            var data = try row.readExperience()
            if active && data.trial == nil { data.trial = .init(variant: Bool.random() ? "stories-first" : "cards-first") }
            else if !active { data.trial?.endedAt = .now }
            try row.writeExperience(data)
            try context.save()
        } catch { context.rollback(); self.error = error.localizedDescription }
    }
    private func aggregate(_ data: LearningExperience) -> String {
        let runs = data.runs.filter { $0.language == language }
        let completed = runs.filter { $0.completedAt != nil }
        let attempts = runs.flatMap(\.attempts)
        return "CueFlow pilot summary\nLanguage: \(language)\nStarted: \(runs.count)\nCompleted: \(completed.count)\nIndependent first answers: \(attempts.filter { $0.correct && !$0.supported }.count)/\(attempts.count)\nDelayed checks completed: \(completed.filter(\.isDelayedCheck).count)\nWeekly learning days: \(data.learningDays(language: language))\nNo free-conversation proficiency claim."
    }
}
