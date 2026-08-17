import Foundation
import CloudKit
import SwiftData

enum CueFlowStorageMode: String, Sendable {
    case iCloud
    case local
    case recovery
}

struct StoreBootstrapResult {
    let container: ModelContainer
    let recoveryMessage: String?
    let mode: CueFlowStorageMode

    var isRecovering: Bool { recoveryMessage != nil }
}

enum StoreBootstrap {
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
        if forceRecovery {
            let configuration = ModelConfiguration(
                "LanguageLearningRecovery",
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            return StoreBootstrapResult(
                container: try ModelContainer(for: schema, configurations: configuration),
                recoveryMessage: "Deine lokalen Lerndaten konnten nicht geöffnet werden. CueFlow läuft in einer sicheren Sitzung; neue Fortschritte bleiben nur bis zum Schließen der App erhalten.",
                mode: .recovery
            )
        }

        let localResolution = try resolve {
            let configuration = ModelConfiguration(
                "LanguageLearning",
                schema: schema,
                cloudKitDatabase: .none
            )
            return try ModelContainer(
                for: schema,
                migrationPlan: LanguageLearningMigrationPlan.self,
                configurations: configuration
            )
        } fallback: {
            let configuration = ModelConfiguration(
                "LanguageLearningRecovery",
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: configuration)
        }

        let message = localResolution.usedFallback
            ? "Deine lokalen Lerndaten konnten nicht geöffnet werden. CueFlow läuft in einer sicheren Sitzung; neue Fortschritte bleiben nur bis zum Schließen der App erhalten."
            : nil
        return StoreBootstrapResult(
            container: localResolution.value,
            recoveryMessage: message,
            mode: localResolution.usedFallback ? .recovery : .local
        )
    }

    /// Checks account availability off the main thread before attaching the
    /// CloudKit mirroring delegate. This avoids noisy failed CloudKit stores on
    /// signed-out devices while preserving a fully functional local database.
    static func makePreferred(forceRecovery: Bool = false) async throws -> StoreBootstrapResult {
        if forceRecovery { return try make(forceRecovery: true) }

        #if targetEnvironment(simulator)
        // CoreSimulator can report a stale `.available` account before the
        // CloudKit daemon rejects mirroring. Keep development deterministic;
        // an opt-in remains available for explicit CloudKit simulator testing.
        if ProcessInfo.processInfo.environment["CUEFLOW_ENABLE_CLOUDKIT_SIMULATOR"] != "1" {
            return try make()
        }
        #endif

        let accountStatus = try? await CKContainer(identifier: "iCloud.com.alex.cueflow").accountStatus()
        if accountStatus == .available, let cloud = try? makeCloudContainer() {
            return cloud
        }
        return try make()
    }

    private static func makeCloudContainer() throws -> StoreBootstrapResult {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(
            "LanguageLearning",
            schema: schema,
            cloudKitDatabase: .automatic
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: LanguageLearningMigrationPlan.self,
            configurations: configuration
        )
        return StoreBootstrapResult(container: container, recoveryMessage: nil, mode: .iCloud)
    }
}
