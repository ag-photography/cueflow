import Foundation
import SwiftData
import Testing
@testable import LanguageLearning

@MainActor
struct BackupServiceTests {
    @Test func completeBackupRoundTripsAndRestoresIdempotently() throws {
        let source = try makeContext()
        let russian = Language(code: "ru", name: "Русский")
        let topic = Topic(name: "Im Café", language: russian, isActive: true)
        let phrase = Phrase(
            sourceText: "Einen Kaffee, bitte.",
            targetText: "Кофе, пожалуйста.",
            language: russian,
            topics: [topic],
            transliteration: "Kofe, požalujsta.",
            notes: "höflich"
        )
        phrase.acceptedAlternatives = ["Кофе пожалуйста"]
        phrase.level = .a1
        phrase.phraseRegister = .formal
        phrase.dialect = "Standardrussisch"
        phrase.qualityStatus = .nativeVerified
        phrase.contentSource = .manual
        let card = StudyCard(phrase: phrase)
        card.reps = 7
        card.state = .review
        card.stability = 8.5
        card.lastReview = Date(timeIntervalSince1970: 1_700_000_000)
        let review = Review(
            card: card,
            rating: 4,
            autoGradeRating: 4,
            userAnswer: phrase.targetText,
            mode: .speakDeToRu,
            responseTimeMs: 1_300,
            gradeTier: 3,
            wasNew: false
        )
        review.timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let settings = AppSettings(activeLanguageCode: "ru", transliterationVisible: true)
        settings.hasCompletedOnboarding = true
        source.insert(russian)
        source.insert(topic)
        source.insert(phrase)
        source.insert(card)
        source.insert(review)
        source.insert(settings)
        try source.save()

        let backup = BackupService.makeBackup(
            languages: [russian],
            topics: [topic],
            phrases: [phrase],
            settings: settings,
            appVersion: "1.0 (42)"
        )
        let decoded = try BackupService.decode(BackupService.encode(backup))
        let destination = try makeContext()

        let first = try BackupService.restore(decoded, into: destination)
        let second = try BackupService.restore(decoded, into: destination)

        #expect(first.languagesAdded == 1)
        #expect(first.topicsAdded == 1)
        #expect(first.phrasesAdded == 1)
        #expect(first.reviewsAdded == 1)
        #expect(second.phrasesAdded == 0)
        #expect(second.phrasesMerged == 1)
        #expect(second.reviewsAdded == 0)
        let restoredPhrases = try destination.fetch(FetchDescriptor<Phrase>())
        let restored = try #require(restoredPhrases.first)
        #expect(restored.transliteration == phrase.transliteration)
        #expect(restored.acceptedAlternatives == phrase.acceptedAlternatives)
        #expect(restored.topics?.first?.name == topic.name)
        #expect(restored.cards?.first?.reps == 7)
        #expect(restored.cards?.first?.reviews?.count == 1)
        #expect(restored.level == .a1)
        #expect(restored.phraseRegister == .formal)
        #expect(restored.dialect == "Standardrussisch")
        #expect(restored.qualityStatus == .nativeVerified)
        #expect(restored.contentSource == .manual)
        #expect(try destination.fetch(FetchDescriptor<AppSettings>()).first?.hasCompletedOnboarding == true)
    }

    @Test func decodesLegacyOneWayBackup() throws {
        let json = """
        {
          "exportedAt": 1700000000,
          "appVersion": "1.0 (38)",
          "topics": [{"name":"Café","isActive":true,"parent":null}],
          "phrases": [{
            "sourceText":"Kaffee", "targetText":"кофе", "transliteration":"kofe",
            "notes":null, "topics":["Café"], "acceptedAlternatives":[], "createdAt":1700000000
          }],
          "reviews": [{
            "cardId":"кофе", "timestamp":1700000001, "rating":4, "autoGradeRating":4,
            "userAnswer":"кофе", "mode":"speakDeToRu", "responseTimeMs":900,
            "gradeTier":3, "wasNew":false
          }],
          "settings": {"dailyNewLimit":"12", "activeLanguageCode":"ru", "useAIGradingAssist":"false"}
        }
        """

        let backup = try BackupService.decode(Data(json.utf8))

        #expect(backup.formatVersion == 1)
        #expect(backup.phrases.count == 1)
        #expect(backup.phrases.first?.reviews.count == 1)
        #expect(backup.settings?.dailyNewLimit == 12)
    }

    @Test func mergeDoesNotDowngradeVerifiedContentMetadata() throws {
        let source = try makeContext()
        let sourceLanguage = Language(code: "ru", name: "Русский")
        let imported = Phrase(sourceText: "Hallo", targetText: "Привет", language: sourceLanguage)
        imported.qualityStatus = .unreviewed
        imported.contentSource = .manual
        source.insert(sourceLanguage)
        source.insert(imported)
        source.insert(StudyCard(phrase: imported))
        try source.save()
        let backup = BackupService.makeBackup(
            languages: [sourceLanguage],
            topics: [],
            phrases: [imported],
            settings: nil,
            appVersion: "1.0"
        )

        let destination = try makeContext()
        let destinationLanguage = Language(code: "ru", name: "Русский")
        let verified = Phrase(sourceText: "Hallo", targetText: "Привет", language: destinationLanguage)
        verified.qualityStatus = .nativeVerified
        verified.contentSource = .bundled
        destination.insert(destinationLanguage)
        destination.insert(verified)
        destination.insert(StudyCard(phrase: verified))
        try destination.save()

        _ = try BackupService.restore(backup, into: destination)

        #expect(verified.qualityStatus == .nativeVerified)
        #expect(verified.contentSource == .bundled)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        return ModelContext(container)
    }
}
