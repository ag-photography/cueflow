import Foundation
import SwiftData

struct StoreBootstrapResult {
    let container: ModelContainer
    let recoveryMessage: String?

    var isRecovering: Bool { recoveryMessage != nil }
}

enum StoreBootstrap {
    private enum DiagnosticError: Error { case forcedRecovery }

    struct Resolution<Value> {
        let value: Value
        let persistentError: Error?

        var usedFallback: Bool { persistentError != nil }
    }

    /// Kept generic so the recovery decision can be tested without damaging a
    /// real SwiftData store. The fallback is only attempted after persistence
    /// fails, and its error is allowed to surface if even a safe session cannot
    /// be created.
    static func resolve<Value>(
        persistent: () throws -> Value,
        fallback: () throws -> Value
    ) throws -> Resolution<Value> {
        do {
            return Resolution(value: try persistent(), persistentError: nil)
        } catch {
            let persistentError = error
            return Resolution(value: try fallback(), persistentError: persistentError)
        }
    }

    static func make(forceRecovery: Bool = false) throws -> StoreBootstrapResult {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let resolution = try resolve {
            if forceRecovery { throw DiagnosticError.forcedRecovery }
            let configuration = ModelConfiguration("LanguageLearning", schema: schema)
            return try ModelContainer(
                for: schema,
                migrationPlan: LanguageLearningMigrationPlan.self,
                configurations: configuration
            )
        } fallback: {
            let configuration = ModelConfiguration(
                "LanguageLearningRecovery",
                schema: schema,
                isStoredInMemoryOnly: true
            )
            return try ModelContainer(for: schema, configurations: configuration)
        }

        let message = resolution.usedFallback
            ? "Deine lokalen Lerndaten konnten nicht geöffnet werden. CueFlow läuft in einer sicheren Sitzung; neue Fortschritte bleiben nur bis zum Schließen der App erhalten."
            : nil
        return StoreBootstrapResult(container: resolution.value, recoveryMessage: message)
    }
}
