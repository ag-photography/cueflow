import Foundation

struct LearningEpisode: Identifiable, Codable, Equatable, Sendable {
    struct Step: Identifiable, Codable, Equatable, Sendable {
        enum Kind: String, Codable { case model, recall, transfer }
        let id: String
        let kind: Kind
        let prompt: String
        let answer: String
        let alternatives: [String]
        let meaning: String
    }
    let id: String
    let version: Int
    let language: String
    let title: String
    let outcome: String
    let hook: String
    let symbol: String
    let interest: String
    let topicTags: [String]
    let steps: [Step]
    var estimatedSeconds: Int { steps.count * 20 }
    var uniqueExpressions: Int { Set(steps.map(\.answer)).count }
    var validationErrors: [String] {
        var errors: [String] = []
        if !["ru", "ar"].contains(language) { errors.append("Unsupported language") }
        if steps.isEmpty || !steps.contains(where: { $0.kind == .transfer }) { errors.append("Missing application") }
        if Set(steps.map(\.id)).count != steps.count { errors.append("Duplicate steps") }
        if steps.contains(where: { $0.prompt.isEmpty || $0.answer.isEmpty || $0.meaning.isEmpty }) { errors.append("Empty content") }
        return errors
    }
}

enum EpisodeLibrary {
    // Pilot material is explicitly marked as a preview in the UI until native review.
    static let all: [LearningEpisode] = [
        make("ru-seasons-1", "ru", "Dein erster Herbst-Smalltalk", "Sag, welche Jahreszeit du magst.",
             "Sascha plant einen Spaziergang. Welche Jahreszeit magst du?", "leaf.fill", "Menschen", ["Jahreszeiten", "Wetter"],
             "Ich mag den Herbst.", "Я люблю осень.", "Ich mag den Winter.", "Я люблю зиму."),
        make("ru-seasons-2", "ru", "Ein Plan für den Winter", "Sprich über das Wetter im Winter.",
             "Sascha packt für eine Reise. Was erwartet euch im Winter?", "snowflake", "Reisen", ["Jahreszeiten", "Wetter"],
             "Im Winter ist es kalt.", "Зимой холодно.", "Im Sommer ist es warm.", "Летом тепло."),
        make("ru-seasons-3", "ru", "Und warum?", "Begründe deine Lieblingsjahreszeit.",
             "Sascha fragt nach: Warum magst du den Sommer?", "sun.max.fill", "Menschen", ["Jahreszeiten", "Wetter"],
             "Ich mag den Sommer.", "Я люблю лето.", "Ich mag den Sommer, weil es warm ist.", "Я люблю лето, потому что тепло."),
        make("ru-cafe-1", "ru", "Dein Kaffee kommt gleich", "Bestelle höflich ein Getränk.",
             "Sascha wartet im Café. Heute bestellst du für euch.", "cup.and.saucer.fill", "Reisen", ["Im Restaurant", "Essen & Trinken"],
             "Einen Kaffee, bitte.", "Кофе, пожалуйста.", "Einen Tee, bitte.", "Чай, пожалуйста."),
        make("ru-meeting-1", "ru", "Das Gespräch beginnt", "Begrüße jemanden und frage nach.",
             "Sascha stellt dir einen Freund vor. Beginne das Gespräch.", "person.2.fill", "Menschen", ["Begrüßung", "Sich vorstellen"],
             "Hallo!", "Привет!", "Hallo! Wie geht es dir?", "Привет! Как дела?"),
        make("ru-work-1", "ru", "Eine kleine Rückfrage", "Bitte höflich um Wiederholung.",
             "Im Gespräch mit Sascha hast du etwas nicht verstanden. Frag nach.", "bubble.left.and.bubble.right.fill", "Beruf", ["Verständigung"],
             "Ich verstehe nicht.", "Я не понимаю.", "Wiederholen Sie bitte.", "Повторите, пожалуйста."),
        make("ar-seasons-1", "ar", "Deine Lieblingsjahreszeit", "Sprich über deine Lieblingsjahreszeit.",
             "Lina plant einen Ausflug. Welche Jahreszeit magst du?", "leaf.fill", "Menschen", ["Jahreszeiten", "Wetter"],
             "Ich mag den Frühling.", "أحب الربيع.", "Ich mag den Sommer.", "أحب الصيف."),
        make("ar-cafe-1", "ar", "Ein Getränk für Lina", "Bestelle höflich ein Getränk.",
             "Du triffst Lina im Café. Bestelle etwas zu trinken.", "cup.and.saucer.fill", "Reisen", ["Im Restaurant", "Essen & Trinken"],
             "Ich möchte einen Kaffee.", "أريد قهوة.", "Ich möchte einen Tee, bitte.", "أريد شايًا من فضلك."),
        make("ar-work-1", "ar", "Noch einmal, bitte", "Bitte um Wiederholung.",
             "Lina erzählt etwas. Du brauchst eine Wiederholung.", "bubble.left.and.bubble.right.fill", "Beruf", ["Verständigung"],
             "Ich verstehe nicht.", "لا أفهم.", "Wiederholen Sie bitte.", "كرر من فضلك.")
    ]

