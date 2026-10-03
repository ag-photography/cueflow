import Foundation
import SwiftData

/// Immutable journal fragments sync independently. Two devices completing
/// different stories no longer overwrite each other's entire settings field.
/// No uniqueness constraint: CloudKit duplicates reconcile by logical identity.
@Model
final class LearningJournalRecord {
    var kind: String = ""
    var payload: String = ""
    var createdAt: Date = Date.now
    init(kind: String, payload: String) { self.kind = kind; self.payload = payload }
}

@MainActor
enum LearningJournalStore {
    static func supports(_ context: ModelContext) -> Bool {
        context.container.schema.entities.contains { $0.name == "LearningJournalRecord" }
    }
    static func persist(_ data: LearningExperience, in context: ModelContext) throws {
        guard supports(context) else { return } // older-schema migration fixtures
        let rows = try context.fetch(FetchDescriptor<LearningJournalRecord>())
        var known = Set(rows.map { $0.kind + $0.payload })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        func add<T: Encodable>(_ kind: String, _ value: T) throws {
            let payload = String(decoding: try encoder.encode(value), as: UTF8.self)
            guard known.insert(kind + payload).inserted else { return }
            context.insert(LearningJournalRecord(kind: kind, payload: payload))
        }
        for run in data.runs { try add("run", run) }
        for event in data.events { try add("event", event) }
        for plan in data.practicePlans ?? [] { try add("plan", plan) }
        for checkpoint in data.cardAttempts ?? [] { try add("attempt", checkpoint) }
        for id in data.endedPlanIDs ?? [] { try add("planEnded", id) }
        for (language, days) in data.learningDayKeys ?? [:] {
            for day in days { try add("learningDay", [language: day]) }
        }
        for (language, date) in data.otherModeExposureAt ?? [:] { try add("exposure", [language: date]) }
        if let awards = data.earnedMilestones, !awards.isEmpty { try add("awards", awards) }
        if let reset = data.eventResetAt { try add("reset", reset) }
        if let trial = data.trial { try add("trial", trial) }
        let cutoff = max(Date.now.addingTimeInterval(-90 * 86_400), data.eventResetAt ?? .distantPast)
        for row in rows where row.kind == "event" {
            let event = try JSONDecoder().decode(LocalLearningEvent.self, from: Data(row.payload.utf8))
            if event.timestamp <= cutoff { context.delete(row) }
        }
    }
    static func merged(_ base: LearningExperience, records: [LearningJournalRecord]) throws -> LearningExperience {
        var incoming = LearningExperience()
        let decoder = JSONDecoder()
        for row in records {
            let payload = Data(row.payload.utf8)
            switch row.kind {
            case "run":
                let run = try decoder.decode(EpisodeRun.self, from: payload)
                if let previous = incoming.runs.first(where: { $0.id == run.id }), previous.updatedAt >= run.updatedAt { continue }
                incoming.save(run)
            case "event": incoming.events.append(try decoder.decode(LocalLearningEvent.self, from: payload))
            case "planEnded": incoming.endedPlanIDs = (incoming.endedPlanIDs ?? []) + [try decoder.decode(UUID.self, from: payload)]
            case "learningDay":
                let values = try decoder.decode([String: String].self, from: payload)
                var days = incoming.learningDayKeys ?? [:]
                for (language, day) in values { days[language] = Array(Set((days[language] ?? []) + [day])).sorted() }
                incoming.learningDayKeys = days
            case "attempt":
                let checkpoint = try decoder.decode(CardAttemptCheckpoint.self, from: payload)
                if let previous = incoming.cardAttempts?.first(where: { $0.id == checkpoint.id }), previous.updatedAt >= checkpoint.updatedAt { continue }
                incoming.save(checkpoint)
            case "plan":
                let plan = try decoder.decode(PracticePlan.self, from: payload)
                if !(incoming.practicePlans ?? []).contains(where: { $0.id == plan.id }) { incoming.practicePlans = (incoming.practicePlans ?? []) + [plan] }
            case "exposure":
                let values = try decoder.decode([String: Date].self, from: payload)
                var dates = incoming.otherModeExposureAt ?? [:]
                for (language, date) in values { dates[language] = max(dates[language] ?? .distantPast, date) }
                incoming.otherModeExposureAt = dates
            case "reset": incoming.eventResetAt = max(incoming.eventResetAt ?? .distantPast, try decoder.decode(Date.self, from: payload))
            case "awards":
                let values = try decoder.decode([String: Date].self, from: payload)
                var awards = incoming.earnedMilestones ?? [:]
                for (key, date) in values { awards[key] = min(awards[key] ?? .distantFuture, date) }
                incoming.earnedMilestones = awards
            case "trial":
                var fragment = LearningExperience()
                fragment.trial = try decoder.decode(LearningTrial.self, from: payload)
                incoming.merge(fragment)
            default: throw ExperienceError.unsupportedVersion
            }
        }
        var result = base
        result.merge(incoming)
        return result
    }
}
