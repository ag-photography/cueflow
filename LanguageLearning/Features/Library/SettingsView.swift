import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [AppSettings]
    @Query private var topics: [Topic]
    @Query private var phrases: [Phrase]

    @Query(sort: \Language.code) private var languages: [Language]

    @State private var dailyNewLimit: Int = 10
    @State private var transliterationVisible: TransliterationMode = .auto
    @State private var useAIGradingAssist: Bool = false
    @State private var starterPackResult: String?
    @State private var activeLanguageCode: String = "ru"

    private let starterPackTotal = 250        // see SeedData.starterPhrases (Russian)
    private let arabicStarterTotal = 115      // see SeedData.arabicStarterPhrases
    private let vocabExpected: [String: Int] = ["A2": 230, "B1": 492, "B2": 986]
    private let starterTopicNames: Set<String> = [
        "Begrüßung", "Höflichkeit", "Verständigung", "Sich vorstellen",
        "Zahlen", "Wochentage", "Monate", "Zeit", "Familie", "Im Restaurant",
        "Wegbeschreibung", "Einkaufen", "Verben", "Adjektive", "Fragewörter",
        "Wetter", "Körperteile", "Essen & Trinken", "Kleidung", "Zuhause",
        "Farben", "Verkehr", "Allgemein"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Aktive Sprache", selection: $activeLanguageCode) {
                        ForEach(languages, id: \.code) { lang in
                            Text(lang.germanLabel).tag(lang.code)
                        }
                    }
                } header: {
                    Text("Sprache")
                } footer: {
                    Text("Phrasen anderer Sprachen werden ausgeblendet, bis du sie hier auswählst. Russisch & Arabisch werden unterstützt – Vokabular fügst du per Stapel-Import oder einzeln hinzu.")
                }

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
                    starterPackRow
                } header: {
                    Text("Starter-Vokabular (A1) – Russisch")
                } footer: {
                    Text("Ca. 250 kuratierte A1-Sätze in 23 Themen (Begrüßung, Familie, Verben, Adjektive, …).")
                }

                Section {
                    arabicStarterRow
                } header: {
                    Text("Starter-Vokabular (A1) – Arabisch")
                } footer: {
                    Text("Ca. 115 A1-Phrasen in Lateinschrift (Transliteration) – die arabische Schrift wird darunter angezeigt. So kannst du sofort mit der deutschen Tastatur tippen, ohne erst das arabische Alphabet zu lernen.")
                }

                Section {
                    vocabRow(level: "A2")
                    vocabRow(level: "B1")
                    vocabRow(level: "B2")
                } header: {
                    Text("Wortlisten (OpenRussian.org)")
                } footer: {
                    Text("Häufigste russische Wörter mit deutschen Übersetzungen. Jede Stufe landet als eigenes Thema in der Bibliothek (inaktiv) – aktiviere sie dort, wenn du soweit bist. Daten: openrussian.org (CC BY-SA 4.0).")
                }

                Section {
                    NavigationLink {
                        BackupView()
                    } label: {
                        Label("Sicherung & Export", systemImage: "externaldrive.badge.icloud")
                    }
                } footer: {
                    Text("Exportiert alle Daten als JSON. TestFlight- und App-Store-Updates erhalten deinen Fortschritt automatisch.")
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
        activeLanguageCode = row?.activeLanguageCode ?? "ru"
    }

    // MARK: - Load-state rows

    private var starterPackRow: some View {
        let loaded = starterPackLoadedCount
        let isLoaded = loaded >= starterPackTotal * 9 / 10
        return Group {
            if isLoaded {
                HStack {
                    Label("Geladen", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Text("\(loaded)/\(starterPackTotal)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else if loaded > 0 {
                Button {
                    let result = SeedData.addStarterPack(context)
                    starterPackResult = "Hinzugefügt: \(result.phrasesAdded) Karten."
                } label: {
                    HStack {
                        Label("Teilweise geladen – Rest laden", systemImage: "arrow.down.circle")
                        Spacer()
                        Text("\(loaded)/\(starterPackTotal)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } else {
                Button {
                    let result = SeedData.addStarterPack(context)
                    starterPackResult = "Hinzugefügt: \(result.phrasesAdded) Karten, \(result.topicsAdded) neue Themen."
                } label: {
                    HStack {
                        Label("Laden", systemImage: "tray.and.arrow.down")
                        Spacer()
                        Text("\(starterPackTotal)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func vocabRow(level: String) -> some View {
        let expected = vocabExpected[level] ?? 0
        let loaded = phrases.filter { phrase in
            phrase.topics.contains { $0.name.hasPrefix("\(level) ") }
        }.count
        let isLoaded = loaded >= expected * 9 / 10
        return Group {
            if isLoaded {
                HStack {
                    Label("Wortliste \(level)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Text("\(loaded)/\(expected)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else {
                Button {
                    let result = SeedData.addVocabLevel(context, level: level)
                    starterPackResult = "Wortliste \(level): \(result.phrasesAdded) Karten hinzugefügt."
                } label: {
                    HStack {
                        Label("Wortliste \(level) laden", systemImage: loaded > 0 ? "arrow.down.circle" : "books.vertical")
                        Spacer()
                        Text(loaded > 0 ? "\(loaded)/\(expected)" : "\(expected)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private var starterPackLoadedCount: Int {
        phrases.filter { phrase in
            phrase.topics.contains { starterTopicNames.contains($0.name) }
        }.count
    }

    private var arabicStarterRow: some View {
        let loaded = phrases.filter { phrase in
            phrase.topics.contains { $0.name.hasSuffix("(AR)") }
        }.count
        let isLoaded = loaded >= arabicStarterTotal * 9 / 10
        return Group {
            if isLoaded {
                HStack {
                    Label("Arabisch-Starter geladen", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Text("\(loaded)/\(arabicStarterTotal)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else {
                Button {
                    let result = SeedData.addArabicStarter(context)
                    starterPackResult = "Arabisch-Starter: \(result.phrasesAdded) Karten hinzugefügt, \(result.topicsAdded) neue Themen."
                } label: {
                    HStack {
                        Label(loaded > 0 ? "Rest laden" : "Laden", systemImage: loaded > 0 ? "arrow.down.circle" : "tray.and.arrow.down")
                        Spacer()
                        Text(loaded > 0 ? "\(loaded)/\(arabicStarterTotal)" : "\(arabicStarterTotal)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
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
        row.activeLanguageCode = activeLanguageCode
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
