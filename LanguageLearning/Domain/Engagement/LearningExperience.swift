import Foundation
import SwiftData

struct LearningPreferences: Codable, Equatable {
    var purpose = "Reisen"
    var quiet = false
    var weeklyDays = 3
    var studyWeekdays: [Int]? = nil
    var calibrationAt: Date? = nil
    var calibrationCorrect: Int? = nil
    var effectiveStudyWeekdays: [Int] { studyWeekdays ?? Array([2, 4, 6, 3, 5, 7, 1].prefix(max(0, min(7, weeklyDays)))) }
}

struct EpisodeAttempt: Codable, Equatable {
    let stepID: String
    let correct: Bool
    let supported: Bool
    let spoken: Bool
    let timestamp: Date
    var spokenWordCount: Int? = nil
}

struct EpisodeRun: Codable, Identifiable, Equatable {
    var id = UUID()
    let episodeID: String
    let contentVersion: Int
    let language: String
    var startedAt = Date.now
    var updatedAt = Date.now
    var stepIndex = 0
    var attempts: [EpisodeAttempt] = []
    var modelRevealed = false
    var isDelayedCheck: Bool = false
    var exposureGapSeconds: Double? = nil
    var completedAt: Date?
    var endedAt: Date?
    var activeSeconds: Double? = nil
    var calibration: Bool? = nil

    var independentCount: Int { attempts.filter { $0.correct && !$0.supported }.count }
    var isOpen: Bool { completedAt == nil && endedAt == nil }

    func isValid(for episode: LearningEpisode) -> Bool {
        episodeID == episode.id && contentVersion == episode.version && language == episode.language
            && (0...episode.steps.count).contains(stepIndex)
            && (completedAt == nil ? stepIndex < episode.steps.count : stepIndex == episode.steps.count)
            && Set(attempts.map(\.stepID)).count == attempts.count
            && attempts.allSatisfy { attempt in episode.steps.contains { $0.id == attempt.stepID && $0.kind != .model } }
    }
}

struct LocalLearningEvent: Codable, Identifiable {
    var id = UUID()
    let name: String
    let language: String
    let sessionID: UUID
    let timestamp: Date
    let stepID: String?
    var activeSeconds: Double? = nil
    var support: String? = nil
    var matched: Bool? = nil
}

struct LearningTrial: Codable, Equatable {
    var policyVersion = 1
    var startedAt = Date.now
    var variant: String
    var endedAt: Date? = nil
}

struct LearningExperience: Codable {
    static let meaningfulEventNames: Set<String> = ["practice_answer", "listening_answer", "listening_dictation", "reading_translation", "reading_audio", "conversation_turn", "sprint_answer", "arcade_completed"]
    var version = 1
    var preferences: [String: LearningPreferences] = [:]
    var runs: [EpisodeRun] = []
    var events: [LocalLearningEvent] = []
    var practicePlans: [PracticePlan]? = nil
    var otherModeExposureAt: [String: Date]? = nil
    var eventResetAt: Date? = nil
    var trial: LearningTrial? = nil
    var earnedMilestones: [String: Date]? = nil
    var cardAttempts: [CardAttemptCheckpoint]? = nil
    var endedPlanIDs: [UUID]? = nil
    var learningDayKeys: [String: [String]]? = nil

