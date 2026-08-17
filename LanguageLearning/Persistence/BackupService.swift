import Foundation
import SwiftData

struct CueFlowBackup: Codable {
    static let currentVersion = 3

    let formatVersion: Int
    let exportedAt: Double
    let appVersion: String
    let languages: [LanguageRecord]
    let topics: [TopicRecord]
    let phrases: [PhraseRecord]
    let settings: SettingsRecord?

    struct LanguageRecord: Codable {
        let code: String
        let name: String
        let isRTL: Bool
        let defaultTransliterationVisible: Bool
    }

    struct TopicRecord: Codable {
        let name: String
        let languageCode: String
        let parentName: String?
        let isActive: Bool
    }

    struct PhraseRecord: Codable {
        let sourceText: String
        let targetText: String
        let languageCode: String
        let transliteration: String?
        let notes: String?
        let exampleSentence: String?
        let exampleSentenceTranslation: String?
        let exampleSentenceTransliteration: String?
        let acceptedAlternatives: [String]
        let topicNames: [String]
        let createdAt: Double
        let isPriority: Bool
        let priorityUntil: Double?
        let level: String?
        let phraseRegister: String?
        let dialect: String?
        let qualityStatus: String?
        let contentSource: String?
        let schedule: ScheduleRecord?
        let reviews: [ReviewRecord]
    }

    struct ScheduleRecord: Codable {
        let direction: String
        let stability: Double
        let difficulty: Double
        let dueDate: Double
        let lapses: Int
        let reps: Int
        let lastReview: Double?
        let state: String
    }

    struct ReviewRecord: Codable {
        let timestamp: Double
        let rating: Int
        let autoGradeRating: Int
        let userAnswer: String
        let mode: String
        let responseTimeMs: Int
        let gradeTier: Int
        let wasNew: Bool
    }

    struct SettingsRecord: Codable {
        let dailyNewLimit: Int
        let activeLanguageCode: String
        let transliterationVisible: Bool?
        let useAIGradingAssist: Bool
        let dailyReminderEnabled: Bool
        let dailyReminderHour: Int
        let dailyReminderMinute: Int
        let surpriseRewardsEnabled: Bool
        let hasCompletedOnboarding: Bool
    }
}

struct BackupImportSummary: Equatable {
    var languagesAdded = 0
    var topicsAdded = 0
    var phrasesAdded = 0
    var phrasesMerged = 0
    var reviewsAdded = 0
}

enum BackupServiceError: LocalizedError {
    case unsupportedVersion(Int)
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Diese Sicherung verwendet das nicht unterstützte Format \(version)."
        case .unreadableFile:
            return "Die Sicherungsdatei konnte nicht gelesen werden."
        }
    }
}

enum BackupService {
    static func makeBackup(
        languages: [Language],
        topics: [Topic],
        phrases: [Phrase],
        settings: AppSettings?,
        appVersion: String
    ) -> CueFlowBackup {
        CueFlowBackup(
            formatVersion: CueFlowBackup.currentVersion,
            exportedAt: Date.now.timeIntervalSince1970,
            appVersion: appVersion,
            languages: languages.map {
                .init(
                    code: $0.code,
                    name: $0.name,
                    isRTL: $0.isRTL,
                    defaultTransliterationVisible: $0.defaultTransliterationVisible
                )
            },
            topics: topics.compactMap { topic in
                guard let code = topic.language?.code else { return nil }
                return .init(
                    name: topic.name,
                    languageCode: code,
                    parentName: topic.parent?.name,
                    isActive: topic.isActive
                )
            },
            phrases: phrases.compactMap { phrase in
                guard let code = phrase.language?.code else { return nil }
                let card = phrase.cards?.max { $0.reps < $1.reps }
                return .init(
                    sourceText: phrase.sourceText,
                    targetText: phrase.targetText,
                    languageCode: code,
                    transliteration: phrase.transliteration,
                    notes: phrase.notes,
                    exampleSentence: phrase.exampleSentence,
                    exampleSentenceTranslation: phrase.exampleSentenceTranslation,
                    exampleSentenceTransliteration: phrase.exampleSentenceTransliteration,
                    acceptedAlternatives: phrase.acceptedAlternatives,
                    topicNames: (phrase.topics ?? []).map(\.name),
                    createdAt: phrase.createdAt.timeIntervalSince1970,
                    isPriority: phrase.isPriority,
                    priorityUntil: phrase.priorityUntil?.timeIntervalSince1970,
                    level: phrase.levelRaw,
                    phraseRegister: phrase.registerRaw,
                    dialect: phrase.dialect,
                    qualityStatus: phrase.qualityStatusRaw,
                    contentSource: phrase.contentSourceRaw,
                    schedule: card.map {
                        .init(
                            direction: $0.directionRaw,
                            stability: $0.stability,
                            difficulty: $0.difficulty,
                            dueDate: $0.dueDate.timeIntervalSince1970,
                            lapses: $0.lapses,
                            reps: $0.reps,
                            lastReview: $0.lastReview?.timeIntervalSince1970,
                            state: $0.stateRaw
                        )
                    },
                    reviews: (card?.reviews ?? []).map {
                        .init(
                            timestamp: $0.timestamp.timeIntervalSince1970,
                            rating: $0.rating,
                            autoGradeRating: $0.autoGradeRating,
                            userAnswer: $0.userAnswer,
                            mode: $0.modeRaw,
                            responseTimeMs: $0.responseTimeMs,
                            gradeTier: $0.gradeTier,
                            wasNew: $0.wasNew
                        )
                    }
                )
            },
            settings: settings.map {
                .init(
                    dailyNewLimit: $0.dailyNewLimit,
                    activeLanguageCode: $0.activeLanguageCode,
                    transliterationVisible: $0.transliterationVisible,
                    useAIGradingAssist: $0.useAIGradingAssist,
                    dailyReminderEnabled: $0.dailyReminderEnabled,
                    dailyReminderHour: $0.dailyReminderHour,
                    dailyReminderMinute: $0.dailyReminderMinute,
                    surpriseRewardsEnabled: $0.surpriseRewardsEnabled,
                    hasCompletedOnboarding: $0.hasCompletedOnboarding
                )
            }
        )
    }

