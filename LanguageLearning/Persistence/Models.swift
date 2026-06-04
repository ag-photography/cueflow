import Foundation
import SwiftData

@Model
final class Language {
    @Attribute(.unique) var code: String
    var name: String
    var isRTL: Bool
    var defaultTransliterationVisible: Bool

    @Relationship(deleteRule: .cascade, inverse: \Phrase.language)
    var phrases: [Phrase] = []

    @Relationship(deleteRule: .cascade, inverse: \Topic.language)
    var topics: [Topic] = []

    init(
        code: String,
        name: String,
        isRTL: Bool = false,
        defaultTransliterationVisible: Bool = true
    ) {
        self.code = code
        self.name = name
        self.isRTL = isRTL
        self.defaultTransliterationVisible = defaultTransliterationVisible
    }

    /// AVFoundation TTS locale identifier (e.g. "ru-RU", "ar-SA").
    var ttsLocale: String {
        switch code {
        case "ru": return "ru-RU"
        case "ar": return "ar-SA"          // Modern Standard Arabic
        case "de": return "de-DE"
        default: return code
        }
    }

    /// SFSpeechRecognizer locale identifier.
    var speechLocale: String { ttsLocale }

    /// User-facing German name (e.g. "Russisch", "Arabisch"). Distinct from
    /// `name` which holds the language's native name.
    var germanLabel: String {
        switch code {
        case "ru": return "Russisch"
        case "ar": return "Arabisch"
        case "de": return "Deutsch"
        default: return name
        }
    }

    var inputPlaceholder: String { "Auf \(germanLabel) tippen…" }
}

@Model
final class Topic {
    var name: String
    var parent: Topic?
    var language: Language?
    var isActive: Bool

    @Relationship(deleteRule: .nullify, inverse: \Topic.parent)
    var children: [Topic] = []

    @Relationship(inverse: \Phrase.topics)
    var phrases: [Phrase] = []

    init(
        name: String,
        language: Language? = nil,
        parent: Topic? = nil,
        isActive: Bool = false
    ) {
        self.name = name
        self.language = language
        self.parent = parent
        self.isActive = isActive
    }
}

@Model
final class Phrase {
    var sourceText: String
    var targetText: String
    var targetTextNormalized: String
    var transliteration: String?
    var notes: String?
    var audioFileName: String?
    var acceptedAlternatives: [String] = []
    var topics: [Topic] = []
    var language: Language?
    var createdAt: Date
    /// Homework boost: when a phrase is imported from a tutor lecture, mark
    /// it priority so the scheduler surfaces it ahead of regular vocab while
    /// the boost window is active.
    var isPriority: Bool = false
    /// Date after which the priority boost expires. nil = no boost. Defaults
    /// to ~2 weeks from import for lecture material.
    var priorityUntil: Date? = nil

    @Relationship(deleteRule: .cascade, inverse: \StudyCard.phrase)
    var cards: [StudyCard] = []

    init(
        sourceText: String,
        targetText: String,
        language: Language? = nil,
        topics: [Topic] = [],
        transliteration: String? = nil,
        notes: String? = nil
    ) {
        self.sourceText = sourceText
        self.targetText = targetText
        self.targetTextNormalized = Phrase.normalize(targetText)
        self.transliteration = transliteration
        self.notes = notes
        self.topics = topics
        self.language = language
        self.createdAt = .now
    }

    static func normalize(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Is the priority flag still in effect (and not yet expired)? Computed,
    /// not persisted, so we don't need a daily cleanup job.
    var isPriorityActive: Bool {
        guard isPriority else { return false }
        if let until = priorityUntil, until < .now { return false }
        return true
    }
}

enum CardDirection: String, Codable, CaseIterable {
    case flipDeToRu       // recognition: tap to reveal, swipe to rate
    case chooseDeToRu     // recognition: pick the answer from 4 (no keyboard)
    case typeDeToRu       // "Üben": smart-mix — exercise varies by card maturity
                          // (new → multiple-choice, mature → typing), one schedule
    case speakDeToRu      // spoken production

    var displayName: String {
        switch self {
        case .flipDeToRu: return "Karten"
        case .chooseDeToRu: return "Wählen"
        case .typeDeToRu: return "Üben"
        case .speakDeToRu: return "Sprechen"
        }
    }

