import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Environment(\.cueFlowStorageMode) private var storageMode
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
    @State private var devTapCount = 0
    @State private var didHydrate = false
    @State private var saveErrorMessage: String?
    @AppStorage("soundEffectsEnabled") private var soundEffectsEnabled = true
    @StateObject private var cloudStatus = CloudSyncStatusService()

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
                // MARK: Sprache & Inhalte
                Section {
                    // Featured: the active language is identity-level (it swaps
                    // all content), so it anchors the screen — accent-tinted row.
                    Picker(selection: $activeLanguageCode) {
                        ForEach(languages, id: \.code) { lang in
                            Text(lang.germanLabel).tag(lang.code)
                        }
                    } label: {
                        HStack(spacing: DS.space.sm) {
                            Image(systemName: "globe").foregroundStyle(DS.accent)
                            Text("Aktive Sprache")
                        }
                    }
                    .listRowBackground(DS.accentSoft)

                    Picker("Transliteration", selection: $transliterationVisible) {
                        ForEach(TransliterationMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .listRowBackground(DS.surface1)
                } header: {
                    Text("Sprache & Inhalte")
                } footer: {
                    Text("Phrasen anderer Sprachen werden ausgeblendet, bis du sie hier auswählst. Russisch & Arabisch werden unterstützt. Transliteration zeigt die Lautschrift unter der Antwort.")
                }

                // MARK: Üben
                Section {
                    Stepper(value: $dailyNewLimit, in: 0...50) {
                        HStack {
                            Text("Neue Karten pro Tag")
                            Spacer()
                            Text("\(dailyNewLimit)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle("KI-Bewertungshilfe", isOn: $useAIGradingAssist)
                    Toggle("Abruf-Meilensteine", isOn: $surpriseRewardsEnabled)
                    Toggle("Klangeffekte", isOn: $soundEffectsEnabled)
                } header: {
                    Text("Üben")
                } footer: {
                    Text("Neue Karten pro Tag begrenzt die Einführung; Wiederholungen sind unbegrenzt. KI-Bewertungshilfe nutzt Apples On-Device-Modell (iOS 26+). Abruf-Meilensteine würdigen echte Serien selbständig produzierter Antworten. Klangeffekte respektieren den Stummmodus.")
                }
                .listRowBackground(DS.surface1)

                // MARK: Erinnerungen
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
                    Text("Erinnerungen")
                } footer: {
                    Text("Eine sanfte tägliche Erinnerung zur gewählten Zeit. Keine Streak-Panik, keine FOMO. Jederzeit ausschaltbar.")
                }
                .listRowBackground(DS.surface1)

                // MARK: Daten
                Section {
                    Label(cloudStatus.status.label, systemImage: cloudStatus.status.symbol)
                        .foregroundStyle(cloudStatus.status == .available ? DS.accent : DS.textSecondary)
                    NavigationLink {
                        BackupView()
                    } label: {
                        Label("Sicherung & Export", systemImage: "externaldrive.badge.icloud")
                    }
                } header: {
                    Text("Daten")
                } footer: {
                    Text("Mit iCloud werden Lernstand und Inhalte privat über deine Apple-ID synchronisiert. Ohne verfügbaren Account bleibt alles vollständig auf diesem Gerät nutzbar. Sicherungen lassen sich zusätzlich exportieren und wiederherstellen.")
                }
                .listRowBackground(DS.surface1)

                // MARK: Entwickler (hidden until unlocked)
                if developerModeEnabled {
                    Section {
                        NavigationLink {
                            TelemetryView()
                        } label: {
                            Label("Diagnose", systemImage: "chart.bar.doc.horizontal")
                        }
                        Button(role: .destructive) {
                            setDeveloperMode(false)
                        } label: {
                            Label("Entwicklermodus ausblenden", systemImage: "eye.slash")
                        }
                    } header: {
                        Text("Entwickler")
                    }
                    .listRowBackground(DS.surface1)
                }

                // MARK: Info
                Section {
                    Button {
                        if save() {   // don't lose unsaved edits behind the cover
                            showingOnboarding = true
                        }
                    } label: {
                        Label("Einführung wiederholen", systemImage: "sparkles")
                    }
                } footer: {
                    versionFooter
                }
                .listRowBackground(DS.surface1)
            }
            .scrollContentBackground(.hidden)
            .background(
                LinearGradient(
                    colors: [DS.surface0, DS.surface2.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Einstellungen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        if save() { dismiss() }
                    }
                }
            }
            .fullScreenCover(isPresented: $showingOnboarding) {
                OnboardingView()
            }
            .onAppear { hydrate() }
            .task { await cloudStatus.refresh(storageMode: storageMode) }
            .onChange(of: dailyNewLimit) { _, _ in saveAfterHydration() }
            .onChange(of: transliterationVisible) { _, _ in saveAfterHydration() }
            .onChange(of: useAIGradingAssist) { _, _ in saveAfterHydration() }
            .onChange(of: activeLanguageCode) { _, _ in saveAfterHydration() }
            .onChange(of: surpriseRewardsEnabled) { _, _ in saveAfterHydration() }
            .onDisappear {
                // Interactive sheet dismissal must behave like the explicit
                // confirmation action; settings should never silently vanish.
                if didHydrate { _ = save() }
            }
            .alert("Einstellungen konnten nicht gespeichert werden", isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "Bitte versuche es erneut.")
            }
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
        didHydrate = true
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
        persistContext()
    }

    private func saveReminderTime(_ time: Date) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        let row = ensureSettingsRow()
        row.dailyReminderHour = comps.hour ?? 19
        row.dailyReminderMinute = comps.minute ?? 0
        persistContext()
    }

    private func ensureSettingsRow() -> AppSettings {
        if let existing = settings.first { return existing }
        let row = AppSettings()
        context.insert(row)
        return row
    }

    @discardableResult
    private func save() -> Bool {
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
        return persistContext()
    }

    private func saveAfterHydration() {
        if didHydrate { _ = save() }
    }

    @discardableResult
    private func persistContext() -> Bool {
        do {
            try context.save()
            saveErrorMessage = nil
            return true
        } catch {
            saveErrorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Developer mode

    private var developerModeEnabled: Bool {
        settings.first?.developerModeEnabled ?? false
    }

    private func setDeveloperMode(_ on: Bool) {
        ensureSettingsRow().developerModeEnabled = on
        persistContext()
        devTapCount = 0
    }

    /// App-version line that doubles as the hidden unlock: seven taps reveal the
    /// Entwickler section (classic iOS "tap to unlock dev tools" pattern).
    private var versionFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Zeigt die Erstkonfiguration erneut — Tagesziel, Starter-Themen und Tastatur-Anleitung.")
            Text(appVersionString)
                .foregroundStyle(.tertiary)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !developerModeEnabled else { return }
                    devTapCount += 1
                    if devTapCount >= 7 {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        setDeveloperMode(true)
                    }
                }
        }
    }

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "CueFlow \(version) (Build \(build))"
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
