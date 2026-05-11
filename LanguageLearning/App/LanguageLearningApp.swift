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
            SeedData.seedIfNeeded(ModelContext(container))
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
        }
    }
}