    static func encode(_ backup: CueFlowBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    static func decode(_ data: Data, legacyLanguageCode: String = "ru") throws -> CueFlowBackup {
        let decoder = JSONDecoder()
        if let backup = try? decoder.decode(CueFlowBackup.self, from: data) {
            guard backup.formatVersion <= CueFlowBackup.currentVersion else {
                throw BackupServiceError.unsupportedVersion(backup.formatVersion)
            }
            return backup
        }
        return try decodeLegacy(data, languageCode: legacyLanguageCode)
    }

    @MainActor
    static func restore(_ backup: CueFlowBackup, into context: ModelContext) throws -> BackupImportSummary {
        guard backup.formatVersion <= CueFlowBackup.currentVersion else {
            throw BackupServiceError.unsupportedVersion(backup.formatVersion)
        }
        var summary = BackupImportSummary()
        var languages = Dictionary(uniqueKeysWithValues:
            try context.fetch(FetchDescriptor<Language>()).map { ($0.code, $0) }
        )
        for record in backup.languages where languages[record.code] == nil {
            let language = Language(
                code: record.code,
                name: record.name,
                isRTL: record.isRTL,
                defaultTransliterationVisible: record.defaultTransliterationVisible
            )
            context.insert(language)
            languages[record.code] = language
            summary.languagesAdded += 1
        }

        var topics = Dictionary(uniqueKeysWithValues:
            try context.fetch(FetchDescriptor<Topic>()).compactMap { topic -> (String, Topic)? in
                guard let code = topic.language?.code else { return nil }
                return (topicKey(code: code, name: topic.name), topic)
            }
        )
        for record in backup.topics {
            guard let language = languages[record.languageCode] else { continue }
            let key = topicKey(code: record.languageCode, name: record.name)
            if let existing = topics[key] {
                existing.isActive = existing.isActive || record.isActive
            } else {
                let topic = Topic(name: record.name, language: language, isActive: record.isActive)
                context.insert(topic)
                topics[key] = topic
                summary.topicsAdded += 1
            }
        }
        for record in backup.topics {
            guard let parentName = record.parentName,
                  let topic = topics[topicKey(code: record.languageCode, name: record.name)]
            else { continue }
            topic.parent = topics[topicKey(code: record.languageCode, name: parentName)]
        }

        var phrases = Dictionary(uniqueKeysWithValues:
            try context.fetch(FetchDescriptor<Phrase>()).compactMap { phrase -> (String, Phrase)? in
                guard let code = phrase.language?.code else { return nil }
                return (phraseKey(code: code, source: phrase.sourceText, target: phrase.targetText), phrase)
            }
        )

        for record in backup.phrases {
            guard let language = languages[record.languageCode] else { continue }
            let key = phraseKey(code: record.languageCode, source: record.sourceText, target: record.targetText)
            let phrase: Phrase
            let isNewPhrase: Bool
            if let existing = phrases[key] {
                phrase = existing
                isNewPhrase = false
                summary.phrasesMerged += 1
            } else {
                phrase = Phrase(
                    sourceText: record.sourceText,
                    targetText: record.targetText,
                    language: language,
                    transliteration: record.transliteration,
                    notes: record.notes
                )
                phrase.createdAt = Date(timeIntervalSince1970: record.createdAt)
                context.insert(phrase)
                context.insert(StudyCard(phrase: phrase))
                phrases[key] = phrase
                isNewPhrase = true
                summary.phrasesAdded += 1
            }
            merge(record, into: phrase, topics: topics, isNewPhrase: isNewPhrase)
            let card = phrase.cards?.first ?? {
                let card = StudyCard(phrase: phrase)
                context.insert(card)
                return card
            }()
            merge(record.schedule, into: card)
            var existingReviewKeys = Set((card.reviews ?? []).map(reviewKey))
            for reviewRecord in record.reviews where !existingReviewKeys.contains(reviewKey(reviewRecord)) {
                let mode = CardDirection(rawValue: reviewRecord.mode) ?? .speakDeToRu
                let review = Review(
                    card: card,
                    rating: reviewRecord.rating,
                    autoGradeRating: reviewRecord.autoGradeRating,
                    userAnswer: reviewRecord.userAnswer,
                    mode: mode,
                    responseTimeMs: reviewRecord.responseTimeMs,
                    gradeTier: reviewRecord.gradeTier,
                    wasNew: reviewRecord.wasNew
                )
                review.timestamp = Date(timeIntervalSince1970: reviewRecord.timestamp)
                context.insert(review)
                existingReviewKeys.insert(reviewKey(reviewRecord))
                summary.reviewsAdded += 1
            }
        }

        if let incoming = backup.settings {
            let settings = try context.fetch(FetchDescriptor<AppSettings>()).first ?? {
                let row = AppSettings()
                context.insert(row)
                return row
            }()
            settings.dailyNewLimit = incoming.dailyNewLimit
            if languages[incoming.activeLanguageCode] != nil {
                settings.activeLanguageCode = incoming.activeLanguageCode
            }
            settings.transliterationVisible = incoming.transliterationVisible
            settings.useAIGradingAssist = incoming.useAIGradingAssist
            settings.dailyReminderEnabled = incoming.dailyReminderEnabled
            settings.dailyReminderHour = incoming.dailyReminderHour
            settings.dailyReminderMinute = incoming.dailyReminderMinute
            settings.surpriseRewardsEnabled = incoming.surpriseRewardsEnabled
            settings.hasCompletedOnboarding = incoming.hasCompletedOnboarding
        }

        do {
            try context.save()
            return summary
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func merge(
        _ record: CueFlowBackup.PhraseRecord,
        into phrase: Phrase,
        topics: [String: Topic],
        isNewPhrase: Bool
    ) {
        if phrase.transliteration == nil { phrase.transliteration = record.transliteration }
        if phrase.notes == nil { phrase.notes = record.notes }
        if phrase.exampleSentence == nil { phrase.exampleSentence = record.exampleSentence }
        if phrase.exampleSentenceTranslation == nil {
            phrase.exampleSentenceTranslation = record.exampleSentenceTranslation
        }
        if phrase.exampleSentenceTransliteration == nil {
            phrase.exampleSentenceTransliteration = record.exampleSentenceTransliteration
        }
        phrase.acceptedAlternatives = Array(Set(phrase.acceptedAlternatives + record.acceptedAlternatives)).sorted()
        phrase.isPriority = phrase.isPriority || record.isPriority
        phrase.priorityUntil = [phrase.priorityUntil, record.priorityUntil.map(Date.init(timeIntervalSince1970:))]
            .compactMap { $0 }.max()
        if let level = record.level { phrase.levelRaw = level }
        if let phraseRegister = record.phraseRegister { phrase.registerRaw = phraseRegister }
        if let dialect = record.dialect, phrase.dialect.isEmpty { phrase.dialect = dialect }
        if let rawStatus = record.qualityStatus,
           let incomingStatus = PhraseQualityStatus(rawValue: rawStatus),
           isNewPhrase || incomingStatus.trustRank > phrase.qualityStatus.trustRank {
            phrase.qualityStatus = incomingStatus
        }
        if let rawSource = record.contentSource,
           let incomingSource = PhraseContentSource(rawValue: rawSource),
           isNewPhrase || incomingSource.provenanceRank > phrase.contentSource.provenanceRank {
            phrase.contentSource = incomingSource
        }
        let restoredTopics = record.topicNames.compactMap {
            topics[topicKey(code: record.languageCode, name: $0)]
        }
        let currentTopics = phrase.topics ?? []
        phrase.topics = Array(Set(currentTopics.map(\.persistentModelID)).union(restoredTopics.map(\.persistentModelID)))
            .compactMap { id in (currentTopics + restoredTopics).first { $0.persistentModelID == id } }
    }

    private static func merge(_ record: CueFlowBackup.ScheduleRecord?, into card: StudyCard) {
        guard let record else { return }
        let incomingLast = record.lastReview.map(Date.init(timeIntervalSince1970:))
        guard record.reps > card.reps || (incomingLast ?? .distantPast) > (card.lastReview ?? .distantPast)
        else { return }
        card.directionRaw = record.direction
        card.stability = record.stability
        card.difficulty = record.difficulty
        card.dueDate = Date(timeIntervalSince1970: record.dueDate)
        card.lapses = record.lapses
        card.reps = record.reps
        card.lastReview = incomingLast
        card.stateRaw = record.state
    }

    private static func topicKey(code: String, name: String) -> String {
        "\(code)|\(name.precomposedStringWithCanonicalMapping.lowercased())"
    }

    private static func phraseKey(code: String, source: String, target: String) -> String {
        "\(code)|\(Phrase.normalize(source))|\(Phrase.normalize(target))"
    }

    private static func reviewKey(_ review: Review) -> String {
        "\(review.timestamp.timeIntervalSince1970)|\(review.modeRaw)|\(review.userAnswer)|\(review.rating)"
    }

    private static func reviewKey(_ review: CueFlowBackup.ReviewRecord) -> String {
        "\(review.timestamp)|\(review.mode)|\(review.userAnswer)|\(review.rating)"
    }

    private struct LegacyBackup: Decodable {
        struct Topic: Decodable { let name: String; let isActive: Bool; let parent: String? }
        struct Phrase: Decodable {
            let sourceText: String; let targetText: String; let transliteration: String?
            let notes: String?; let topics: [String]; let acceptedAlternatives: [String]; let createdAt: Double
        }
        struct Review: Decodable {
            let cardId: String; let timestamp: Double; let rating: Int; let autoGradeRating: Int
            let userAnswer: String; let mode: String; let responseTimeMs: Int; let gradeTier: Int; let wasNew: Bool
        }
        let exportedAt: Double; let appVersion: String; let topics: [Topic]
        let phrases: [Phrase]; let reviews: [Review]; let settings: [String: String]
    }

    private static func decodeLegacy(_ data: Data, languageCode: String) throws -> CueFlowBackup {
        guard let legacy = try? JSONDecoder().decode(LegacyBackup.self, from: data) else {
            throw BackupServiceError.unreadableFile
        }
        let reviewsByTarget = Dictionary(grouping: legacy.reviews, by: { $0.cardId })
        return CueFlowBackup(
            formatVersion: 1,
            exportedAt: legacy.exportedAt,
            appVersion: legacy.appVersion,
            languages: [.init(
                code: languageCode,
                name: LanguagePack.configuration(for: languageCode)?.nativeName ?? languageCode,
                isRTL: LanguagePack.configuration(for: languageCode)?.isRTL ?? false,
                defaultTransliterationVisible: true
            )],
            topics: legacy.topics.map {
                .init(name: $0.name, languageCode: languageCode, parentName: $0.parent, isActive: $0.isActive)
            },
            phrases: legacy.phrases.map { phrase in
                let targetKey = Phrase.normalize(phrase.targetText)
                return .init(
                    sourceText: phrase.sourceText,
                    targetText: phrase.targetText,
                    languageCode: languageCode,
                    transliteration: phrase.transliteration,
                    notes: phrase.notes,
                    exampleSentence: nil,
                    exampleSentenceTranslation: nil,
                    exampleSentenceTransliteration: nil,
                    acceptedAlternatives: phrase.acceptedAlternatives,
                    topicNames: phrase.topics,
                    createdAt: phrase.createdAt,
                    isPriority: false,
                    priorityUntil: nil,
                    level: nil,
                    phraseRegister: nil,
                    dialect: nil,
                    qualityStatus: nil,
                    contentSource: nil,
                    schedule: nil,
                    reviews: (reviewsByTarget[targetKey] ?? []).map {
                        .init(
                            timestamp: $0.timestamp,
                            rating: $0.rating,
                            autoGradeRating: $0.autoGradeRating,
                            userAnswer: $0.userAnswer,
                            mode: $0.mode,
                            responseTimeMs: $0.responseTimeMs,
                            gradeTier: $0.gradeTier,
                            wasNew: $0.wasNew
                        )
                    }
                )
            },
            settings: .init(
                dailyNewLimit: Int(legacy.settings["dailyNewLimit"] ?? "") ?? 10,
                activeLanguageCode: legacy.settings["activeLanguageCode"] ?? languageCode,
                transliterationVisible: Bool(legacy.settings["transliterationVisible"] ?? ""),
                useAIGradingAssist: Bool(legacy.settings["useAIGradingAssist"] ?? "") ?? false,
                dailyReminderEnabled: false,
                dailyReminderHour: 19,
                dailyReminderMinute: 0,
                surpriseRewardsEnabled: true,
                hasCompletedOnboarding: true
            )
        )
    }
}
