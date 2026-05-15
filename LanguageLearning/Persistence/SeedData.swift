import Foundation
import SwiftData

enum SeedData {
    /// Idempotent: every Phrase should have one StudyCard per CardDirection.
    /// When a new direction is added in a future build (e.g. `.flipDeToRu` in
    /// build 8) existing phrases are missing the new card — this backfills it
    /// so the new mode has content to schedule on first run.
    @discardableResult
    static func backfillMissingCards(_ context: ModelContext) -> Int {
        let phrases = (try? context.fetch(FetchDescriptor<Phrase>())) ?? []
        var added = 0
        for phrase in phrases {
            let existing = Set(phrase.cards.map(\.direction))
            for direction in CardDirection.allCases where !existing.contains(direction) {
                context.insert(StudyCard(phrase: phrase, direction: direction))
                added += 1
            }
        }
        if added > 0 { try? context.save() }
        return added
    }

    /// Inserts the default Russian language and the full starter pack on first
    /// launch with an empty store.
    static func seedIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Language>())) ?? []
        guard existing.isEmpty else { return }

        let russian = Language(code: "ru", name: "Русский")
        context.insert(russian)
        context.insert(AppSettings(activeLanguageCode: "ru"))

        _ = installStarterPack(into: context, language: russian)
        try? context.save()
    }

    /// Idempotent: ensures all supported languages have a `Language` record.
    /// On first launch only Russian is seeded; this function adds Arabic
    /// (and future languages) on later launches without disturbing existing
    /// Russian content. Active language stays whatever the user picked.
    @discardableResult
    static func ensureSupportedLanguages(_ context: ModelContext) -> Int {
        let existing = (try? context.fetch(FetchDescriptor<Language>())) ?? []
        let codes = Set(existing.map(\.code))
        var added = 0
        let supported: [(code: String, name: String, isRTL: Bool, translit: Bool)] = [
            ("ru", "Русский", false, true),
            ("ar", "العربية", true, true)
        ]
        for lang in supported where !codes.contains(lang.code) {
            context.insert(Language(
                code: lang.code,
                name: lang.name,
                isRTL: lang.isRTL,
                defaultTransliterationVisible: lang.translit
            ))
            added += 1
        }
        if added > 0 { try? context.save() }
        return added
    }

    /// Loads a level pack (A2/B1/B2) from the bundled OpenRussian.org dataset.
    /// CC BY-SA 4.0 — see `openrussian-vocab.json` for the source attribution.
    ///
    /// Phrases are split into POS-specific topics ("A2 Substantive", "A2
    /// Verben", "A2 Adjektive", "A2 Sonstige") rather than dumped into one
    /// big "Wortliste A2" bag — matches the grouping style of the curated
    /// starter pack.
    ///
    /// Idempotent: skips phrases that already exist by exact (`de`, `ru`)
    /// signature. Stress-marked Cyrillic goes into `transliteration` as a
    /// pronunciation hint; `targetText` stores the bare form so grading
    /// matches what the user actually types.
    @discardableResult
    static func addVocabLevel(
        _ context: ModelContext,
        level: String
    ) -> (phrasesAdded: Int, total: Int, topicAdded: Bool) {
        guard let entries = loadVocabPayload()?[level] else {
            return (0, 0, false)
        }

        let russian = ensureRussianLanguage(context: context)
        var topicCache = buildTopicCache(context: context)

        let existingPhrases = (try? context.fetch(FetchDescriptor<Phrase>())) ?? []
        var sigs = Set(existingPhrases.map { "\($0.sourceText)|||\($0.targetText)" })

        var added = 0
        var topicsAdded = 0
        for entry in entries {
            let signature = "\(entry.de)|||\(entry.ru)"
            guard !sigs.contains(signature) else { continue }
            sigs.insert(signature)

            let topicName = "\(level) \(posToGermanLabel(entry.pos))"
            let topicResult = ensureTopic(
                name: topicName,
                language: russian,
                context: context,
                cache: &topicCache
            )
            if topicResult.created { topicsAdded += 1 }

            let phrase = Phrase(
                sourceText: entry.de,
                targetText: entry.ru,
                language: russian,
                topics: [topicResult.topic],
                transliteration: entry.ru_a == entry.ru ? nil : entry.ru_a
            )
            context.insert(phrase)
            for direction in CardDirection.allCases {
                context.insert(StudyCard(phrase: phrase, direction: direction))
            }
            added += 1
        }
        try? context.save()
        return (added, entries.count, topicsAdded > 0)
    }

    /// One-shot migration from the old "Wortliste A2/B1/B2" mega-topics to
    /// the POS-split layout. For every phrase in an old "Wortliste X" topic,
    /// look up its part of speech in the bundled JSON, move it to "X POS",
    /// and delete the now-empty old topic.
    ///
    /// Idempotent: if no old topics exist, no-op. Safe to call on every launch.
    @discardableResult
    static func migrateVocabTopicsToPOS(_ context: ModelContext) -> Int {
        let allTopics = (try? context.fetch(FetchDescriptor<Topic>())) ?? []
        let oldTopics = allTopics.filter { $0.name.hasPrefix("Wortliste ") }
        guard !oldTopics.isEmpty else { return 0 }

        guard let payload = loadVocabPayload() else { return 0 }

        // Build ru-bare → pos lookup across all levels.
        var posByRu: [String: String] = [:]
        for (_, entries) in payload {
            for entry in entries { posByRu[entry.ru] = entry.pos }
        }

        let russian = ensureRussianLanguage(context: context)
        var topicCache = buildTopicCache(context: context)

        var movedPhrases = 0
        for oldTopic in oldTopics {
            let level = String(oldTopic.name.dropFirst("Wortliste ".count))
            let snapshot = oldTopic.phrases
            for phrase in snapshot {
                let pos = posByRu[phrase.targetText] ?? "other"
                let newTopicName = "\(level) \(posToGermanLabel(pos))"
                let newTopic = ensureTopic(
                    name: newTopicName,
                    language: russian,
                    context: context,
                    cache: &topicCache,
                    isActive: oldTopic.isActive
                ).topic

                // Detach from old topic, attach to new.
                phrase.topics.removeAll { $0.persistentModelID == oldTopic.persistentModelID }
                if !phrase.topics.contains(where: { $0.persistentModelID == newTopic.persistentModelID }) {
                    phrase.topics.append(newTopic)
                }
                movedPhrases += 1
            }
        }

        // Delete the old now-empty topics.
        for oldTopic in oldTopics where oldTopic.phrases.isEmpty {
            context.delete(oldTopic)
        }
        try? context.save()
        return movedPhrases
    }

    // MARK: - Vocab helpers

    private static func loadVocabPayload() -> [String: [VocabEntry]]? {
        guard
            let url = Bundle.main.url(forResource: "openrussian-vocab", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode([String: [VocabEntry]].self, from: data)
    }

    private static func ensureRussianLanguage(context: ModelContext) -> Language {
        let languages = (try? context.fetch(FetchDescriptor<Language>())) ?? []
        if let existing = languages.first(where: { $0.code == "ru" }) {
            return existing
        }
        let russian = Language(code: "ru", name: "Русский")
        context.insert(russian)
        return russian
    }

    private static func buildTopicCache(context: ModelContext) -> [String: Topic] {
        let existing = (try? context.fetch(FetchDescriptor<Topic>())) ?? []
        return Dictionary(uniqueKeysWithValues: existing.map { ($0.name, $0) })
    }

    private static func ensureTopic(
        name: String,
        language: Language,
        context: ModelContext,
        cache: inout [String: Topic],
        isActive: Bool = false
    ) -> (topic: Topic, created: Bool) {
        if let existing = cache[name] { return (existing, false) }
        let topic = Topic(name: name, language: language, isActive: isActive)
        context.insert(topic)
        cache[name] = topic
        return (topic, true)
    }

    /// Maps OpenRussian POS tags to German labels users will recognise.
    private static func posToGermanLabel(_ pos: String) -> String {
        switch pos.lowercased() {
        case "noun": return "Substantive"
        case "verb": return "Verben"
        case "adjective": return "Adjektive"
        case "pronoun": return "Pronomen"
        case "adverb": return "Adverbien"
        case "preposition": return "Präpositionen"
        case "conjunction": return "Konjunktionen"
        case "numeral", "number": return "Zahlwörter"
        default: return "Sonstige"
        }
    }

    private struct VocabEntry: Decodable {
        let ru: String
        let ru_a: String
        let de: String
        let pos: String
    }

    /// Idempotent: inserts any starter-pack phrases not already present in the
    /// store. Matches by exact `sourceText` + `targetText`. Reuses existing
    /// topics by name; creates new ones otherwise. Returns counts for UI feedback.
    @discardableResult
    static func addStarterPack(_ context: ModelContext) -> (phrasesAdded: Int, topicsAdded: Int) {
        let languages = (try? context.fetch(FetchDescriptor<Language>())) ?? []
        let russian: Language
        if let existing = languages.first(where: { $0.code == "ru" }) {
            russian = existing
        } else {
            russian = Language(code: "ru", name: "Русский")
            context.insert(russian)
        }
        let result = installStarterPack(into: context, language: russian)
        try? context.save()
        return result
    }

    // MARK: - Starter pack

    @discardableResult
    private static func installStarterPack(
        into context: ModelContext,
        language: Language
    ) -> (phrasesAdded: Int, topicsAdded: Int) {
        // Build topic cache from anything already in the DB so we don't
        // duplicate "Familie" if the user happened to create one.
        let existingTopics = (try? context.fetch(FetchDescriptor<Topic>())) ?? []
        var topicCache: [String: Topic] = Dictionary(uniqueKeysWithValues: existingTopics.map { ($0.name, $0) })
        var topicsAdded = 0

        for topicSpec in starterTopics where topicCache[topicSpec.name] == nil {
            let topic = Topic(
                name: topicSpec.name,
                language: language,
                isActive: topicSpec.initiallyActive
            )
            context.insert(topic)
            topicCache[topicSpec.name] = topic
            topicsAdded += 1
        }

        // Existing phrase signatures for dedupe.
        let existingPhrases = (try? context.fetch(FetchDescriptor<Phrase>())) ?? []
        var existingSignatures = Set(existingPhrases.map { "\($0.sourceText)|||\($0.targetText)" })

        var phrasesAdded = 0
        for spec in starterPhrases {
            let signature = "\(spec.de)|||\(spec.ru)"
            guard !existingSignatures.contains(signature) else { continue }
            existingSignatures.insert(signature)

            let topics = spec.topics.compactMap { topicCache[$0] }
            let phrase = Phrase(
                sourceText: spec.de,
                targetText: spec.ru,
                language: language,
                topics: topics
            )
            context.insert(phrase)
            for direction in CardDirection.allCases {
                context.insert(StudyCard(phrase: phrase, direction: direction))
            }
            phrasesAdded += 1
        }
        return (phrasesAdded, topicsAdded)
    }

    private struct StarterTopic {
        let name: String
        let initiallyActive: Bool
    }

    private struct StarterPhrase {
        let de: String
        let ru: String
        let topics: [String]
    }

    private static let starterTopics: [StarterTopic] = [
        .init(name: "Begrüßung", initiallyActive: true),
        .init(name: "Höflichkeit", initiallyActive: true),
        .init(name: "Verständigung", initiallyActive: true),
        .init(name: "Sich vorstellen", initiallyActive: false),
        .init(name: "Zahlen", initiallyActive: false),
        .init(name: "Wochentage", initiallyActive: false),
        .init(name: "Monate", initiallyActive: false),
        .init(name: "Zeit", initiallyActive: false),
        .init(name: "Familie", initiallyActive: false),
        .init(name: "Im Restaurant", initiallyActive: false),
        .init(name: "Wegbeschreibung", initiallyActive: false),
        .init(name: "Einkaufen", initiallyActive: false),
        .init(name: "Verben", initiallyActive: false),
        .init(name: "Adjektive", initiallyActive: false),
        .init(name: "Fragewörter", initiallyActive: false),
        .init(name: "Wetter", initiallyActive: false),
        .init(name: "Körperteile", initiallyActive: false),
        .init(name: "Essen & Trinken", initiallyActive: false),
        .init(name: "Kleidung", initiallyActive: false),
        .init(name: "Zuhause", initiallyActive: false),
        .init(name: "Farben", initiallyActive: false),
        .init(name: "Verkehr", initiallyActive: false),
        .init(name: "Allgemein", initiallyActive: false),
    ]

    private static let starterPhrases: [StarterPhrase] = [
        // Begrüßung
        .init(de: "Hallo.", ru: "Привет.", topics: ["Begrüßung"]),
        .init(de: "Guten Morgen.", ru: "Доброе утро.", topics: ["Begrüßung"]),
        .init(de: "Guten Tag.", ru: "Добрый день.", topics: ["Begrüßung"]),
        .init(de: "Guten Abend.", ru: "Добрый вечер.", topics: ["Begrüßung"]),
        .init(de: "Gute Nacht.", ru: "Спокойной ночи.", topics: ["Begrüßung"]),
        .init(de: "Auf Wiedersehen.", ru: "До свидания.", topics: ["Begrüßung"]),
        .init(de: "Tschüss.", ru: "Пока.", topics: ["Begrüßung"]),
        .init(de: "Bis bald.", ru: "До скорого.", topics: ["Begrüßung"]),
        .init(de: "Bis morgen.", ru: "До завтра.", topics: ["Begrüßung"]),

        // Höflichkeit
        .init(de: "Danke.", ru: "Спасибо.", topics: ["Höflichkeit"]),
        .init(de: "Vielen Dank.", ru: "Большое спасибо.", topics: ["Höflichkeit"]),
        .init(de: "Bitte.", ru: "Пожалуйста.", topics: ["Höflichkeit"]),
        .init(de: "Entschuldigung.", ru: "Извините.", topics: ["Höflichkeit"]),
        .init(de: "Es tut mir leid.", ru: "Мне жаль.", topics: ["Höflichkeit"]),
        .init(de: "Keine Ursache.", ru: "Не за что.", topics: ["Höflichkeit"]),
        .init(de: "Macht nichts.", ru: "Ничего страшного.", topics: ["Höflichkeit"]),

        // Verständigung
        .init(de: "Ich verstehe nicht.", ru: "Я не понимаю.", topics: ["Verständigung"]),
        .init(de: "Können Sie das wiederholen?", ru: "Можете повторить?", topics: ["Verständigung"]),
        .init(de: "Langsamer, bitte.", ru: "Помедленнее, пожалуйста.", topics: ["Verständigung"]),
        .init(de: "Sprechen Sie Englisch?", ru: "Вы говорите по-английски?", topics: ["Verständigung"]),
        .init(de: "Ich spreche ein bisschen Russisch.", ru: "Я немного говорю по-русски.", topics: ["Verständigung"]),
        .init(de: "Wie sagt man das auf Russisch?", ru: "Как это сказать по-русски?", topics: ["Verständigung"]),
        .init(de: "Ich weiß nicht.", ru: "Я не знаю.", topics: ["Verständigung"]),
        .init(de: "Ja.", ru: "Да.", topics: ["Verständigung"]),
        .init(de: "Nein.", ru: "Нет.", topics: ["Verständigung"]),

        // Sich vorstellen
        .init(de: "Wie heißt du?", ru: "Как тебя зовут?", topics: ["Sich vorstellen"]),
        .init(de: "Ich heiße Alex.", ru: "Меня зовут Алекс.", topics: ["Sich vorstellen"]),
        .init(de: "Sehr angenehm.", ru: "Очень приятно.", topics: ["Sich vorstellen"]),
        .init(de: "Woher kommst du?", ru: "Откуда ты?", topics: ["Sich vorstellen"]),
        .init(de: "Ich komme aus Deutschland.", ru: "Я из Германии.", topics: ["Sich vorstellen"]),
        .init(de: "Wo wohnst du?", ru: "Где ты живёшь?", topics: ["Sich vorstellen"]),
        .init(de: "Ich wohne in Berlin.", ru: "Я живу в Берлине.", topics: ["Sich vorstellen"]),
        .init(de: "Wie alt bist du?", ru: "Сколько тебе лет?", topics: ["Sich vorstellen"]),
        .init(de: "Ich bin dreißig Jahre alt.", ru: "Мне тридцать лет.", topics: ["Sich vorstellen"]),

        // Zahlen
        .init(de: "eins", ru: "один", topics: ["Zahlen"]),
        .init(de: "zwei", ru: "два", topics: ["Zahlen"]),
        .init(de: "drei", ru: "три", topics: ["Zahlen"]),
        .init(de: "vier", ru: "четыре", topics: ["Zahlen"]),
        .init(de: "fünf", ru: "пять", topics: ["Zahlen"]),
        .init(de: "sechs", ru: "шесть", topics: ["Zahlen"]),
        .init(de: "sieben", ru: "семь", topics: ["Zahlen"]),
        .init(de: "acht", ru: "восемь", topics: ["Zahlen"]),
        .init(de: "neun", ru: "девять", topics: ["Zahlen"]),
        .init(de: "zehn", ru: "десять", topics: ["Zahlen"]),

        // Wochentage
        .init(de: "Montag", ru: "понедельник", topics: ["Wochentage"]),
        .init(de: "Dienstag", ru: "вторник", topics: ["Wochentage"]),
        .init(de: "Mittwoch", ru: "среда", topics: ["Wochentage"]),
        .init(de: "Donnerstag", ru: "четверг", topics: ["Wochentage"]),
        .init(de: "Freitag", ru: "пятница", topics: ["Wochentage"]),
        .init(de: "Samstag", ru: "суббота", topics: ["Wochentage"]),
        .init(de: "Sonntag", ru: "воскресенье", topics: ["Wochentage"]),

        // Zeit
        .init(de: "heute", ru: "сегодня", topics: ["Zeit"]),
        .init(de: "morgen", ru: "завтра", topics: ["Zeit"]),
        .init(de: "gestern", ru: "вчера", topics: ["Zeit"]),
        .init(de: "jetzt", ru: "сейчас", topics: ["Zeit"]),
        .init(de: "später", ru: "позже", topics: ["Zeit"]),
        .init(de: "bald", ru: "скоро", topics: ["Zeit"]),
        .init(de: "Wie spät ist es?", ru: "Который час?", topics: ["Zeit"]),

        // Familie
        .init(de: "die Familie", ru: "семья", topics: ["Familie"]),
        .init(de: "die Mutter", ru: "мать", topics: ["Familie"]),
        .init(de: "der Vater", ru: "отец", topics: ["Familie"]),
        .init(de: "der Bruder", ru: "брат", topics: ["Familie"]),
        .init(de: "die Schwester", ru: "сестра", topics: ["Familie"]),
        .init(de: "der Sohn", ru: "сын", topics: ["Familie"]),
        .init(de: "die Tochter", ru: "дочь", topics: ["Familie"]),
        .init(de: "die Großmutter", ru: "бабушка", topics: ["Familie"]),
        .init(de: "der Großvater", ru: "дедушка", topics: ["Familie"]),

        // Im Restaurant
        .init(de: "Die Speisekarte, bitte.", ru: "Меню, пожалуйста.", topics: ["Im Restaurant"]),
        .init(de: "Ich möchte einen Kaffee, bitte.", ru: "Я хочу кофе, пожалуйста.", topics: ["Im Restaurant"]),
        .init(de: "Wasser, bitte.", ru: "Воду, пожалуйста.", topics: ["Im Restaurant"]),
        .init(de: "Eine Tasse Tee.", ru: "Чашку чая.", topics: ["Im Restaurant"]),
        .init(de: "Die Rechnung, bitte.", ru: "Счёт, пожалуйста.", topics: ["Im Restaurant"]),
        .init(de: "Es war lecker.", ru: "Было вкусно.", topics: ["Im Restaurant"]),
        .init(de: "Ich habe Hunger.", ru: "Я голоден.", topics: ["Im Restaurant"]),
        .init(de: "Ich habe Durst.", ru: "Я хочу пить.", topics: ["Im Restaurant"]),

        // Wegbeschreibung
        .init(de: "Wo ist die Toilette?", ru: "Где туалет?", topics: ["Wegbeschreibung"]),
        .init(de: "Wo ist der Bahnhof?", ru: "Где вокзал?", topics: ["Wegbeschreibung"]),
        .init(de: "links", ru: "налево", topics: ["Wegbeschreibung"]),
        .init(de: "rechts", ru: "направо", topics: ["Wegbeschreibung"]),
        .init(de: "geradeaus", ru: "прямо", topics: ["Wegbeschreibung"]),
        .init(de: "Wie komme ich dorthin?", ru: "Как туда добраться?", topics: ["Wegbeschreibung"]),

        // Einkaufen
        .init(de: "Wie viel kostet das?", ru: "Сколько это стоит?", topics: ["Einkaufen"]),
        .init(de: "Das ist zu teuer.", ru: "Это слишком дорого.", topics: ["Einkaufen"]),
        .init(de: "Haben Sie das?", ru: "У вас это есть?", topics: ["Einkaufen"]),
        .init(de: "Ich nehme das.", ru: "Я возьму это.", topics: ["Einkaufen"]),
        .init(de: "Kann ich mit Karte zahlen?", ru: "Можно оплатить картой?", topics: ["Einkaufen"]),
        .init(de: "Wo ist die Kasse?", ru: "Где касса?", topics: ["Einkaufen"]),

        // Zahlen 11-20 + Zehner
        .init(de: "elf", ru: "одиннадцать", topics: ["Zahlen"]),
        .init(de: "zwölf", ru: "двенадцать", topics: ["Zahlen"]),
        .init(de: "dreizehn", ru: "тринадцать", topics: ["Zahlen"]),
        .init(de: "vierzehn", ru: "четырнадцать", topics: ["Zahlen"]),
        .init(de: "fünfzehn", ru: "пятнадцать", topics: ["Zahlen"]),
        .init(de: "sechzehn", ru: "шестнадцать", topics: ["Zahlen"]),
        .init(de: "siebzehn", ru: "семнадцать", topics: ["Zahlen"]),
        .init(de: "achtzehn", ru: "восемнадцать", topics: ["Zahlen"]),
        .init(de: "neunzehn", ru: "девятнадцать", topics: ["Zahlen"]),
        .init(de: "zwanzig", ru: "двадцать", topics: ["Zahlen"]),
        .init(de: "dreißig", ru: "тридцать", topics: ["Zahlen"]),
        .init(de: "vierzig", ru: "сорок", topics: ["Zahlen"]),
        .init(de: "fünfzig", ru: "пятьдесят", topics: ["Zahlen"]),
        .init(de: "sechzig", ru: "шестьдесят", topics: ["Zahlen"]),
        .init(de: "siebzig", ru: "семьдесят", topics: ["Zahlen"]),
        .init(de: "achtzig", ru: "восемьдесят", topics: ["Zahlen"]),
        .init(de: "neunzig", ru: "девяносто", topics: ["Zahlen"]),
        .init(de: "hundert", ru: "сто", topics: ["Zahlen"]),
        .init(de: "tausend", ru: "тысяча", topics: ["Zahlen"]),

        // Monate
        .init(de: "Januar", ru: "январь", topics: ["Monate"]),
        .init(de: "Februar", ru: "февраль", topics: ["Monate"]),
        .init(de: "März", ru: "март", topics: ["Monate"]),
        .init(de: "April", ru: "апрель", topics: ["Monate"]),
        .init(de: "Mai", ru: "май", topics: ["Monate"]),
        .init(de: "Juni", ru: "июнь", topics: ["Monate"]),
        .init(de: "Juli", ru: "июль", topics: ["Monate"]),
        .init(de: "August", ru: "август", topics: ["Monate"]),
        .init(de: "September", ru: "сентябрь", topics: ["Monate"]),
        .init(de: "Oktober", ru: "октябрь", topics: ["Monate"]),
        .init(de: "November", ru: "ноябрь", topics: ["Monate"]),
        .init(de: "Dezember", ru: "декабрь", topics: ["Monate"]),

        // Verben (Infinitive)
        .init(de: "sein", ru: "быть", topics: ["Verben"]),
        .init(de: "haben", ru: "иметь", topics: ["Verben"]),
        .init(de: "machen", ru: "делать", topics: ["Verben"]),
        .init(de: "gehen", ru: "идти", topics: ["Verben"]),
        .init(de: "fahren", ru: "ехать", topics: ["Verben"]),
        .init(de: "kommen", ru: "приходить", topics: ["Verben"]),
        .init(de: "essen", ru: "есть", topics: ["Verben"]),
        .init(de: "trinken", ru: "пить", topics: ["Verben"]),
        .init(de: "schlafen", ru: "спать", topics: ["Verben"]),
        .init(de: "sehen", ru: "видеть", topics: ["Verben"]),
        .init(de: "hören", ru: "слышать", topics: ["Verben"]),
        .init(de: "sprechen", ru: "говорить", topics: ["Verben"]),
        .init(de: "lesen", ru: "читать", topics: ["Verben"]),
        .init(de: "schreiben", ru: "писать", topics: ["Verben"]),
        .init(de: "lernen", ru: "учить", topics: ["Verben"]),
        .init(de: "arbeiten", ru: "работать", topics: ["Verben"]),
        .init(de: "wohnen", ru: "жить", topics: ["Verben"]),
        .init(de: "wissen", ru: "знать", topics: ["Verben"]),
        .init(de: "denken", ru: "думать", topics: ["Verben"]),
        .init(de: "verstehen", ru: "понимать", topics: ["Verben"]),
        .init(de: "lieben", ru: "любить", topics: ["Verben"]),
        .init(de: "können", ru: "мочь", topics: ["Verben"]),
        .init(de: "wollen", ru: "хотеть", topics: ["Verben"]),
        .init(de: "kaufen", ru: "покупать", topics: ["Verben"]),
        .init(de: "geben", ru: "давать", topics: ["Verben"]),

        // Adjektive (maskuline Form Nominativ)
        .init(de: "gut", ru: "хороший", topics: ["Adjektive"]),
        .init(de: "schlecht", ru: "плохой", topics: ["Adjektive"]),
        .init(de: "groß", ru: "большой", topics: ["Adjektive"]),
        .init(de: "klein", ru: "маленький", topics: ["Adjektive"]),
        .init(de: "neu", ru: "новый", topics: ["Adjektive"]),
        .init(de: "alt", ru: "старый", topics: ["Adjektive"]),
        .init(de: "schön", ru: "красивый", topics: ["Adjektive"]),
        .init(de: "einfach", ru: "лёгкий", topics: ["Adjektive"]),
        .init(de: "schwierig", ru: "трудный", topics: ["Adjektive"]),
        .init(de: "schnell", ru: "быстрый", topics: ["Adjektive"]),
        .init(de: "langsam", ru: "медленный", topics: ["Adjektive"]),
        .init(de: "warm", ru: "тёплый", topics: ["Adjektive"]),
        .init(de: "kalt", ru: "холодный", topics: ["Adjektive"]),
        .init(de: "heiß", ru: "горячий", topics: ["Adjektive"]),
        .init(de: "billig", ru: "дешёвый", topics: ["Adjektive"]),
        .init(de: "teuer", ru: "дорогой", topics: ["Adjektive"]),
        .init(de: "lecker", ru: "вкусный", topics: ["Adjektive"]),
        .init(de: "müde", ru: "усталый", topics: ["Adjektive"]),
        .init(de: "glücklich", ru: "счастливый", topics: ["Adjektive"]),
        .init(de: "traurig", ru: "грустный", topics: ["Adjektive"]),

        // Fragewörter
        .init(de: "Was?", ru: "Что?", topics: ["Fragewörter"]),
        .init(de: "Wer?", ru: "Кто?", topics: ["Fragewörter"]),
        .init(de: "Wo?", ru: "Где?", topics: ["Fragewörter"]),
        .init(de: "Wohin?", ru: "Куда?", topics: ["Fragewörter"]),
        .init(de: "Wann?", ru: "Когда?", topics: ["Fragewörter"]),
        .init(de: "Warum?", ru: "Почему?", topics: ["Fragewörter"]),
        .init(de: "Wie?", ru: "Как?", topics: ["Fragewörter"]),
        .init(de: "Wie viel?", ru: "Сколько?", topics: ["Fragewörter"]),

        // Wetter
        .init(de: "Wie ist das Wetter?", ru: "Какая погода?", topics: ["Wetter"]),
        .init(de: "Es ist warm.", ru: "Тепло.", topics: ["Wetter"]),
        .init(de: "Es ist kalt.", ru: "Холодно.", topics: ["Wetter"]),
        .init(de: "Es ist heiß.", ru: "Жарко.", topics: ["Wetter"]),
        .init(de: "Es regnet.", ru: "Идёт дождь.", topics: ["Wetter"]),
        .init(de: "Es schneit.", ru: "Идёт снег.", topics: ["Wetter"]),
        .init(de: "Es ist sonnig.", ru: "Солнечно.", topics: ["Wetter"]),
        .init(de: "Es ist windig.", ru: "Ветрено.", topics: ["Wetter"]),

        // Körperteile
        .init(de: "der Kopf", ru: "голова", topics: ["Körperteile"]),
        .init(de: "die Hand", ru: "рука", topics: ["Körperteile"]),
        .init(de: "das Bein", ru: "нога", topics: ["Körperteile"]),
        .init(de: "das Auge", ru: "глаз", topics: ["Körperteile"]),
        .init(de: "das Ohr", ru: "ухо", topics: ["Körperteile"]),
        .init(de: "der Mund", ru: "рот", topics: ["Körperteile"]),
        .init(de: "die Nase", ru: "нос", topics: ["Körperteile"]),
        .init(de: "das Gesicht", ru: "лицо", topics: ["Körperteile"]),
        .init(de: "das Haar", ru: "волосы", topics: ["Körperteile"]),
        .init(de: "der Zahn", ru: "зуб", topics: ["Körperteile"]),

        // Essen & Trinken
        .init(de: "das Brot", ru: "хлеб", topics: ["Essen & Trinken"]),
        .init(de: "das Wasser", ru: "вода", topics: ["Essen & Trinken"]),
        .init(de: "der Kaffee", ru: "кофе", topics: ["Essen & Trinken"]),
        .init(de: "der Tee", ru: "чай", topics: ["Essen & Trinken"]),
        .init(de: "die Milch", ru: "молоко", topics: ["Essen & Trinken"]),
        .init(de: "der Käse", ru: "сыр", topics: ["Essen & Trinken"]),
        .init(de: "das Fleisch", ru: "мясо", topics: ["Essen & Trinken"]),
        .init(de: "der Fisch", ru: "рыба", topics: ["Essen & Trinken"]),
        .init(de: "der Apfel", ru: "яблоко", topics: ["Essen & Trinken"]),
        .init(de: "die Banane", ru: "банан", topics: ["Essen & Trinken"]),
        .init(de: "das Ei", ru: "яйцо", topics: ["Essen & Trinken"]),
        .init(de: "der Zucker", ru: "сахар", topics: ["Essen & Trinken"]),
        .init(de: "das Salz", ru: "соль", topics: ["Essen & Trinken"]),
        .init(de: "die Suppe", ru: "суп", topics: ["Essen & Trinken"]),
        .init(de: "das Bier", ru: "пиво", topics: ["Essen & Trinken"]),
        .init(de: "der Wein", ru: "вино", topics: ["Essen & Trinken"]),

        // Kleidung
        .init(de: "das Hemd", ru: "рубашка", topics: ["Kleidung"]),
        .init(de: "die Hose", ru: "брюки", topics: ["Kleidung"]),
        .init(de: "die Schuhe", ru: "обувь", topics: ["Kleidung"]),
        .init(de: "der Mantel", ru: "пальто", topics: ["Kleidung"]),
        .init(de: "die Mütze", ru: "шапка", topics: ["Kleidung"]),
        .init(de: "das Kleid", ru: "платье", topics: ["Kleidung"]),
        .init(de: "die Jacke", ru: "куртка", topics: ["Kleidung"]),

        // Zuhause
        .init(de: "das Haus", ru: "дом", topics: ["Zuhause"]),
        .init(de: "die Wohnung", ru: "квартира", topics: ["Zuhause"]),
        .init(de: "das Zimmer", ru: "комната", topics: ["Zuhause"]),
        .init(de: "die Küche", ru: "кухня", topics: ["Zuhause"]),
        .init(de: "das Badezimmer", ru: "ванная", topics: ["Zuhause"]),
        .init(de: "das Schlafzimmer", ru: "спальня", topics: ["Zuhause"]),
        .init(de: "das Fenster", ru: "окно", topics: ["Zuhause"]),
        .init(de: "die Tür", ru: "дверь", topics: ["Zuhause"]),
        .init(de: "der Tisch", ru: "стол", topics: ["Zuhause"]),
        .init(de: "der Stuhl", ru: "стул", topics: ["Zuhause"]),

        // Farben
        .init(de: "rot", ru: "красный", topics: ["Farben"]),
        .init(de: "blau", ru: "синий", topics: ["Farben"]),
        .init(de: "grün", ru: "зелёный", topics: ["Farben"]),
        .init(de: "gelb", ru: "жёлтый", topics: ["Farben"]),
        .init(de: "schwarz", ru: "чёрный", topics: ["Farben"]),
        .init(de: "weiß", ru: "белый", topics: ["Farben"]),
        .init(de: "grau", ru: "серый", topics: ["Farben"]),
        .init(de: "braun", ru: "коричневый", topics: ["Farben"]),

        // Verkehr
        .init(de: "das Auto", ru: "машина", topics: ["Verkehr"]),
        .init(de: "der Zug", ru: "поезд", topics: ["Verkehr"]),
        .init(de: "der Bus", ru: "автобус", topics: ["Verkehr"]),
        .init(de: "das Flugzeug", ru: "самолёт", topics: ["Verkehr"]),
        .init(de: "die U-Bahn", ru: "метро", topics: ["Verkehr"]),
        .init(de: "das Taxi", ru: "такси", topics: ["Verkehr"]),
        .init(de: "das Fahrrad", ru: "велосипед", topics: ["Verkehr"]),

        // Allgemein — useful everyday sentences
        .init(de: "Ich bin müde.", ru: "Я устал.", topics: ["Allgemein"]),
        .init(de: "Ich bin glücklich.", ru: "Я счастлив.", topics: ["Allgemein"]),
        .init(de: "Ich bin krank.", ru: "Я болен.", topics: ["Allgemein"]),
        .init(de: "Das ist gut.", ru: "Это хорошо.", topics: ["Allgemein"]),
        .init(de: "Das ist schlecht.", ru: "Это плохо.", topics: ["Allgemein"]),
        .init(de: "Sehr gut.", ru: "Очень хорошо.", topics: ["Allgemein"]),
        .init(de: "Ich liebe dich.", ru: "Я люблю тебя.", topics: ["Allgemein"]),
        .init(de: "Ich vermisse dich.", ru: "Я скучаю по тебе.", topics: ["Allgemein"]),
        .init(de: "Alles klar.", ru: "Всё понятно.", topics: ["Allgemein"]),
        .init(de: "Kein Problem.", ru: "Нет проблем.", topics: ["Allgemein"]),
        .init(de: "Wir sehen uns.", ru: "Увидимся.", topics: ["Allgemein"]),
        .init(de: "Viel Glück!", ru: "Удачи!", topics: ["Allgemein"]),
        .init(de: "Herzlichen Glückwunsch!", ru: "Поздравляю!", topics: ["Allgemein"]),
    ]
}
