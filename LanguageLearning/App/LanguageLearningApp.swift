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
