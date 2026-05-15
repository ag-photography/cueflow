import SwiftUI
import SwiftData

@main
struct LanguageLearningApp: App {
    let container: ModelContainer

    init() {
        do {
            let schema = Schema(versionedSchema: SchemaV1.self)
            let configuration = ModelConfiguration("LanguageLearning", schema: schema)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: LanguageLearningMigrationPlan.self,
                configurations: configuration
            )
            self.container = container
            let setupContext = ModelContext(container)
            SeedData.seedIfNeeded(setupContext)
            // Backfill StudyCards for any new directions added in updates
            // (idempotent — only inserts the missing ones).
            SeedData.backfillMissingCards(setupContext)
            // Migrate old "Wortliste A2/B1/B2" mega-topics into POS-split
            // topics (idempotent — no-op once migrated).
            SeedData.migrateVocabTopicsToPOS(setupContext)
            // Ensure all supported language records exist (Russian, Arabic).
            // Adds missing ones without touching content for existing ones.
            SeedData.ensureSupportedLanguages(setupContext)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
                // Brand teal as the system tint so buttons, NavigationLinks,
                // selection indicators and active-topic badges inherit it
                // without each view setting `.tint` manually.
                .tint(DS.accent)
        }
    }
}
