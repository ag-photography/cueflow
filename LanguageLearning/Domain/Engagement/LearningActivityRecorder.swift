import Foundation
import SwiftData

@MainActor
enum LearningActivityRecorder {
    /// Non-assessment modes retain engagement/support, never a productive FSRS
    /// grade. No transcript, phrase text or recording enters these events.
    static func record(_ name: String, language: String, session: UUID, step: String? = nil,
                       support: String? = nil, matched: Bool? = nil, context: ModelContext) throws {
        guard let row = try context.fetch(FetchDescriptor<AppSettings>()).first else { return }
        var data = try row.readExperience()
        guard !data.events.contains(where: { $0.sessionID == session && $0.stepID == step && $0.name == name }) else { return }
        data.events.append(.init(name: name, language: language, sessionID: session, timestamp: .now,
            stepID: step, support: support, matched: matched))
        try row.writeExperience(data)
        try context.save()
    }
}
