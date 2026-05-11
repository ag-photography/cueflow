import Foundation
import SwiftData

enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Language.self,
            Topic.self,
            Phrase.self,
            StudyCard.self,
            Review.self,
            Session.self,
            AppSettings.self,
        ]
    }
}

enum LanguageLearningMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
