import Foundation
import SwiftData

enum SeedData {
    /// Inserts the default Russian language, a few starter topics, and a handful
    /// of sample phrases the first time the app launches with an empty store.
    static func seedIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Language>())) ?? []
        guard existing.isEmpty else { return }

        let russian = Language(code: "ru", name: "Русский")
        context.insert(russian)

        let dailyLife = Topic(name: "Tägliches Leben", language: russian, isActive: true)
        let restaurant = Topic(name: "Im Restaurant", language: russian)
        let travel = Topic(name: "Reisen", language: russian)
        for topic in [dailyLife, restaurant, travel] {
            context.insert(topic)
        }

        let samples: [(de: String, ru: String, topics: [Topic])] = [
            ("Ich möchte einen Kaffee, bitte.", "Я хочу кофе, пожалуйста.", [dailyLife, restaurant]),
            ("Wie viel kostet das?", "Сколько это стоит?", [dailyLife, restaurant]),
            ("Wo ist der Bahnhof?", "Где вокзал?", [travel]),
            ("Ich verstehe nicht.", "Я не понимаю.", [dailyLife]),
            ("Können Sie das bitte wiederholen?", "Можете это повторить, пожалуйста?", [dailyLife]),
        ]

        for sample in samples {
            let phrase = Phrase(
                sourceText: sample.de,
                targetText: sample.ru,
                language: russian,
                topics: sample.topics
            )
            context.insert(phrase)
            for direction in CardDirection.allCases {
                context.insert(StudyCard(phrase: phrase, direction: direction))
            }
        }

        context.insert(AppSettings(activeLanguageCode: "ru"))

        try? context.save()
    }
}
