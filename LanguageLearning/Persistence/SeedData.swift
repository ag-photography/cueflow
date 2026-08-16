import Foundation
import SwiftData

enum SeedData {
    /// Idempotent migration to one shared learning schedule per phrase.
    ///
    /// Older builds created a separate `StudyCard` for every exercise mode.
    /// Keep the most-established card, attach every historical review to it,
    /// and remove the duplicate schedules. The exercise used for each attempt
    /// remains preserved on `Review.modeRaw`.
    @discardableResult
    static func consolidateSharedCards(_ context: ModelContext) -> (created: Int, removed: Int) {
        let phrases = (try? context.fetch(FetchDescriptor<Phrase>())) ?? []
        var created = 0
        var removed = 0
        for phrase in phrases {
            let cards = phrase.cards
            guard !cards.isEmpty else {
                context.insert(StudyCard(phrase: phrase))
                created += 1
                continue
            }
            guard cards.count > 1 else { continue }

            let canonical = cards.max(by: sharedCardRanksBefore) ?? cards[0]
            for duplicate in cards where duplicate !== canonical {
                for review in Array(duplicate.reviews) {
                    review.card = canonical
                }
                context.delete(duplicate)
                removed += 1
            }
        }
        if created > 0 || removed > 0 { try? context.save() }
        return (created, removed)
    }

    /// Orders legacy schedules by the amount and recency of actual practice.
    /// Ties prefer Üben, the speaking-first default, for deterministic results.
    private static func sharedCardRanksBefore(_ lhs: StudyCard, _ rhs: StudyCard) -> Bool {
        if lhs.reps != rhs.reps { return lhs.reps < rhs.reps }
        let lhsLast = lhs.lastReview ?? .distantPast
        let rhsLast = rhs.lastReview ?? .distantPast
        if lhsLast != rhsLast { return lhsLast < rhsLast }
        if lhs.state != rhs.state {
            return sharedStateRank(lhs.state) < sharedStateRank(rhs.state)
        }
        return lhs.direction != .speakDeToRu && rhs.direction == .speakDeToRu
    }

    private static func sharedStateRank(_ state: LearningState) -> Int {
        switch state {
        case .new: return 0
        case .learning: return 1
        case .relearning: return 2
        case .review: return 3
        }
    }

    /// Idempotent: fills in `exampleSentence` (and its translation/transliteration)
    /// on any phrase that doesn't have one yet, from the bundled
    /// `example-sentences.json` (matched by `de|||target`). Lets returning users —
    /// whose phrases were seeded before this build, or before we shipped a
    /// sentence for that word — pick up sentences on launch without a reinstall.
    /// Only writes when it actually fills something in. Cheap: one fetch + an
    /// in-memory dictionary lookup per phrase.
    @discardableResult
    static func backfillExampleSentences(_ context: ModelContext) -> Int {
        let phrases = (try? context.fetch(FetchDescriptor<Phrase>())) ?? []
        var filled = 0
        for phrase in phrases where phrase.exampleSentence == nil {
            if ExampleSentences.apply(to: phrase) { filled += 1 }
        }
        if filled > 0 { try? context.save() }
        return filled
    }

    /// Idempotent: makes sure every piece of content that ships *inside* the
    /// app bundle is present in the store — A1 Russian + A1 Arabic curated
    /// packs and the full OpenRussian A2/B1/B2 wordlists. Topics are all
    /// inactive by default; the user activates what they want to drill in
    /// Library. Called on every launch — does work only on the first one
    /// (and after future content updates).
    static func ensureAllBundledContent(_ context: ModelContext) {
        _ = addStarterPack(context)        // RU A1 (~250 curated phrases)
        _ = addArabicStarter(context)       // AR A1 (~115 curated phrases)
        for level in ["A2", "B1", "B2"] {
            _ = addVocabLevel(context, level: level)   // OpenRussian per level
        }
    }