    func preference(for language: String) -> LearningPreferences { preferences[language] ?? .init() }
    func completed(in language: String) -> Set<String> {
        Set(runs.filter { $0.language == language && $0.completedAt != nil }.map(\.episodeID))
    }
    /// Checks are separated from the immediate rehearsal: they start without a
    /// model and never certify free conversation or modify unrelated FSRS cards.
    func isCheckDue(_ episode: LearningEpisode, now: Date = .now) -> Bool {
        let matching = runs.filter { $0.episodeID == episode.id && $0.contentVersion == episode.version }
        guard !matching.contains(where: \.isOpen) else { return false }
        let finished = matching.filter { $0.completedAt != nil }
        guard let latest = finished.max(by: { $0.completedAt! < $1.completedAt! }), let date = latest.completedAt else { return false }
        let delay: TimeInterval = latest.isDelayedCheck ? 7 * 86_400 : 86_400
        let lastExposure = max(date, matching.map(\.updatedAt).max() ?? date, otherModeExposureAt?[episode.language] ?? .distantPast)
        return now.timeIntervalSince(lastExposure) >= delay
    }
    func dueEpisode(language: String, now: Date = .now) -> LearningEpisode? {
        EpisodeLibrary.all.filter { $0.language == language && isCheckDue($0, now: now) }.sorted { lhs, rhs in
            let left = runs.filter { $0.episodeID == lhs.id }.compactMap(\.completedAt).max() ?? .distantPast
            let right = runs.filter { $0.episodeID == rhs.id }.compactMap(\.completedAt).max() ?? .distantPast
            return left < right
        }.first
    }
    func retainedCount(for episode: LearningEpisode) -> Int {
        runs.filter { $0.episodeID == episode.id && $0.contentVersion == episode.version && $0.isDelayedCheck && $0.completedAt != nil }
            .max(by: { $0.updatedAt < $1.updatedAt })?.independentCount ?? 0
    }
    mutating func event(_ name: String, run: EpisodeRun, step: String? = nil, now: Date = .now) {
        events.removeAll { $0.timestamp < now.addingTimeInterval(-90 * 86_400) }
        events.append(.init(name: name, language: run.language, sessionID: run.id, timestamp: now, stepID: step))
    }
    mutating func save(_ run: EpisodeRun) {
        if let index = runs.firstIndex(where: { $0.id == run.id }) { runs[index] = run }
        else { runs.append(run) }
    }
    mutating func merge(_ incoming: LearningExperience) {
        var days = learningDayKeys ?? [:]
        for (language, keys) in incoming.learningDayKeys ?? [:] { days[language] = Array(Set((days[language] ?? []) + keys)).sorted() }
        learningDayKeys = days
        endedPlanIDs = Array(Set((endedPlanIDs ?? []) + (incoming.endedPlanIDs ?? [])))
        for checkpoint in incoming.cardAttempts ?? [] {
            if let existing = cardAttempts?.first(where: { $0.id == checkpoint.id }), existing.updatedAt >= checkpoint.updatedAt { continue }
            save(checkpoint)
        }
        var awards = earnedMilestones ?? [:]
        for (key, date) in incoming.earnedMilestones ?? [:] { awards[key] = min(awards[key] ?? .distantFuture, date) }
        earnedMilestones = awards
        if let candidate = incoming.trial {
            if trial == nil || candidate.startedAt < trial!.startedAt
                || (candidate.startedAt == trial?.startedAt && candidate.variant < (trial?.variant ?? "")) { trial = candidate }
            else if candidate.startedAt == trial?.startedAt && candidate.variant == trial?.variant, let ended = candidate.endedAt {
                let previousEnd = trial?.endedAt ?? .distantPast
                trial?.endedAt = max(previousEnd, ended)
            }
        }
        if let reset = incoming.eventResetAt { eventResetAt = max(eventResetAt ?? .distantPast, reset) }
        var exposures = otherModeExposureAt ?? [:]
        for (key, value) in incoming.otherModeExposureAt ?? [:] { exposures[key] = max(exposures[key] ?? .distantPast, value) }
        otherModeExposureAt = exposures
        var plans = practicePlans ?? []
        let known = Set(plans.map(\.id))
        plans += (incoming.practicePlans ?? []).filter { !known.contains($0.id) }
        practicePlans = plans
        for (key, value) in incoming.preferences { preferences[key] = value }
        for run in incoming.runs {
            if let existing = runs.first(where: { $0.id == run.id }), existing.updatedAt >= run.updatedAt { continue }
            save(run)
        }
        var ids = Set(events.map(\.id))
        for event in incoming.events where ids.insert(event.id).inserted { events.append(event) }
        events.removeAll { $0.timestamp < Date.now.addingTimeInterval(-90 * 86_400) }
        if let reset = eventResetAt { events.removeAll { $0.timestamp <= reset } }
    }
    func learningDays(language: String, now: Date = .now) -> Int {
        let interval = Calendar.current.dateInterval(of: .weekOfYear, for: now)
        let storyDays = runs.filter { $0.language == language && $0.completedAt.map { interval?.contains($0) == true } == true }
            .compactMap { $0.completedAt.map { Calendar.current.startOfDay(for: $0) } }
        let cardDays = events.filter { $0.language == language && Self.meaningfulEventNames.contains($0.name) && interval?.contains($0.timestamp) == true }
            .map { Calendar.current.startOfDay(for: $0.timestamp) }
        let recorded = Set((storyDays + cardDays).map(Self.dayKey))
        let weekKeys: Set<String>
        if let start = interval?.start {
            weekKeys = Set((0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }.map(Self.dayKey))
        } else { weekKeys = [] }
        return recorded.union(Set(learningDayKeys?[language] ?? []).intersection(weekKeys)).count
    }

    /// Retain anonymous day-level totals when raw analytics expire or are reset.
    mutating func captureLearningDays() {
        var days = (learningDayKeys ?? [:]).mapValues { Set($0) }
        for event in events where Self.meaningfulEventNames.contains(event.name) {
            days[event.language, default: []].insert(Self.dayKey(event.timestamp))
        }
        for run in runs {
            if let date = run.completedAt { days[run.language, default: []].insert(Self.dayKey(date)) }
        }
        learningDayKeys = days.mapValues { $0.sorted() }
    }

    private static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

extension AppSettings {
    @MainActor
    func readExperience() throws -> LearningExperience {
        guard let experienceJSON else { return .init() }
        return try LearningExperienceDecoder.decode(experienceJSON)
    }
    @MainActor
    func writeExperience(_ experience: LearningExperience) throws {
        var materialized = experience
        materialized.captureLearningDays()
        if let modelContext { try LearningJournalStore.persist(materialized, in: modelContext) }
        experienceJSON = String(decoding: try JSONEncoder().encode(materialized), as: UTF8.self)
    }
}

/// Keep body evaluation and tab switches from reparsing the activity journal.
/// A changed JSON value (including CloudKit/restore changes) invalidates it.
@MainActor
private enum LearningExperienceDecoder {
    private static var cachedJSON: String?
    private static var cachedValue: LearningExperience?
    static func decode(_ json: String) throws -> LearningExperience {
        if cachedJSON == json, let cachedValue { return cachedValue }
        let value = try JSONDecoder().decode(LearningExperience.self, from: Data(json.utf8))
        guard value.version == 1 else { throw ExperienceError.unsupportedVersion }
        cachedJSON = json
        cachedValue = value
        return value
    }
}

enum ExperienceError: LocalizedError {
    case unsupportedVersion
    var errorDescription: String? { "Dieser Lernverlauf benötigt eine neuere App-Version." }
}
