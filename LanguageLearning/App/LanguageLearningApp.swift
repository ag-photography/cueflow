import SwiftUI
import SwiftData

@main
struct LanguageLearningApp: App {
    @StateObject private var startup: AppStartupCoordinator

    /// Deterministic screenshot appearance for the isolated debug UI harness.
    /// Ordinary launches and release builds always follow the system setting.
    private var testColorScheme: ColorScheme? {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["CUEFLOW_FORCE_STORE_RECOVERY"] == "1" else { return nil }
        switch ProcessInfo.processInfo.environment["CUEFLOW_TEST_APPEARANCE"] {
        case "Dark": return .dark
        case "Light": return .light
        default: return nil
        }
        #else
        return nil
        #endif
    }

    init() {
        MetricsDiagnosticsService.shared.start()
        #if DEBUG
        let forceRecovery = ProcessInfo.processInfo.environment["CUEFLOW_FORCE_STORE_RECOVERY"] == "1"
        #else
        let forceRecovery = false
        #endif
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        _startup = StateObject(wrappedValue: AppStartupCoordinator(
            forceRecovery: forceRecovery || isTesting,
            skipPreparation: isTesting
        ))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch startup.state {
                case .preparing:
                    AppStartupView(failureMessage: nil)
                case .ready:
                    if let bootstrap = startup.bootstrap {
                        RootView(storeRecoveryMessage: bootstrap.recoveryMessage)
                            .modelContainer(bootstrap.container)
                            .environment(\.cueFlowStorageMode, bootstrap.mode)
                    } else {
                        AppStartupView(failureMessage: "CueFlow konnte den Datenspeicher nicht öffnen.")
                    }
                case .failed(let message):
                    AppStartupView(failureMessage: message)
                }
            }
                // Brand teal as the system tint so buttons, NavigationLinks,
                // selection indicators and active-topic badges inherit it
                // without each view setting `.tint` manually.
                .tint(DS.accent)
                .preferredColorScheme(testColorScheme)
                .task { NotificationService.shared.installRouting(); await startup.start() }
        }
    }
}