    private static func make(_ id: String, _ language: String, _ title: String, _ outcome: String,
                             _ hook: String, _ symbol: String, _ interest: String, _ tags: [String],
                             _ firstMeaning: String, _ first: String, _ secondMeaning: String, _ second: String) -> LearningEpisode {
        let contexts: [String: String] = [
            "ru-seasons-1": "Sascha liebt den Herbst. Du lieber die kalte Jahreszeit. Sage ihm: Ich mag den Winter.",
            "ru-seasons-2": "Eine Freundin packt einen dicken Mantel für Juli. Erkläre ihr: Im Sommer ist es warm.",
            "ru-seasons-3": "Sascha will wissen, warum du lieber im Juli reist. Erkläre: Ich mag den Sommer, weil es warm ist.",
            "ru-cafe-1": "Es gibt keinen Kaffee mehr. Bestelle stattdessen höflich einen Tee.",
            "ru-meeting-1": "Du siehst deinen Freund am nächsten Tag wieder. Begrüße ihn und frage, wie es ihm geht.",
            "ru-work-1": "Am Bahnhof hast du die Auskunft nicht verstanden. Bitte die Person höflich, sie zu wiederholen.",
            "ar-seasons-1": "Lina mag den Frühling. Du magst die heißere Jahreszeit. Sage: Ich mag den Sommer.",
            "ar-cafe-1": "Heute möchtest du keinen Kaffee. Sage höflich: Ich möchte einen Tee, bitte.",
            "ar-work-1": "Du verstehst die Auskunft eines Mannes am Bahnhof nicht. Bitte ihn auf Hocharabisch um Wiederholung."
        ]
        return .init(id: id, version: 1, language: language, title: title, outcome: outcome, hook: hook,
              symbol: symbol, interest: interest, topicTags: tags, steps: [
                .init(id: "model-a", kind: .model, prompt: "So kannst du es sagen", answer: first, alternatives: [], meaning: firstMeaning),
                .init(id: "model-b", kind: .model, prompt: "Eine zweite Möglichkeit", answer: second, alternatives: [], meaning: secondMeaning),
                .init(id: "recall-a", kind: .recall, prompt: firstMeaning, answer: first, alternatives: [], meaning: firstMeaning),
                .init(id: "recall-b", kind: .recall, prompt: secondMeaning, answer: second, alternatives: [], meaning: secondMeaning),
                .init(id: "apply", kind: .transfer, prompt: contexts[id] ?? secondMeaning, answer: second, alternatives: [], meaning: secondMeaning)
              ])
    }

    static func recommendation(language: String, purpose: String, focusNames: [String], completed: Set<String>) -> LearningEpisode? {
        let candidates = all.filter { $0.language == language && $0.validationErrors.isEmpty }
        let focus = focusNames.joined(separator: " ").lowercased()
        func score(_ episode: LearningEpisode) -> Int {
            (episode.topicTags.contains { focus.contains($0.lowercased()) } ? 10 : 0)
                + (episode.interest == purpose ? 2 : 0)
        }
        return candidates.enumerated().sorted {
            let leftDone = completed.contains($0.element.id), rightDone = completed.contains($1.element.id)
            if leftDone != rightDone { return !leftDone }
            let lhs = score($0.element), rhs = score($1.element)
            return lhs == rhs ? $0.offset < $1.offset : lhs > rhs
        }.first?.element
    }
}
