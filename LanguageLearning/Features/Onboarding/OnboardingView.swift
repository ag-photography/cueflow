import SwiftUI
import SwiftData
import UIKit

/// First-launch walkthrough (build 21; made language-agnostic in build 26). A
/// small, paged flow that introduces the app, lets the user pick which language
/// to learn, sets a daily goal, activates a few starter topics, and — only for
/// languages typed in a non-Latin script — walks through installing the
/// keyboard. Adult tone — no mascots, no pressure — and every choice has a
/// sensible default so "Überspringen" is always safe.
///
/// Shown two ways:
///   • First launch — RootView renders this when `hasCompletedOnboarding` is
///     false. `finish()` flips the flag and RootView swaps to PracticeView.
///   • Replay — Settings presents it as a fullScreenCover; `finish()` calls
///     `dismiss()` to close the cover. The flag is already true, so re-running
///     it just re-applies the chosen goal/topics (non-destructive).
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [AppSettings]
    @Query private var topics: [Topic]
    @Query private var languages: [Language]

    @State private var index = 0
    @State private var selectedLanguageCode = ""        // "" until hydrated
    @State private var selectedDailyLimit = 10
    @State private var selectedTopicIDs: Set<PersistentIdentifier> = []
    @State private var didHydrate = false
    @State private var selectedPurpose = "Reisen"
    @State private var firstSpeechSucceeded = false
    @State private var firstSpeechUnavailable = false
    @State private var onboardingSpeechGeneration = UUID()
    @StateObject private var speech = SpeechRecognitionService()

    /// Curated beginner topics offered on the topic-selection page. A small,
    /// inviting subset — the full library (incl. A2/B1/B2 vocab) stays one tap
    /// away in the Library. Order here is the display order.
    private let starterTopicNames = [
        "Begrüßung", "Höflichkeit", "Verständigung", "Sich vorstellen",
        "Zahlen", "Familie", "Essen & Trinken", "Im Restaurant",
    ]

    private let dailyOptions: [(limit: Int, title: String, blurb: String)] = [
        (5, "Entspannt", "Ein paar Minuten am Tag."),
        (10, "Empfohlen", "Guter Rhythmus für die meisten."),
        (15, "Ehrgeizig", "Schneller vorankommen."),
        (20, "Intensiv", "Viel Zeit, viel Fortschritt."),
    ]

    // MARK: - Page model

    private enum Page: Hashable { case welcome, languageAndPurpose, firstSuccess, personalize }

    /// Languages the user can learn (everything except German, the UI language).
    private var learnableLanguages: [Language] {
        languages
            .filter { $0.code != "de" }
            .sorted { $0.germanLabel.localizedCompare($1.germanLabel) == .orderedAscending }
    }

    /// The keyboard page only appears when the active language's practice target
    /// is written in a non-Latin script. Data-driven so Russian, Arabic, and a
    /// future language slot in without language-specific branching.
    private var needsKeyboardSetup: Bool {
        guard let lang = activeLanguage else { return false }
        let sample = lang.phrases.first { !$0.targetText.isEmpty }?.targetText ?? ""
        // Anything above the combining-marks block (U+036F) is non-Latin here —
        // Cyrillic (U+0400+), Arabic (U+0600+), etc. Latin (incl. accented
        // transliteration) stays below it.
        return sample.unicodeScalars.contains { $0.value > 0x036F && CharacterSet.letters.contains($0) }
    }

    private var pages: [Page] {
        [.welcome, .languageAndPurpose, .firstSuccess, .personalize]
    }

    private var isLastPage: Bool { index >= pages.count - 1 }

    /// Reflects the in-flight language choice immediately (before `finish()`
    /// writes it), so the topic page and keyboard gating react as the user picks.
    private var activeCode: String {
        selectedLanguageCode.isEmpty ? (settings.first?.activeLanguageCode ?? "ru") : selectedLanguageCode
    }

    private var activeLanguage: Language? {
        languages.first { $0.code == activeCode }
    }

    /// Curated starter topics that exist for the active language, in
    /// `starterTopicNames` order. Topics for non-default languages carry a
    /// " (XX)" suffix (e.g. "Begrüßung (AR)") to avoid name collisions, so we
    /// match on the base name — the same curated set works for every language.
    private var shownTopics: [Topic] {
        let inLang = topics.filter { $0.language?.code == activeCode }
        let byBase = Dictionary(inLang.map { (Self.baseTopicName($0.name), $0) },
                                uniquingKeysWith: { a, _ in a })
        return starterTopicNames.compactMap { byBase[$0] }
    }

    /// Strips a trailing " (XX)" language suffix so "Begrüßung (AR)" → "Begrüßung".
    private static func baseTopicName(_ name: String) -> String {
        name.replacingOccurrences(
            of: #"\s*\([A-Z]{2}\)$"#, with: "", options: .regularExpression
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            topBar
            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.element) { i, page in
                    pageBody(page)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: index)
            bottomBar
        }
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .background(DS.surface0.ignoresSafeArea())
        .onAppear(perform: hydrateOnce)
        .onChange(of: selectedLanguageCode) { _, _ in
            // New language → its starter topics differ, so re-seed the picks.
            rehydrateTopicSelection()
            firstSpeechSucceeded = false
            firstSpeechUnavailable = false
            speech.stop()
            if let locale = activeLanguage?.speechLocale { speech.setLocale(locale) }
        }
        .onChange(of: index) { _, newIndex in
            guard pages.indices.contains(newIndex), pages[newIndex] != .firstSuccess else { return }
            onboardingSpeechGeneration = UUID()
            speech.stop()
            TTSService.shared.stop()
        }
        .onChange(of: speech.transcription) { _, newValue in
            guard let phrase = firstPhrase, !firstSpeechSucceeded else { return }
            if SprintMatcher.matches(spokenTail: newValue, target: phrase.targetText) {
                firstSpeechSucceeded = true
                speech.stop()
                CompletionFeedbackService.shared.playCompletion()
            }
        }
        .onDisappear {
            onboardingSpeechGeneration = UUID()
            speech.stop()
            TTSService.shared.stop()
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            if index > 0 {
                Button {
                    withAnimation { index -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .foregroundStyle(DS.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zurück")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            Spacer()
            if index > 0 && !isLastPage {
                Button("Später") { finish() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, DS.space.sm)
            }
        }
        .padding(.horizontal, DS.space.sm)
        .padding(.top, DS.space.sm)
    }

    private var bottomBar: some View {
        VStack(spacing: DS.space.md) {
            pageDots
            Button {
                if isLastPage {
                    finish()
                } else {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation { index += 1 }
                }
            } label: {
                Text(isLastPage ? "Erste Einheit starten" : "Weiter")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Capsule().fill(DS.accent))
                    .shadow(color: DS.accent.opacity(0.30), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.space.lg)
        .padding(.top, DS.space.sm)
        .padding(.bottom, DS.space.md)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<pages.count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? DS.accent : DS.textTertiary.opacity(0.4))
                    .frame(width: i == index ? 22 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: index)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Pages

    @ViewBuilder
    private func pageBody(_ page: Page) -> some View {
        switch page {
        case .welcome:    welcomePage
        case .languageAndPurpose: languageAndPurposePage
        case .firstSuccess: firstSuccessPage
        case .personalize: personalizePage
        }
    }

    private var welcomePage: some View {
        VStack(spacing: DS.space.xl) {
            Spacer()
            brandBadge
            VStack(spacing: DS.space.md) {
                Text("Willkommen bei\nCueFlow")
                    .font(.system(size: 40, weight: .bold, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DS.textPrimary)
                Text("Hol die richtigen Wörter selbst hervor — und sprich sie aus. So wird aus Verstehen echte Gesprächsfähigkeit.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, DS.space.md)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, DS.space.lg)
    }

    private var languageAndPurposePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space.lg) {
                pageHeader(
                    title: "Wofür willst du sprechen?",
                    subtitle: "Wähle deine Sprache und den Moment, für den du sie brauchst."
                )
                VStack(spacing: DS.space.sm) {
                    ForEach(learnableLanguages, id: \.code) { lang in
                        languageOptionRow(lang)
                    }
                }
                Text("Mein Ziel")
                    .font(.headline)
                    .foregroundStyle(DS.textPrimary)
                HStack(spacing: DS.space.sm) {
                    ForEach(["Reisen", "Menschen", "Beruf"], id: \.self) { purpose in
                        Button(purpose) { selectedPurpose = purpose }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedPurpose == purpose ? .white : DS.textPrimary)
                            .padding(.horizontal, DS.space.md)
                            .frame(minHeight: 44)
                            .background(selectedPurpose == purpose ? DS.accent : DS.surface1)
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selectedPurpose == purpose ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal, DS.space.lg)
            .padding(.bottom, DS.space.lg)
        }
    }

    private var firstPhrase: Phrase? {
        shownTopics.lazy.flatMap(\.phrases).first(where: { !$0.targetText.isEmpty })
            ?? activeLanguage?.phrases.first(where: { !$0.targetText.isEmpty })
    }

    private var firstSuccessPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space.lg) {
                pageHeader(
                    title: "Dein erster Satz",
                    subtitle: "Hör ihn einmal. Dann sag ihn selbst — die Verarbeitung bleibt auf deinem Gerät."
                )
                if let phrase = firstPhrase {
                    VStack(spacing: DS.space.md) {
                        Text(phrase.sourceText)
                            .font(.subheadline)
                            .foregroundStyle(DS.textSecondary)
                        Text(phrase.targetText)
                            .font(.system(size: 34, weight: .bold, design: .serif))
                            .multilineTextAlignment(.center)
                            .environment(\.layoutDirection, phrase.language?.code == "ar" ? .rightToLeft : .leftToRight)
                            .foregroundStyle(DS.textPrimary)
                        Button {
                            TTSService.shared.speak(
                                phrase.targetText,
                                language: phrase.language?.ttsLocale ?? "ru-RU"
                            )
                        } label: {
                            Label("Anhören", systemImage: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(DS.accent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.space.xl)
                    .padding(.horizontal, DS.space.md)
                    .dsFlashcardSurface()

                    Button {
                        if speech.isRecording {
                            onboardingSpeechGeneration = UUID()
                            speech.stop()
                        } else {
                            startFirstSpeech()
                        }
                    } label: {
                        Label(
                            firstSpeechSucceeded ? "Geschafft" : (speech.isRecording ? "Aufnahme stoppen" : "Jetzt selbst sagen"),
                            systemImage: firstSpeechSucceeded ? "checkmark.circle.fill" : (speech.isRecording ? "stop.fill" : "mic.fill")
                        )
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(firstSpeechSucceeded ? DS.gradePerfect : DS.accent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(firstSpeechSucceeded)

                    if firstSpeechUnavailable {
                        Text("Sprechen ist gerade nicht verfügbar. Du kannst trotzdem fortfahren und später erneut probieren.")
                            .font(.footnote)
                            .foregroundStyle(DS.textSecondary)
                    } else if speech.isRecording {
                        Text(speech.transcription.isEmpty ? "Sprich jetzt den Satz." : "Gehört: \(speech.transcription)")
                            .font(.footnote)
                            .foregroundStyle(DS.textSecondary)
                    }
                } else {
                    Text("Deine erste Übung wird vorbereitet.")
                        .foregroundStyle(DS.textSecondary)
                }
            }
            .padding(.horizontal, DS.space.lg)
            .padding(.bottom, DS.space.lg)
        }
    }

    private var personalizePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space.lg) {
                pageHeader(
                    title: "Was passt heute?",
                    subtitle: "Wähle ein Startthema und deinen täglichen Rhythmus. Beides lässt sich später ändern."
                )
                Text("Startthemen")
                    .font(.headline)
                    .foregroundStyle(DS.textPrimary)
                VStack(spacing: DS.space.sm) {
                    ForEach(shownTopics.prefix(4)) { topic in topicRow(topic) }
                }
                Text("Täglicher Rhythmus")
                    .font(.headline)
                    .foregroundStyle(DS.textPrimary)
                VStack(spacing: DS.space.sm) {
                    ForEach(dailyOptions.filter { [5, 10, 20].contains($0.limit) }, id: \.limit) { option in
                        goalOptionRow(option)
                    }
                }
            }
            .padding(.horizontal, DS.space.lg)
            .padding(.bottom, DS.space.lg)
        }
    }

    private func startFirstSpeech() {
        guard !speech.isRecording else { return }
        TTSService.shared.stop()
        firstSpeechUnavailable = false
        let generation = UUID()
        onboardingSpeechGeneration = generation
        Task {
            let authorized = await speech.requestAuthorization()
            guard onboardingSpeechGeneration == generation,
                  pages.indices.contains(index),
                  pages[index] == .firstSuccess
            else { return }
            guard authorized else {
                firstSpeechUnavailable = true
                return
            }
            if let locale = activeLanguage?.speechLocale { speech.setLocale(locale) }
            speech.clearTranscription()
            do {
                try speech.start()
            } catch {
                firstSpeechUnavailable = true
            }
        }
    }

    private var brandBadge: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [DS.accent, DS.accent.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle().stroke(DS.onAccent.opacity(0.9), lineWidth: 5)
                )
                .shadow(color: DS.accent.opacity(0.35), radius: 18, x: 0, y: 8)
            Text("C")
                .font(.system(size: 88, weight: .bold, design: .serif))
                .foregroundStyle(DS.onAccent)
        }
        .frame(width: 136, height: 136)
        .accessibilityHidden(true)
    }

    private var languagePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space.lg) {
                pageHeader(
                    title: "Welche Sprache?",
                    subtitle: "Womit möchtest du anfangen? Du kannst später jederzeit in den Einstellungen wechseln."
                )
                VStack(spacing: DS.space.sm) {
                    ForEach(learnableLanguages, id: \.code) { lang in
                        languageOptionRow(lang)
                    }
                }
            }
            .padding(.horizontal, DS.space.lg)
            .padding(.bottom, DS.space.lg)
        }
    }

    private func languageOptionRow(_ lang: Language) -> some View {
        let selected = activeCode == lang.code
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedLanguageCode = lang.code
        } label: {
            HStack(spacing: DS.space.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.germanLabel)
                        .font(.headline)
                        .foregroundStyle(selected ? .white : DS.textPrimary)
                    Text(lang.name)   // native name, e.g. Русский / العربية
                        .font(.subheadline)
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : DS.textSecondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? .white : DS.textTertiary)
            }
            .padding(DS.space.md)
            .background(selected ? DS.accent : DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lang.germanLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var howItWorksPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space.lg) {
                pageHeader(
                    title: "So funktioniert's",
                    subtitle: "Drei Wege zu üben — wähl, was zum Moment passt."
                )
                VStack(spacing: DS.space.sm) {
                    modeRow(icon: "keyboard", title: "Tippen",
                            blurb: "Schreib die Antwort. Tippfehler werden fair bewertet, nicht bestraft.")
                    modeRow(icon: "mic.fill", title: "Sprechen",
                            blurb: "Sprich laut. Die Erkennung läuft komplett auf dem Gerät.")
                    modeRow(icon: "rectangle.on.rectangle", title: "Karten",
                            blurb: "Klassisch umdrehen, wenn du nur erkennen statt produzieren willst.")
                }
                infoCallout(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Es merkt sich, was sitzt",
                    body: "Was du sicher kannst, kommt seltener. Was wackelt, kommt zurück — kurz bevor du es vergisst."
                )
                infoCallout(
                    icon: "lock.fill",
                    title: "Alles bleibt bei dir",
                    body: "Keine Konten, kein Tracking. Dein Fortschritt lebt auf deinem Gerät."
                )
            }
            .padding(.horizontal, DS.space.lg)
            .padding(.bottom, DS.space.lg)
        }
    }

    private var goalPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space.lg) {
                pageHeader(
                    title: "Dein Tagesziel",
                    subtitle: "Wie viele neue Vokabeln pro Tag? Wiederholungen kommen oben drauf — und du kannst das jederzeit ändern."
                )
                VStack(spacing: DS.space.sm) {
                    ForEach(dailyOptions, id: \.limit) { option in
                        goalOptionRow(option)
                    }
                }
            }
            .padding(.horizontal, DS.space.lg)
            .padding(.bottom, DS.space.lg)
        }
    }

    private func goalOptionRow(_ option: (limit: Int, title: String, blurb: String)) -> some View {
        let selected = selectedDailyLimit == option.limit
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedDailyLimit = option.limit
        } label: {
            HStack(spacing: DS.space.md) {
                Text("\(option.limit)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(selected ? .white : DS.accent)
                    .frame(width: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.headline)
                        .foregroundStyle(selected ? .white : DS.textPrimary)
                    Text(option.blurb)
                        .font(.caption)
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : DS.textSecondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? .white : DS.textTertiary)
            }
            .padding(DS.space.md)
            .background(selected ? DS.accent : DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.limit) neue Karten, \(option.title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var topicsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space.lg) {
                pageHeader(
                    title: "Womit fängst du an?",
                    subtitle: "Wähl ein paar Themen zum Starten. Mehr schaltest du jederzeit in der Bibliothek frei."
                )
                if shownTopics.isEmpty {
                    Text("Inhalte werden vorbereitet …")
                        .font(.subheadline)
                        .foregroundStyle(DS.textSecondary)
                } else {
                    VStack(spacing: DS.space.sm) {
                        ForEach(shownTopics) { topic in
                            topicRow(topic)
                        }
                    }
                }
            }
            .padding(.horizontal, DS.space.lg)
            .padding(.bottom, DS.space.lg)
        }
    }

    private func topicRow(_ topic: Topic) -> some View {
        let selected = selectedTopicIDs.contains(topic.persistentModelID)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if selected {
                selectedTopicIDs.remove(topic.persistentModelID)
            } else {
                selectedTopicIDs.insert(topic.persistentModelID)
            }
        } label: {
            HStack(spacing: DS.space.md) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? DS.accent : DS.textTertiary)
                Text(topic.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(DS.textPrimary)
                Spacer()
                Text("\(topic.phrases.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(DS.space.md)
            .background(DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radius.md)
                    .stroke(selected ? DS.accent : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(topic.name), \(topic.phrases.count) Phrasen")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var keyboardPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space.lg) {
                pageHeader(
                    title: "\(keyboardLanguageLabel)e Tastatur",
                    subtitle: "Zum Tippen brauchst du eine Tastatur für \(keyboardLanguageLabel). So fügst du sie in iOS hinzu:"
                )
                VStack(spacing: DS.space.sm) {
                    keyboardStep(1, "Öffne die iOS-Einstellungen.")
                    keyboardStep(2, "Allgemein → Tastatur → Tastaturen.")
                    keyboardStep(3, "Tastatur hinzufügen → \(keyboardLanguageLabel) wählen.")
                    keyboardStep(4, "Beim Tippen mit 🌐 zwischen den Tastaturen wechseln.")
                }
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Einstellungen öffnen", systemImage: "arrow.up.forward.app")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(DS.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
                }
                .buttonStyle(.plain)
                Text("Kein Muss — du kannst das auch später machen. Zum Erkennen und Sprechen brauchst du keine Tastatur.")
                    .font(.caption)
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(.horizontal, DS.space.lg)
            .padding(.bottom, DS.space.lg)
        }
    }

    // MARK: - Reusable bits

    private func pageHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: DS.space.sm) {
            Text(title)
                .font(.system(size: 32, weight: .bold, design: .serif))
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, DS.space.md)
    }

    private func modeRow(icon: String, title: String, blurb: String) -> some View {
        HStack(alignment: .top, spacing: DS.space.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(DS.accent)
                .frame(width: 44, height: 44)
                .background(DS.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: DS.radius.sm))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(DS.textPrimary)
                Text(blurb)
                    .font(.subheadline)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
        .accessibilityElement(children: .combine)
    }

    private func infoCallout(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: DS.space.md) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(DS.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.textPrimary)
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func keyboardStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: DS.space.md) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(DS.accent))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Copy helpers

    /// German language name used in the keyboard-page copy. "Russisch" + "e
    /// Tastatur" → "Russische Tastatur"; "Arabisch" → "Arabische Tastatur".
    private var keyboardLanguageLabel: String {
        activeLanguage?.germanLabel ?? "Russisch"
    }

    // MARK: - Persistence

    private func hydrateOnce() {
        guard !didHydrate else { return }
        let row = settings.first
        selectedLanguageCode = row?.activeLanguageCode ?? "ru"
        selectedDailyLimit = row?.dailyNewLimit ?? 10
        rehydrateTopicSelection()
        if let locale = activeLanguage?.speechLocale { speech.setLocale(locale) }
        didHydrate = true
    }

    /// Pre-selects whatever is already active among the active language's shown
    /// starter topics (the seeded defaults on first launch; the user's current
    /// picks on replay). Re-run when the language choice changes.
    private func rehydrateTopicSelection() {
        selectedTopicIDs = Set(shownTopics.filter(\.isActive).map(\.persistentModelID))
        if selectedTopicIDs.isEmpty, let first = shownTopics.first {
            selectedTopicIDs.insert(first.persistentModelID)
        }
    }

    private func finish() {
        let row = settings.first ?? {
            let s = AppSettings()
            context.insert(s)
            return s
        }()
        if !selectedLanguageCode.isEmpty {
            row.activeLanguageCode = selectedLanguageCode
        }
        row.dailyNewLimit = selectedDailyLimit
        // Apply topic choices only to the curated set we actually showed — other
        // topics (e.g. A2/B1/B2 vocab, the other language) keep their state.
        for topic in shownTopics {
            topic.isActive = selectedTopicIDs.contains(topic.persistentModelID)
        }
        row.hasCompletedOnboarding = true
        do {
            try context.save()
        } catch {
            // Keep onboarding open if the durable hand-off failed.
            return
        }
        // First launch: RootView observes the flag and swaps in PracticeView.
        // Replay: this closes the Settings-presented cover. Harmless at the root.
        dismiss()
    }
}
