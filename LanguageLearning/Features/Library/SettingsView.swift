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
    @State private var dailyReminderEnabled: Bool = false
    @State private var dailyReminderTime: Date = SettingsView.defaultReminderTime
    @State private var reminderPermissionDenied: Bool = false
    @State private var surpriseRewardsEnabled: Bool = true
    @State private var showingOnboarding = false

    private static var defaultReminderTime: Date {
        var comps = DateComponents()
        comps.hour = 19
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? .now
    }

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

                Section {
                    Toggle("Tägliche Erinnerung", isOn: $dailyReminderEnabled)
                        .onChange(of: dailyReminderEnabled) { _, newValue in
                            handleReminderToggle(newValue)
                        }
                    if dailyReminderEnabled {
                        DatePicker(
                            "Zeit",
                            selection: $dailyReminderTime,
                            displayedComponents: .hourAndMinute
                        )
                        .onChange(of: dailyReminderTime) { _, newTime in
                            saveReminderTime(newTime)
                            Task {
                                let cal = Calendar.current
                                let comps = cal.dateComponents([.hour, .minute], from: newTime)
                                await NotificationService.shared.scheduleDailyReminder(
                                    hour: comps.hour ?? 19,
                                    minute: comps.minute ?? 0
                                )
                            }
                        }
                    }
                    if reminderPermissionDenied {
                        Text("Benachrichtigungen sind in den iOS-Einstellungen deaktiviert. Aktiviere sie dort, um die Erinnerung zu nutzen.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Erinnerung")
                } footer: {
                    Text("Eine sanfte tägliche Erinnerung zur gewählten Zeit. Keine Streak-Panik, keine FOMO. Jederzeit ausschaltbar.")
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
                    Toggle("Überraschungs-Belohnungen", isOn: $surpriseRewardsEnabled)
                } footer: {
                    Text("Gelegentliche Mini-Feier nach einer richtigen Antwort (ca. jede 8. Karte). Reines Spaß-Element — wenn's nervt, ausschalten.")
                }

                Section {
                    NavigationLink {
                        BackupView()
                    } label: {
                        Label("Sicherung & Export", systemImage: "externaldrive.badge.icloud")
                    }
                } footer: {
                    Text("Fortschritt & Streak: oben rechts auf der Übungsseite (Diagramm-Icon). TestFlight-Updates erhalten deinen Fortschritt automatisch.")
                }

                Section {
                    Button {
                        save()   // don't lose unsaved edits behind the cover
                        showingOnboarding = true
                    } label: {
                        Label("Einführung wiederholen", systemImage: "sparkles")
                    }
                } footer: {
                    Text("Zeigt die Erstkonfiguration erneut — Tagesziel, Starter-Themen und die Tastatur-Anleitung.")
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
            .fullScreenCover(isPresented: $showingOnboarding) {
                OnboardingView()
            }
            .onAppear { hydrate() }
        }
    }

    private func hydrate() {
        let row = settings.first
        dailyNewLimit = row?.dailyNewLimit ?? 10
        transliterationVisible = TransliterationMode.from(row?.transliterationVisible)
        useAIGradingAssist = row?.useAIGradingAssist ?? false
        activeLanguageCode = row?.activeLanguageCode ?? "ru"
        dailyReminderEnabled = row?.dailyReminderEnabled ?? false
        var comps = DateComponents()
        comps.hour = row?.dailyReminderHour ?? 19
        comps.minute = row?.dailyReminderMinute ?? 0
        dailyReminderTime = Calendar.current.date(from: comps) ?? Self.defaultReminderTime
        surpriseRewardsEnabled = row?.surpriseRewardsEnabled ?? true
    }

    private func handleReminderToggle(_ enabled: Bool) {
        if enabled {
            Task {
                let granted = await NotificationService.shared.requestAuthorization()
                if granted {
                    reminderPermissionDenied = false
                    saveReminderEnabled(true)
                    let cal = Calendar.current
                    let comps = cal.dateComponents([.hour, .minute], from: dailyReminderTime)
                    await NotificationService.shared.scheduleDailyReminder(
                        hour: comps.hour ?? 19,
                        minute: comps.minute ?? 0
                    )
                } else {
                    reminderPermissionDenied = true
                    dailyReminderEnabled = false   // revert toggle since not authorised
                }
            }
        } else {
            NotificationService.shared.cancelDailyReminder()
            saveReminderEnabled(false)
        }
    }

    private func saveReminderEnabled(_ enabled: Bool) {
        ensureSettingsRow().dailyReminderEnabled = enabled
        try? context.save()
    }

    private func saveReminderTime(_ time: Date) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        let row = ensureSettingsRow()
        row.dailyReminderHour = comps.hour ?? 19
        row.dailyReminderMinute = comps.minute ?? 0
        try? context.save()
    }

    private func ensureSettingsRow() -> AppSettings {
        if let existing = settings.first { return existing }
        let row = AppSettings()
        context.insert(row)
        return row
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
        row.surpriseRewardsEnabled = surpriseRewardsEnabled
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