    var displayIcon: String {
        switch self {
        case .flipDeToRu: return "rectangle.on.rectangle"
        case .chooseDeToRu: return "checklist"
        case .typeDeToRu: return "graduationcap.fill"
        case .speakDeToRu: return "mic.fill"
        }
    }
}

enum LearningState: String, Codable {
    case new
    case learning
    case review
    case relearning
}

@Model
final class StudyCard {
    var phrase: Phrase?
    var directionRaw: String
    var stability: Double
    var difficulty: Double
    var dueDate: Date
    var lapses: Int
    var reps: Int
    var lastReview: Date?
    var stateRaw: String

    @Relationship(deleteRule: .cascade, inverse: \Review.card)
    var reviews: [Review] = []

    var direction: CardDirection {
        get { CardDirection(rawValue: directionRaw) ?? .typeDeToRu }
        set { directionRaw = newValue.rawValue }
    }

    var state: LearningState {
        get { LearningState(rawValue: stateRaw) ?? .new }
        set { stateRaw = newValue.rawValue }
    }

    init(phrase: Phrase, direction: CardDirection) {
        self.phrase = phrase
        self.directionRaw = direction.rawValue
        self.stability = 0
        self.difficulty = 0
        self.dueDate = .now
        self.lapses = 0
        self.reps = 0
        self.lastReview = nil
        self.stateRaw = LearningState.new.rawValue
    }
}

@Model
final class Review {
    var card: StudyCard?
    var timestamp: Date
    var rating: Int
    var autoGradeRating: Int
    var userAnswer: String
    var modeRaw: String
    var responseTimeMs: Int
    var gradeTier: Int
    var wasNew: Bool = false

    init(
        card: StudyCard,
        rating: Int,
        autoGradeRating: Int,
        userAnswer: String,
        mode: CardDirection,
        responseTimeMs: Int,
        gradeTier: Int,
        wasNew: Bool
    ) {
        self.card = card
        self.timestamp = .now
        self.rating = rating
        self.autoGradeRating = autoGradeRating
        self.userAnswer = userAnswer
        self.modeRaw = mode.rawValue
        self.responseTimeMs = responseTimeMs
        self.gradeTier = gradeTier
        self.wasNew = wasNew
    }
}

@Model
final class Session {
    var startedAt: Date
    var endedAt: Date?
    var cardsReviewed: Int
    var correctCount: Int

    init() {
        self.startedAt = .now
        self.endedAt = nil
        self.cardsReviewed = 0
        self.correctCount = 0
    }
}

@Model
final class AppSettings {
    var dailyNewLimit: Int
    var activeLanguageCode: String
    var transliterationVisible: Bool?
    var useAIGradingAssist: Bool
    // Daily reminder: defaults are off-and-7pm so a SwiftData lightweight
    // migration from earlier builds doesn't surprise existing users with a
    // notification — they have to opt in via Settings.
    var dailyReminderEnabled: Bool = false
    var dailyReminderHour: Int = 19
    var dailyReminderMinute: Int = 0
    // Last streak length that the user has been shown a milestone celebration
    // for. Prevents re-celebration when the user does multiple sessions on
    // the same milestone day.
    var lastCelebratedStreak: Int = 0
    // Variable-ratio reinforcement: roughly 1-in-8 correct answers trigger a
    // surprise praise banner. Defaults to on; can be disabled if it gets
    // distracting from the calm reading-app feel.
    var surpriseRewardsEnabled: Bool = true
    // First-launch onboarding gate. Defaults to false so a fresh install sees
    // the walkthrough. Existing users (anyone who already has reviews when they
    // update to the onboarding build) are flipped to true by
    // SeedData.markExistingUsersOnboarded so they don't get re-onboarded.
    var hasCompletedOnboarding: Bool = false
    // Developer tools (Diagnose/Telemetry) stay hidden until unlocked by
    // tapping the version footer in Settings. Off by default; persisted so it
    // survives across launches once unlocked.
    var developerModeEnabled: Bool = false

    init(
        dailyNewLimit: Int = 10,
        activeLanguageCode: String = "ru",
        transliterationVisible: Bool? = nil,
        useAIGradingAssist: Bool = false
    ) {
        self.dailyNewLimit = dailyNewLimit
        self.activeLanguageCode = activeLanguageCode
        self.transliterationVisible = transliterationVisible
        self.useAIGradingAssist = useAIGradingAssist
        self.dailyReminderEnabled = false
        self.dailyReminderHour = 19
        self.dailyReminderMinute = 0
        self.lastCelebratedStreak = 0
        self.surpriseRewardsEnabled = true
        self.hasCompletedOnboarding = false
        self.developerModeEnabled = false
    }
}
