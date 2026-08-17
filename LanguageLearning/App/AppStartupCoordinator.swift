import Combine
import Foundation
import SwiftData
import SwiftUI

actor StorePreparer {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func prepare() {
        let context = ModelContext(container)
        SeedData.seedIfNeeded(context)
        SeedData.migrateVocabTopicsToPOS(context)
        SeedData.migrateVocabTopicsToSemantic(context)
        SeedData.ensureSupportedLanguages(context)
        SeedData.migrateArabicToCanonicalScript(context)
        SeedData.ensureAllBundledContent(context)
        SeedData.consolidateSharedCards(context)
        SeedData.backfillExampleSentences(context)
        SeedData.markExistingUsersOnboarded(context)
    }
}

@MainActor
final class AppStartupCoordinator: ObservableObject {
    enum State: Equatable {
        case preparing
        case ready
        case failed(String)
    }

    @Published private(set) var state: State
    @Published private(set) var bootstrap: StoreBootstrapResult?
    private var hasStarted = false
    private let preparation: () async throws -> Void
    private let bootstrapStore: (() async throws -> StoreBootstrapResult)?

    init(forceRecovery: Bool, skipPreparation: Bool) {
        state = .preparing
        bootstrap = nil
        bootstrapStore = { try await StoreBootstrap.makePreferred(forceRecovery: forceRecovery) }
        preparation = {}
        self.skipPreparation = skipPreparation
    }

    init(preparation: @escaping () async throws -> Void) {
        state = .preparing
        bootstrap = nil
        self.preparation = preparation
        bootstrapStore = nil
    }

    private var skipPreparation = false

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        do {
            if let bootstrapStore {
                let result = try await bootstrapStore()
                if !skipPreparation {
                    await StorePreparer(container: result.container).prepare()
                }
                bootstrap = result
            } else {
                try await preparation()
            }
            state = .ready
        } catch {
            state = .failed("CueFlow konnte die Lerninhalte nicht vorbereiten. Bitte starte die App erneut.")
        }
    }
}

struct AppStartupView: View {
    let failureMessage: String?

    var body: some View {
        VStack(spacing: DS.space.lg) {
            Spacer()
            Image(systemName: failureMessage == nil ? "text.bubble.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(failureMessage == nil ? DS.accent : DS.gradeWrong)
                .accessibilityHidden(true)
            Text("CueFlow")
                .font(.system(.largeTitle, design: .serif, weight: .bold))
                .foregroundStyle(DS.textPrimary)
            if let failureMessage {
                Text(failureMessage)
                    .font(.body)
                    .foregroundStyle(DS.textSecondary)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView()
                    .tint(DS.accent)
                Text("Deine Lernreise wird vorbereitet …")
                    .font(.subheadline)
                    .foregroundStyle(DS.textSecondary)
            }
            Spacer()
        }
        .padding(DS.space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.surface0.ignoresSafeArea())
        .accessibilityElement(children: .combine)
    }
}
