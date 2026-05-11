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
}

enum CardDirection: String, Codable, CaseIterable {
    case typeDeToRu
    case speakDeToRu

    var displayName: String {
        switch self {
        case .typeDeToRu: return "Tippen"
        case .speakDeToRu: return "Sprechen"
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
    }
}
