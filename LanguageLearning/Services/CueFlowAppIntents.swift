import AppIntents
import Foundation

enum CueFlowPendingAction: String, Sendable {
    case practice
    case conversation
    case listening

    private static let key = "pendingAppIntentAction"

    static func store(_ action: CueFlowPendingAction, defaults: UserDefaults = sharedDefaults) {
        defaults.set(action.rawValue, forKey: key)
    }

    static func consume(defaults: UserDefaults = sharedDefaults) -> CueFlowPendingAction? {
        guard let raw = defaults.string(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        return CueFlowPendingAction(rawValue: raw)
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: CueFlowWidgetSnapshot.suiteName) ?? .standard
    }
}

struct StartCueFlowPracticeIntent: AppIntent {
    static let title: LocalizedStringResource = "CueFlow-Einheit starten"
    static let description = IntentDescription("Öffnet direkt die empfohlene sprechorientierte Einheit.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        CueFlowPendingAction.store(.practice)
        return .result()
    }
}

struct StartCueFlowConversationIntent: AppIntent {
    static let title: LocalizedStringResource = "CueFlow-Gespräch starten"
    static let description = IntentDescription("Öffnet die Auswahl der geführten Rollenspiele.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        CueFlowPendingAction.store(.conversation)
        return .result()
    }
}

struct StartCueFlowListeningIntent: AppIntent {
    static let title: LocalizedStringResource = "CueFlow-Hörstudio starten"
    static let description = IntentDescription("Öffnet fünf kurze Hör- und Nachsprechübungen.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        CueFlowPendingAction.store(.listening)
        return .result()
    }
}

struct CueFlowShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartCueFlowPracticeIntent(),
            phrases: [
                "Einheit mit \(.applicationName) starten",
                "Mit \(.applicationName) sprechen"
            ],
            shortTitle: "Einheit starten",
            systemImageName: "text.bubble.fill"
        )
        AppShortcut(
            intent: StartCueFlowConversationIntent(),
            phrases: [
                "Gespräch mit \(.applicationName) starten",
                "Rollenspiel in \(.applicationName)"
            ],
            shortTitle: "Gespräch",
            systemImageName: "person.2.wave.2.fill"
        )
        AppShortcut(
            intent: StartCueFlowListeningIntent(),
            phrases: [
                "Hörstudio mit \(.applicationName) starten",
                "Mit \(.applicationName) nachsprechen"
            ],
            shortTitle: "Hörstudio",
            systemImageName: "ear.and.waveform"
        )
    }
}
