import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [AppSettings]

    @State private var dailyNewLimit: Int = 10
    @State private var transliterationVisible: TransliterationMode = .auto
    @State private var useAIGradingAssist: Bool = false
    @State private var starterPackResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $dailyNewLimit, in: 0...50) {
                        HStack {
                            Text("Neue Karten pro Tag")
                            Spacer()
                            Text("\(dailyNewLimit)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Begrenzt, wie viele neue Karten pro Tag eingeführt werden. Wiederholungen sind unbegrenzt.")
                }

                Section("Transliteration") {
                    Picker("Anzeigen", selection: $transliterationVisible) {
                        ForEach(TransliterationMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                }

                Section {
                    Toggle("KI-Bewertungshilfe", isOn: $useAIGradingAssist)
                } footer: {
                    Text("Nutzt Apples On-Device-Sprachmodell, um Tier-2-Bewertungen zu verfeinern (iOS 26+, nur auf Apple-Intelligence-fähigen Geräten).")
                }

                Section {
                    Button {
                        let result = SeedData.addStarterPack(context)
                        starterPackResult = "Hinzugefügt: \(result.phrasesAdded) Karten, \(result.topicsAdded) neue Themen."
                    } label: {
                        Label("Starter-Vokabular laden (A1)", systemImage: "tray.and.arrow.down")
                    }
                } header: {
                    Text("Inhalte")
                } footer: {
                    Text("Ca. 250 kuratierte A1-Sätze in 23 Themen (Begrüßung, Familie, Verben, Adjektive, …). Doppelte Einträge werden übersprungen.")
                }

                Section {
                    vocabLoadButton(level: "A2", count: 230)
                    vocabLoadButton(level: "B1", count: 492)
                    vocabLoadButton(level: "B2", count: 986)
                } header: {
                    Text("Wortlisten (OpenRussian.org)")
                } footer: {
                    Text("Häufigste russische Wörter mit deutschen Übersetzungen, sortiert nach Schwierigkeit. Jede Stufe wird als eigenes Thema eingefügt und ist standardmäßig inaktiv – aktiviere sie in der Bibliothek, wenn du soweit bist. Daten: openrussian.org (CC BY-SA 4.0).")
                }

                Section("Entwickler") {
                    NavigationLink {
                        TelemetryView()
                    } label: {
                        Label("Diagnose", systemImage: "chart.bar.doc.horizontal")
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { save(); dismiss() }
                }
            }
            .onAppear { hydrate() }
            .alert(
                "Starter-Vokabular",
                isPresented: Binding(
                    get: { starterPackResult != nil },
                    set: { if !$0 { starterPackResult = nil } }
                )
            ) {
                Button("OK") { starterPackResult = nil }
            } message: {
                Text(starterPackResult ?? "")
            }
        }
    }

    private func hydrate() {
        let row = settings.first
        dailyNewLimit = row?.dailyNewLimit ?? 10
        transliterationVisible = TransliterationMode.from(row?.transliterationVisible)
        useAIGradingAssist = row?.useAIGradingAssist ?? false
    }

    private func vocabLoadButton(level: String, count: Int) -> some View {
        Button {
            let result = SeedData.addVocabLevel(context, level: level)
            starterPackResult = "Wortliste \(level): \(result.phrasesAdded) Karten hinzugefügt (von \(result.total))."
        } label: {
            HStack {
                Label("Wortliste \(level) laden", systemImage: "books.vertical")
                Spacer()
                Text("\(count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func save() {
        let row = settings.first ?? {
            let s = AppSettings()
            context.insert(s)
            return s
        }()
        row.dailyNewLimit = dailyNewLimit
        row.transliterationVisible = transliterationVisible.persisted
        row.useAIGradingAssist = useAIGradingAssist
        try? context.save()
    }
}

private enum TransliterationMode: CaseIterable {
    case auto, on, off

    var label: String {
        switch self {
        case .auto: return "Automatisch"
        case .on: return "Immer"
        case .off: return "Nie"
        }
    }

    var persisted: Bool? {
        switch self {
        case .auto: return nil
        case .on: return true
        case .off: return false
        }
    }

    static func from(_ value: Bool?) -> TransliterationMode {
        switch value {
        case .none: return .auto
        case .some(true): return .on
        case .some(false): return .off
        }
    }
}
