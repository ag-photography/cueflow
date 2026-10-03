import Foundation
import SwiftData

/// Stories and card practice share one Phrase/StudyCard and one FSRS schedule.
/// Exposure is persisted separately from success, using the existing review
/// entity so backups and CloudKit keep the evidence with its canonical card.
@MainActor
enum EpisodeVocabulary {
    static func key(language: String, answer: String) -> String {
        language + ":" + FuzzyMatcher.normalize(answer)
    }

    static func card(for step: LearningEpisode.Step, episode: LearningEpisode, context: ModelContext) throws -> StudyCard {
        let languageCode = episode.language
        let phrases = try context.fetch(FetchDescriptor<Phrase>())
        let identity = key(language: languageCode, answer: step.answer)
        if let existing = phrases.first(where: {
            $0.language?.code == languageCode && key(language: languageCode, answer: $0.targetText) == identity
        }) {
            if let card = existing.cards?.first { return card }
            let card = StudyCard(phrase: existing)
            context.insert(card)
            return card
        }
        guard let language = try context.fetch(FetchDescriptor<Language>()).first(where: { $0.code == languageCode }) else {
            throw VocabularyError.missingLanguage
        }
        let topicName = "Mini-Geschichten"
        let topics = try context.fetch(FetchDescriptor<Topic>())
        let topic = topics.first { $0.language?.code == languageCode && $0.name == topicName }
            ?? Topic(name: topicName, language: language, isActive: true)
        if topic.modelContext == nil { context.insert(topic) }
        let phrase = Phrase(sourceText: step.meaning, targetText: step.answer, language: language, topics: [topic])
        phrase.acceptedAlternatives = step.alternatives
        phrase.qualityStatus = .unreviewed
        phrase.level = .a1
        phrase.notes = "Entwurf aus Mini-Geschichte \(episode.id), Version \(episode.version). Muttersprachliche Prüfung ausstehend."
        context.insert(phrase)
        let card = StudyCard(phrase: phrase)
        context.insert(card)
        return card
    }

    /// Caller commits this together with the story checkpoint. A repeated UI
    /// callback cannot create another review or apply the schedule twice.
    static func record(episode: LearningEpisode, run: EpisodeRun, step: LearningEpisode.Step,
                       attempt: EpisodeAttempt?, context: ModelContext, now: Date = .now) throws {
        let card = try card(for: step, episode: episode, context: context)
        let history = card.reviews ?? []
        let kind = attempt == nil ? "exposure" : step.kind.rawValue
        guard !history.contains(where: {
            $0.evidence?.sessionID == run.id && $0.evidence?.promptID == step.id && $0.evidence?.kind == kind
        }) else { return }
        let barrier = try context.fetch(FetchDescriptor<AppSettings>()).first?.readExperience().otherModeExposureAt?[episode.language]
        let recorded = history.map(\.timestamp).max()
        let lastExposure = recorded == nil && barrier == nil ? nil : max(recorded ?? .distantPast, barrier ?? .distantPast)
        let supported = attempt?.supported ?? true
        let correct = attempt?.correct ?? false
        var evidence = AttemptEvidence(support: supported ? .revealed : .none,
            inputWasSpeech: attempt?.spoken ?? false, assessedCorrect: correct, gradingMethod: attempt == nil ? 0 : 1)
        evidence.sessionID = run.id
        evidence.contentID = episode.id
        evidence.contentVersion = episode.version
        evidence.promptID = step.id
        evidence.kind = kind
        evidence.spokenWordCount = attempt?.spokenWordCount
        evidence.previousExposureAt = lastExposure
        // Repeating the same expression in the scene is practice, not a second
        // independent FSRS opportunity. A revealed answer never schedules Good.
        let alreadyScheduled = history.contains { $0.evidence?.sessionID == run.id && $0.evidence?.schedulingApplied == true }
        let shouldSchedule = attempt != nil && !supported && !alreadyScheduled
        evidence.schedulingApplied = shouldSchedule
        let review = Review(card: card, rating: attempt == nil ? 0 : correct ? 3 : 1,
            autoGradeRating: attempt == nil ? 0 : correct ? 3 : 1, userAnswer: "",
            mode: attempt == nil ? .chooseDeToRu : (attempt?.spoken == true ? .speakDeToRu : .typeDeToRu),
            responseTimeMs: 0, gradeTier: attempt == nil ? 0 : 1, wasNew: !card.hasBeenIntroduced)
        review.timestamp = now
        review.evidence = evidence
        if shouldSchedule { try SchedulerService().record(rating: correct ? 3 : 1, on: card, now: now) }
        context.insert(review)
    }

    enum VocabularyError: LocalizedError {
        case missingLanguage
        var errorDescription: String? { "Das Sprachpaket wird noch geladen. Bitte versuche es erneut." }
    }
}

enum ProductionFollowUp {
    /// An explicit queue projected from durable evidence, not from FSRS state.
    /// Later recognition cannot clear an outstanding productive opportunity.
    static func pending(_ reviews: [Review]) -> Bool {
        let ordered = reviews.sorted { $0.timestamp < $1.timestamp }
        var pending = false
        for review in ordered {
            guard let evidence = review.evidence else { continue }
            if evidence.support == .none && evidence.assessedCorrect && review.gradeTier > 0 {
                pending = false
            } else if evidence.kind == "exposure" || evidence.support != .none || !evidence.assessedCorrect {
                pending = true
            }
        }
        return pending
    }
}