    /// Idempotent: marks anyone who was already using the app before the
    /// onboarding build (build 21) as having completed onboarding, so a
    /// TestFlight/App Store update doesn't drop returning users into the
    /// first-launch walkthrough.
    ///
    /// Heuristic: if the store already holds any `Review`, the user has
    /// practised before and is not a fresh install. A brand-new install has
    /// zero reviews, so its `AppSettings` row keeps `hasCompletedOnboarding =
    /// false` and the walkthrough shows. Runs every launch but only writes when
    /// it actually flips the flag.
    static func markExistingUsersOnboarded(_ context: ModelContext) {
        guard let settings = (try? context.fetch(FetchDescriptor<AppSettings>()))?.first else { return }
        guard !settings.hasCompletedOnboarding else { return }
        var reviewCount = FetchDescriptor<Review>()
        reviewCount.fetchLimit = 1
        let hasReviews = ((try? context.fetch(reviewCount)) ?? []).isEmpty == false
        if hasReviews {
            settings.hasCompletedOnboarding = true
            try? context.save()
        }
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
    /// Each entry is run through `PhraseClassifier` and dropped into the
    /// matching semantic topic (Familie, Verben, Essen & Trinken, …) — the
    /// same topic structure the curated starter pack uses. Entries the
    /// classifier can't place fall back to a bare POS bucket ("Substantive",
    /// "Verben", "Adjektive", …) so they're still groupable, just not
    /// semantically tagged.
    ///
    /// Idempotent: skips phrases that already exist by exact (`de`, `ru`)
    /// signature.
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

            let topicName = semanticTopicName(de: entry.de, ru: entry.ru, pos: entry.pos)
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
            ExampleSentences.apply(to: phrase)
            context.insert(phrase)
            context.insert(StudyCard(phrase: phrase))
            added += 1
        }
        try? context.save()
        return (added, entries.count, topicsAdded > 0)
    }

    /// One-shot migration from the POS-split level topics ("A2 Substantive",
    /// "B1 Verben", "B2 Adjektive", …) — introduced in build 10 — to semantic
    /// topics aligned with the curated starter pack. Each phrase gets
    /// reclassified via `PhraseClassifier`; unmappable phrases land in bare
    /// POS buckets ("Substantive", "Verben", …) so the user has fewer, more
    /// meaningful topics. Idempotent: no-op once migrated.
    @discardableResult
    static func migrateVocabTopicsToSemantic(_ context: ModelContext) -> Int {
        let allTopics = (try? context.fetch(FetchDescriptor<Topic>())) ?? []
        let levelPrefixes = ["A2 ", "B1 ", "B2 "]
        let oldTopics = allTopics.filter { topic in
            levelPrefixes.contains { topic.name.hasPrefix($0) }
        }
        guard !oldTopics.isEmpty else { return 0 }

        guard let payload = loadVocabPayload() else { return 0 }
        // ru-bare → pos lookup across all levels
        var posByRu: [String: String] = [:]
        for (_, entries) in payload {
            for entry in entries { posByRu[entry.ru] = entry.pos }
        }

        let russian = ensureRussianLanguage(context: context)
        var topicCache = buildTopicCache(context: context)

        var moved = 0
        for oldTopic in oldTopics {
            let snapshot = oldTopic.phrases
            for phrase in snapshot {
                let pos = posByRu[phrase.targetText] ?? "other"
                let newTopicName = semanticTopicName(
                    de: phrase.sourceText,
                    ru: phrase.targetText,
                    pos: pos
                )
                let newTopic = ensureTopic(
                    name: newTopicName,
                    language: russian,
                    context: context,
                    cache: &topicCache,
                    isActive: oldTopic.isActive
                ).topic
                phrase.topics.removeAll { $0.persistentModelID == oldTopic.persistentModelID }
                if !phrase.topics.contains(where: { $0.persistentModelID == newTopic.persistentModelID }) {
                    phrase.topics.append(newTopic)
                }
                moved += 1
            }
        }
        for oldTopic in oldTopics where oldTopic.phrases.isEmpty {
            context.delete(oldTopic)
        }
        try? context.save()
        return moved
    }

    /// Picks the topic name for a (de, ru, pos) triple: first tries
    /// PhraseClassifier (semantic), falls back to the bare POS label
    /// ("Substantive", "Verben", "Adjektive", …) if the classifier
    /// returns Allgemein — so unmapped vocab is grouped by POS rather
    /// than dumped into one giant Allgemein bucket.
    private static func semanticTopicName(de: String, ru: String, pos: String) -> String {
        let semantic = PhraseClassifier.classify(de: de, ru: ru)
        if semantic != "Allgemein" { return semantic }
        // Allgemein fallback → POS bucket for vocab that doesn't fit
        // a semantic group. Better than mega-Allgemein.
        return posToGermanLabel(pos)
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

    // MARK: - Arabic starter pack

    /// Idempotent A1 Arabic starter: ~120 phrases organised into topics,
    /// stored with Latin transliteration as `targetText` (the practice form,
    /// typeable with the default keyboard) and Arabic script in the
    /// `transliteration` field as a cultural reference shown below the answer.
    @discardableResult
    static func addArabicStarter(_ context: ModelContext) -> (phrasesAdded: Int, topicsAdded: Int) {
        let languages = (try? context.fetch(FetchDescriptor<Language>())) ?? []
        let arabic: Language
        if let existing = languages.first(where: { $0.code == "ar" }) {
            arabic = existing
        } else {
            arabic = Language(code: "ar", name: "العربية", isRTL: true, defaultTransliterationVisible: true)
            context.insert(arabic)
        }

        // Topic cache keyed by name (Arabic topic names are suffixed "(AR)"
        // to avoid collision with the Russian-language topics that use the
        // bare German names).
        let existingTopics = (try? context.fetch(FetchDescriptor<Topic>())) ?? []
        var topicCache: [String: Topic] = Dictionary(uniqueKeysWithValues: existingTopics.map { ($0.name, $0) })
        var topicsAdded = 0
        for spec in arabicStarterTopics where topicCache[spec.name] == nil {
            let topic = Topic(name: spec.name, language: arabic, isActive: spec.initiallyActive)
            context.insert(topic)
            topicCache[spec.name] = topic
            topicsAdded += 1
        }

        let existingPhrases = (try? context.fetch(FetchDescriptor<Phrase>())) ?? []
        var sigs = Set(existingPhrases.map { "\($0.sourceText)|||\($0.targetText)" })

        var added = 0
        for spec in arabicStarterPhrases {
            let signature = "\(spec.de)|||\(spec.translit)"
            guard !sigs.contains(signature) else { continue }
            sigs.insert(signature)

            let topics = spec.topics.compactMap { topicCache[$0] }
            let phrase = Phrase(
                sourceText: spec.de,
                targetText: spec.translit,       // Latin form — what the user types & is graded against
                language: arabic,
                topics: topics,
                transliteration: spec.script     // Arabic script — display reference under the answer
            )
            ExampleSentences.apply(to: phrase)
            context.insert(phrase)
            context.insert(StudyCard(phrase: phrase))
            added += 1
        }
        try? context.save()
        return (added, topicsAdded)
    }

    private struct ArabicTopic {
        let name: String
        let initiallyActive: Bool
    }

    private struct ArabicPhrase {
        let de: String
        let translit: String   // Latin transliteration (target for grading)
        let script: String     // Arabic script (shown below as reference)
        let topics: [String]
    }

    private static let arabicStarterTopics: [ArabicTopic] = [
        .init(name: "Begrüßung (AR)", initiallyActive: true),
        .init(name: "Höflichkeit (AR)", initiallyActive: true),
        .init(name: "Verständigung (AR)", initiallyActive: true),
        .init(name: "Sich vorstellen (AR)", initiallyActive: false),
        .init(name: "Zahlen (AR)", initiallyActive: false),
        .init(name: "Wochentage (AR)", initiallyActive: false),
        .init(name: "Familie (AR)", initiallyActive: false),
        .init(name: "Im Restaurant (AR)", initiallyActive: false),
        .init(name: "Wegbeschreibung (AR)", initiallyActive: false),
        .init(name: "Einkaufen (AR)", initiallyActive: false),
        .init(name: "Farben (AR)", initiallyActive: false),
        .init(name: "Verben (AR)", initiallyActive: false),
        .init(name: "Adjektive (AR)", initiallyActive: false),
        .init(name: "Fragewörter (AR)", initiallyActive: false)
    ]

    private static let arabicStarterPhrases: [ArabicPhrase] = [
        // Begrüßung
        .init(de: "Hallo.", translit: "marhaba", script: "مرحبا", topics: ["Begrüßung (AR)"]),
        .init(de: "Guten Morgen.", translit: "sabah al-khayr", script: "صباح الخير", topics: ["Begrüßung (AR)"]),
        .init(de: "Guten Abend.", translit: "masa al-khayr", script: "مساء الخير", topics: ["Begrüßung (AR)"]),
        .init(de: "Gute Nacht.", translit: "tusbih ala khayr", script: "تصبح على خير", topics: ["Begrüßung (AR)"]),
        .init(de: "Auf Wiedersehen.", translit: "ma'a as-salama", script: "مع السلامة", topics: ["Begrüßung (AR)"]),
        .init(de: "Bis morgen.", translit: "ila al-ghad", script: "إلى الغد", topics: ["Begrüßung (AR)"]),
        .init(de: "Friede sei mit dir.", translit: "as-salamu alaykum", script: "السلام عليكم", topics: ["Begrüßung (AR)"]),
        .init(de: "Und mit dir Friede.", translit: "wa alaykum as-salam", script: "وعليكم السلام", topics: ["Begrüßung (AR)"]),
        .init(de: "Willkommen.", translit: "ahlan wa sahlan", script: "أهلا وسهلا", topics: ["Begrüßung (AR)"]),

        // Höflichkeit
        .init(de: "Danke.", translit: "shukran", script: "شكرا", topics: ["Höflichkeit (AR)"]),
        .init(de: "Vielen Dank.", translit: "shukran jazilan", script: "شكرا جزيلا", topics: ["Höflichkeit (AR)"]),
        .init(de: "Bitte.", translit: "min fadlak", script: "من فضلك", topics: ["Höflichkeit (AR)"]),
        .init(de: "Bitte sehr.", translit: "afwan", script: "عفوا", topics: ["Höflichkeit (AR)"]),
        .init(de: "Entschuldigung.", translit: "aasif", script: "آسف", topics: ["Höflichkeit (AR)"]),
        .init(de: "Es tut mir leid.", translit: "ana aasif", script: "أنا آسف", topics: ["Höflichkeit (AR)"]),
        .init(de: "Macht nichts.", translit: "la ba's", script: "لا بأس", topics: ["Höflichkeit (AR)"]),

        // Verständigung
        .init(de: "Ja.", translit: "naam", script: "نعم", topics: ["Verständigung (AR)"]),
        .init(de: "Nein.", translit: "la", script: "لا", topics: ["Verständigung (AR)"]),
        .init(de: "Vielleicht.", translit: "rubbama", script: "ربما", topics: ["Verständigung (AR)"]),
        .init(de: "Ich verstehe nicht.", translit: "la afham", script: "لا أفهم", topics: ["Verständigung (AR)"]),
        .init(de: "Können Sie wiederholen?", translit: "mumkin tuid", script: "ممكن تعيد", topics: ["Verständigung (AR)"]),
        .init(de: "Langsamer, bitte.", translit: "ahdaa min fadlak", script: "أهدأ من فضلك", topics: ["Verständigung (AR)"]),
        .init(de: "Sprechen Sie Englisch?", translit: "hal tatakallam al-injliziyya", script: "هل تتكلم الإنجليزية", topics: ["Verständigung (AR)"]),
        .init(de: "Ich spreche ein bisschen Arabisch.", translit: "atakallam al-arabiyya qaleelan", script: "أتكلم العربية قليلا", topics: ["Verständigung (AR)"]),
        .init(de: "Wie heißt das auf Arabisch?", translit: "ma ismuhu bil arabiyya", script: "ما اسمه بالعربية", topics: ["Verständigung (AR)"]),
        .init(de: "Ich weiß nicht.", translit: "la a'rif", script: "لا أعرف", topics: ["Verständigung (AR)"]),

        // Sich vorstellen
        .init(de: "Wie heißt du?", translit: "ma ismuk", script: "ما اسمك", topics: ["Sich vorstellen (AR)"]),
        .init(de: "Ich heiße Alex.", translit: "ismi Alex", script: "اسمي أليكس", topics: ["Sich vorstellen (AR)"]),
        .init(de: "Sehr angenehm.", translit: "tasharrafna", script: "تشرفنا", topics: ["Sich vorstellen (AR)"]),
        .init(de: "Woher kommst du?", translit: "min ayna ant", script: "من أين أنت", topics: ["Sich vorstellen (AR)"]),
        .init(de: "Ich komme aus Deutschland.", translit: "ana min almaniya", script: "أنا من ألمانيا", topics: ["Sich vorstellen (AR)"]),
        .init(de: "Wo wohnst du?", translit: "ayna taskun", script: "أين تسكن", topics: ["Sich vorstellen (AR)"]),
        .init(de: "Ich wohne in Berlin.", translit: "askunu fi Berlin", script: "أسكن في برلين", topics: ["Sich vorstellen (AR)"]),
        .init(de: "Wie alt bist du?", translit: "kam umruk", script: "كم عمرك", topics: ["Sich vorstellen (AR)"]),
        .init(de: "Ich bin dreißig.", translit: "umri thalathuna", script: "عمري ثلاثون", topics: ["Sich vorstellen (AR)"]),

        // Zahlen 1-10
        .init(de: "eins", translit: "wahid", script: "واحد", topics: ["Zahlen (AR)"]),
        .init(de: "zwei", translit: "ithnan", script: "اثنان", topics: ["Zahlen (AR)"]),
        .init(de: "drei", translit: "thalatha", script: "ثلاثة", topics: ["Zahlen (AR)"]),
        .init(de: "vier", translit: "arba'a", script: "أربعة", topics: ["Zahlen (AR)"]),
        .init(de: "fünf", translit: "khamsa", script: "خمسة", topics: ["Zahlen (AR)"]),
        .init(de: "sechs", translit: "sitta", script: "ستة", topics: ["Zahlen (AR)"]),
        .init(de: "sieben", translit: "sab'a", script: "سبعة", topics: ["Zahlen (AR)"]),
        .init(de: "acht", translit: "thamaniya", script: "ثمانية", topics: ["Zahlen (AR)"]),
        .init(de: "neun", translit: "tis'a", script: "تسعة", topics: ["Zahlen (AR)"]),
        .init(de: "zehn", translit: "ashra", script: "عشرة", topics: ["Zahlen (AR)"]),

        // Wochentage
        .init(de: "Sonntag", translit: "al-ahad", script: "الأحد", topics: ["Wochentage (AR)"]),
        .init(de: "Montag", translit: "al-ithnayn", script: "الإثنين", topics: ["Wochentage (AR)"]),
        .init(de: "Dienstag", translit: "ath-thulatha", script: "الثلاثاء", topics: ["Wochentage (AR)"]),
        .init(de: "Mittwoch", translit: "al-arba'a", script: "الأربعاء", topics: ["Wochentage (AR)"]),
        .init(de: "Donnerstag", translit: "al-khamis", script: "الخميس", topics: ["Wochentage (AR)"]),
        .init(de: "Freitag", translit: "al-jum'a", script: "الجمعة", topics: ["Wochentage (AR)"]),
        .init(de: "Samstag", translit: "as-sabt", script: "السبت", topics: ["Wochentage (AR)"]),

        // Familie
        .init(de: "der Vater", translit: "ab", script: "أب", topics: ["Familie (AR)"]),
        .init(de: "die Mutter", translit: "umm", script: "أم", topics: ["Familie (AR)"]),
        .init(de: "der Bruder", translit: "akh", script: "أخ", topics: ["Familie (AR)"]),
        .init(de: "die Schwester", translit: "ukht", script: "أخت", topics: ["Familie (AR)"]),
        .init(de: "der Sohn", translit: "ibn", script: "ابن", topics: ["Familie (AR)"]),
        .init(de: "die Tochter", translit: "bint", script: "بنت", topics: ["Familie (AR)"]),
        .init(de: "der Großvater", translit: "jadd", script: "جد", topics: ["Familie (AR)"]),
        .init(de: "die Großmutter", translit: "jadda", script: "جدة", topics: ["Familie (AR)"]),
        .init(de: "die Familie", translit: "a'ila", script: "عائلة", topics: ["Familie (AR)"]),

        // Im Restaurant
        .init(de: "Die Speisekarte, bitte.", translit: "al-qa'ima min fadlak", script: "القائمة من فضلك", topics: ["Im Restaurant (AR)"]),
        .init(de: "Wasser, bitte.", translit: "ma' min fadlak", script: "ماء من فضلك", topics: ["Im Restaurant (AR)"]),
        .init(de: "Eine Tasse Kaffee.", translit: "finjan qahwa", script: "فنجان قهوة", topics: ["Im Restaurant (AR)"]),
        .init(de: "Tee, bitte.", translit: "shay min fadlak", script: "شاي من فضلك", topics: ["Im Restaurant (AR)"]),
        .init(de: "Die Rechnung, bitte.", translit: "al-hisab min fadlak", script: "الحساب من فضلك", topics: ["Im Restaurant (AR)"]),
        .init(de: "Es war lecker.", translit: "kana ladhidhan", script: "كان لذيذا", topics: ["Im Restaurant (AR)"]),
        .init(de: "Ich habe Hunger.", translit: "ana jaw'an", script: "أنا جوعان", topics: ["Im Restaurant (AR)"]),
        .init(de: "Ich habe Durst.", translit: "ana atshan", script: "أنا عطشان", topics: ["Im Restaurant (AR)"]),

        // Wegbeschreibung
        .init(de: "Wo ist die Toilette?", translit: "ayna al-hammam", script: "أين الحمام", topics: ["Wegbeschreibung (AR)"]),
        .init(de: "links", translit: "yasaar", script: "يسار", topics: ["Wegbeschreibung (AR)"]),
        .init(de: "rechts", translit: "yameen", script: "يمين", topics: ["Wegbeschreibung (AR)"]),
        .init(de: "geradeaus", translit: "ila al-amam", script: "إلى الأمام", topics: ["Wegbeschreibung (AR)"]),
        .init(de: "hier", translit: "huna", script: "هنا", topics: ["Wegbeschreibung (AR)"]),
        .init(de: "dort", translit: "hunaak", script: "هناك", topics: ["Wegbeschreibung (AR)"]),

        // Einkaufen
        .init(de: "Wie viel kostet das?", translit: "bikam", script: "بكم", topics: ["Einkaufen (AR)"]),
        .init(de: "Das ist zu teuer.", translit: "ghaali jiddan", script: "غالي جدا", topics: ["Einkaufen (AR)"]),
        .init(de: "Haben Sie das?", translit: "indak hadha", script: "عندك هذا", topics: ["Einkaufen (AR)"]),
        .init(de: "Ich nehme das.", translit: "aakhudhu hadha", script: "آخذ هذا", topics: ["Einkaufen (AR)"]),
        .init(de: "Wo ist der Markt?", translit: "ayna as-souq", script: "أين السوق", topics: ["Einkaufen (AR)"]),

        // Farben
        .init(de: "rot", translit: "ahmar", script: "أحمر", topics: ["Farben (AR)"]),
        .init(de: "blau", translit: "azraq", script: "أزرق", topics: ["Farben (AR)"]),
        .init(de: "grün", translit: "akhdar", script: "أخضر", topics: ["Farben (AR)"]),
        .init(de: "gelb", translit: "asfar", script: "أصفر", topics: ["Farben (AR)"]),
        .init(de: "schwarz", translit: "aswad", script: "أسود", topics: ["Farben (AR)"]),
        .init(de: "weiß", translit: "abyad", script: "أبيض", topics: ["Farben (AR)"]),

        // Verben (Past 3ms = dictionary form in MSA)
        .init(de: "essen", translit: "akala", script: "أكل", topics: ["Verben (AR)"]),
        .init(de: "trinken", translit: "shariba", script: "شرب", topics: ["Verben (AR)"]),
        .init(de: "gehen", translit: "dhahaba", script: "ذهب", topics: ["Verben (AR)"]),
        .init(de: "kommen", translit: "ja'a", script: "جاء", topics: ["Verben (AR)"]),
        .init(de: "sehen", translit: "ra'a", script: "رأى", topics: ["Verben (AR)"]),
        .init(de: "hören", translit: "sami'a", script: "سمع", topics: ["Verben (AR)"]),
        .init(de: "sprechen", translit: "takallama", script: "تكلم", topics: ["Verben (AR)"]),
        .init(de: "lesen", translit: "qara'a", script: "قرأ", topics: ["Verben (AR)"]),
        .init(de: "schreiben", translit: "kataba", script: "كتب", topics: ["Verben (AR)"]),
        .init(de: "lernen", translit: "ta'allama", script: "تعلم", topics: ["Verben (AR)"]),
        .init(de: "arbeiten", translit: "amila", script: "عمل", topics: ["Verben (AR)"]),
        .init(de: "schlafen", translit: "naama", script: "نام", topics: ["Verben (AR)"]),
        .init(de: "lieben", translit: "ahabba", script: "أحب", topics: ["Verben (AR)"]),
        .init(de: "wissen", translit: "arafa", script: "عرف", topics: ["Verben (AR)"]),

        // Adjektive
        .init(de: "gut", translit: "jayyid", script: "جيد", topics: ["Adjektive (AR)"]),
        .init(de: "schlecht", translit: "sayyi'", script: "سيء", topics: ["Adjektive (AR)"]),
        .init(de: "groß", translit: "kabir", script: "كبير", topics: ["Adjektive (AR)"]),
        .init(de: "klein", translit: "saghir", script: "صغير", topics: ["Adjektive (AR)"]),
        .init(de: "neu", translit: "jadid", script: "جديد", topics: ["Adjektive (AR)"]),
        .init(de: "alt", translit: "qadim", script: "قديم", topics: ["Adjektive (AR)"]),
        .init(de: "schön", translit: "jamil", script: "جميل", topics: ["Adjektive (AR)"]),
        .init(de: "einfach", translit: "sahl", script: "سهل", topics: ["Adjektive (AR)"]),
        .init(de: "schwierig", translit: "sa'b", script: "صعب", topics: ["Adjektive (AR)"]),
        .init(de: "warm", translit: "daafi", script: "دافئ", topics: ["Adjektive (AR)"]),
        .init(de: "kalt", translit: "barid", script: "بارد", topics: ["Adjektive (AR)"]),

        // Fragewörter
        .init(de: "Was?", translit: "ma", script: "ما", topics: ["Fragewörter (AR)"]),
        .init(de: "Wer?", translit: "man", script: "من", topics: ["Fragewörter (AR)"]),
        .init(de: "Wo?", translit: "ayna", script: "أين", topics: ["Fragewörter (AR)"]),
        .init(de: "Wann?", translit: "mata", script: "متى", topics: ["Fragewörter (AR)"]),
        .init(de: "Warum?", translit: "limadha", script: "لماذا", topics: ["Fragewörter (AR)"]),
        .init(de: "Wie?", translit: "kayfa", script: "كيف", topics: ["Fragewörter (AR)"]),
        .init(de: "Wie viel?", translit: "kam", script: "كم", topics: ["Fragewörter (AR)"])
    ]

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
            ExampleSentences.apply(to: phrase)
            context.insert(phrase)
            context.insert(StudyCard(phrase: phrase))
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
