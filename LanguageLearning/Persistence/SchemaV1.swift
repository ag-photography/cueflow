import Foundation
import SwiftData

/// Frozen Build 53 schema. Do not point these entries at the live model types:
/// migration needs the actual previous fields and relationships.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Language.self, Topic.self, Phrase.self, StudyCard.self, Review.self, Session.self, AppSettings.self]
    }

    @Model
    final class Language {
        var code: String = ""
        var name: String = ""
        var isRTL: Bool = false
        var defaultTransliterationVisible: Bool = true

        @Relationship(deleteRule: .cascade, inverse: \Phrase.language)
        var phrases: [Phrase]? = []

        @Relationship(deleteRule: .cascade, inverse: \Topic.language)
        var topics: [Topic]? = []

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

        var configuration: LanguagePack? { LanguagePack.configuration(for: code) }

        /// AVFoundation TTS locale identifier (e.g. "ru-RU", "ar-SA").
        var ttsLocale: String {
            configuration?.ttsLocale ?? code
        }

        /// SFSpeechRecognizer locale identifier.
        var speechLocale: String { configuration?.speechLocale ?? ttsLocale }

        /// User-facing German name (e.g. "Russisch", "Arabisch"). Distinct from
        /// `name` which holds the language's native name.
        var germanLabel: String {
            configuration?.germanLabel ?? (code == "de" ? "Deutsch" : name)
        }

        var inputPlaceholder: String { "Auf \(germanLabel) tippen…" }
    }

    @Model
    final class Topic {
        var name: String = ""
        var parent: Topic?
        var language: Language?
        var isActive: Bool = false
        /// Persistent lesson focus. Existing tutor-import topics are inferred as
        /// focused until the learner explicitly finishes them.
        var isTutorFocus: Bool = false
        var tutorFocusStartedAt: Date?
        var tutorFocusUntil: Date?
        var tutorNextLessonAt: Date?

        @Relationship(deleteRule: .nullify, inverse: \Topic.parent)
        var children: [Topic]? = []

        @Relationship(inverse: \Phrase.topics)
        var phrases: [Phrase]? = []

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

        var containsTutorMaterial: Bool {
            (phrases ?? []).contains { $0.contentSource == .tutorImport || $0.isPriority }
        }

        func isTutorFocusActive(at date: Date) -> Bool {
            guard isTutorFocus || containsTutorMaterial else { return false }
            guard let tutorFocusUntil else { return true }
            // Strictly greater: `finishTutorFocus` stamps `tutorFocusUntil = .now`,
            // so an inclusive comparison left the topic focused for whatever
            // remained of that instant — a race the tests could land on either side
            // of. "Focus ended at T" means not focused at T.
            return tutorFocusUntil > date
        }

        var isTutorFocusActive: Bool {
            isTutorFocusActive(at: .now)
        }

        func startTutorFocus(
            nextLessonAt: Date?,
            now: Date = .now,
            calendar: Calendar = .current
        ) {
            isTutorFocus = true
            isActive = true
            tutorFocusStartedAt = tutorFocusStartedAt ?? now
            tutorNextLessonAt = nextLessonAt
            tutorFocusUntil = nextLessonAt.flatMap {
                calendar.date(byAdding: .day, value: 7, to: $0)
            }
        }

        func finishTutorFocus() {
            isTutorFocus = false
            tutorFocusUntil = .now
            tutorNextLessonAt = nil
        }
    }

    @Model
    final class Phrase {
        var sourceText: String = ""
        var targetText: String = ""
        var targetTextNormalized: String = ""
        var transliteration: String?
        var notes: String?
        /// A short target-language sentence that *uses* this word, shown as a
        /// spoken "say it in a sentence" reinforcement while the card is still
        /// young (see `PracticeView` maturity gate). Populated from the bundled
        /// `example-sentences.json` at seed/backfill time; nil when we don't ship
        /// a sentence for this entry (e.g. the phrase already is a sentence, or
        /// it's user-imported vocab we haven't generated a sentence for). Optional
        /// + default nil → additive lightweight SwiftData migration, no version bump.
        var exampleSentence: String?
        /// German translation of `exampleSentence`.
        var exampleSentenceTranslation: String?
        /// Pronunciation reference for `exampleSentence`: stress-marked Cyrillic or
        /// Latin transliteration, depending on the target language. nil when not
        /// applicable.
        var exampleSentenceTransliteration: String?
        var audioFileName: String?
        var acceptedAlternatives: [String] = []
        var topics: [Topic]? = []
        var language: Language?
        var createdAt: Date = Date.now
        /// Homework boost: when a phrase is imported from a tutor lecture, mark
        /// it priority so the scheduler surfaces it ahead of regular vocab while
        /// the boost window is active.
        var isPriority: Bool = false
        /// Date after which the priority boost expires. nil = no boost. Defaults
        /// to ~2 weeks from import for lecture material.
        var priorityUntil: Date? = nil
        var levelRaw: String = PhraseLevel.unspecified.rawValue
        var registerRaw: String = PhraseRegister.neutral.rawValue
        var dialect: String = ""
        var qualityStatusRaw: String = PhraseQualityStatus.editorial.rawValue
        var contentSourceRaw: String = PhraseContentSource.bundled.rawValue

        @Relationship(deleteRule: .cascade, inverse: \StudyCard.phrase)
        var cards: [StudyCard]? = []

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

        /// Tutor lesson focus supersedes the legacy phrase-level 14-day flag.
        /// This keeps older imports working while allowing a lesson to remain in
        /// focus until it is completed or its configured consolidation window ends.
        var isTutorPriorityActive: Bool {
            isPriorityActive || (topics ?? []).contains(where: \.isTutorFocusActive)
        }

        var level: PhraseLevel {
            get { PhraseLevel(rawValue: levelRaw) ?? .unspecified }
            set { levelRaw = newValue.rawValue }
        }

        var phraseRegister: PhraseRegister {
            get { PhraseRegister(rawValue: registerRaw) ?? .neutral }
            set { registerRaw = newValue.rawValue }
        }

        var qualityStatus: PhraseQualityStatus {
            get { PhraseQualityStatus(rawValue: qualityStatusRaw) ?? .unreviewed }
            set { qualityStatusRaw = newValue.rawValue }
        }

        var contentSource: PhraseContentSource {
            get { PhraseContentSource(rawValue: contentSourceRaw) ?? .bundled }
            set { contentSourceRaw = newValue.rawValue }
        }
    }

    @Model
    final class StudyCard {
        var phrase: Phrase?
        /// Legacy storage retained for compatibility with existing stores.
        /// Scheduling is shared; the exercise used lives on `Review.modeRaw`.
        var directionRaw: String = CardDirection.speakDeToRu.rawValue
        var stability: Double = 0
        var difficulty: Double = 0
        var dueDate: Date = Date.now
        var lapses: Int = 0
        var reps: Int = 0
        var lastReview: Date?
        var stateRaw: String = LearningState.new.rawValue

        @Relationship(deleteRule: .cascade, inverse: \Review.card)
        var reviews: [Review]? = []

        var direction: CardDirection {
            get { CardDirection(rawValue: directionRaw) ?? .typeDeToRu }
            set { directionRaw = newValue.rawValue }
        }

        var state: LearningState {
            get { LearningState(rawValue: stateRaw) ?? .new }
            set { stateRaw = newValue.rawValue }
        }

        init(phrase: Phrase, direction: CardDirection = .speakDeToRu) {
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
        var timestamp: Date = Date.now
        var rating: Int = 0
        var autoGradeRating: Int = 0
        var userAnswer: String = ""
        var modeRaw: String = CardDirection.speakDeToRu.rawValue
        var responseTimeMs: Int = 0
        var gradeTier: Int = 0
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
        var startedAt: Date = Date.now
        var endedAt: Date?
        var cardsReviewed: Int = 0
        var correctCount: Int = 0

        init() {
            self.startedAt = .now
            self.endedAt = nil
            self.cardsReviewed = 0
            self.correctCount = 0
        }
    }

    @Model
    final class AppSettings {
        var dailyNewLimit: Int = 10
        var activeLanguageCode: String = "ru"
        var transliterationVisible: Bool?
        var useAIGradingAssist: Bool = false
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
}

enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Language.self, Topic.self, Phrase.self, StudyCard.self, Review.self, Session.self, AppSettings.self]
    }
}

enum LanguageLearningMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}
