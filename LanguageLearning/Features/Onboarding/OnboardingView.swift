import SwiftUI
import SwiftData
import UIKit

/// First-launch walkthrough (build 21). A small, paged flow that introduces the
/// app, sets a daily goal, activates a few starter topics, and walks through
/// installing the Russian keyboard. Adult tone — no mascots, no pressure — and
/// every choice has a sensible default so "Überspringen" is always safe.
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
    @State private var selectedDailyLimit = 10
    @State private var selectedTopicIDs: Set<PersistentIdentifier> = []
    @State private var didHydrate = false

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

    private enum Page: Hashable {
        case welcome, howItWorks, goal, topics, keyboard
    }

    /// The keyboard page only appears when the active language is typed in a
    /// non-Latin script (Russian → Cyrillic). The Arabic starter practises Latin
    /// transliteration, so it needs no keyboard setup.
    private var needsKeyboardSetup: Bool { activeCode == "ru" }

    private var pages: [Page] {
        var p: [Page] = [.welcome, .howItWorks, .goal, .topics]
        if needsKeyboardSetup { p.append(.keyboard) }
        return p
    }

    private var isLastPage: Bool { index >= pages.count - 1 }

    private var activeCode: String { settings.first?.activeLanguageCode ?? "ru" }

    private var activeLanguage: Language? {
        languages.first { $0.code == activeCode }
    }

    /// Curated starter topics that actually exist for the active language,
    /// in `starterTopicNames` order.
    private var shownTopics: [Topic] {
        let inLang = topics.filter { $0.language?.code == activeCode }
        let byName = Dictionary(inLang.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        return starterTopicNames.compactMap { byName[$0] }
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
        .background(DS.surface0.ignoresSafeArea())
        .onAppear(perform: hydrateOnce)
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
            if !isLastPage {
                Button("Überspringen") { finish() }
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
                Text(isLastPage ? "Los geht's" : "Weiter")
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
        case .howItWorks: howItWorksPage
        case .goal:       goalPage
        case .topics:     topicsPage
        case .keyboard:   keyboardPage
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
                Text("Dein ruhiger Übungsraum für \(languageAccusative). Kein Schnickschnack, kein Maskottchen — nur du, deine Vokabeln und ein System, das weiß, wann du sie wiederholen musst.")
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
                    Circle().stroke(DS.surface0.opacity(0.9), lineWidth: 5)
                )
                .shadow(color: DS.accent.opacity(0.35), radius: 18, x: 0, y: 8)
            Text("C")
                .font(.system(size: 88, weight: .bold, design: .serif))
                .foregroundStyle(DS.surface0)
        }
        .frame(width: 136, height: 136)
        .accessibilityHidden(true)
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
                    title: "Russische Tastatur",
                    subtitle: "Zum Tippen brauchst du die kyrillische Tastatur. So fügst du sie in iOS hinzu:"
                )
                VStack(spacing: DS.space.sm) {
                    keyboardStep(1, "Öffne die iOS-Einstellungen.")
                    keyboardStep(2, "Allgemein → Tastatur → Tastaturen.")
                    keyboardStep(3, "Tastatur hinzufügen → Russisch wählen.")
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

    /// "Russisch" / "Arabisch" in the accusative-friendly welcome sentence.
    private var languageAccusative: String {
        activeLanguage?.germanLabel ?? "Russisch"
    }

    // MARK: - Persistence

    private func hydrateOnce() {
        guard !didHydrate else { return }
        let row = settings.first
        selectedDailyLimit = row?.dailyNewLimit ?? 10
        // Pre-select whatever is already active among the shown starter topics
        // (the seeded defaults on first launch; the user's current picks on replay).
        selectedTopicIDs = Set(shownTopics.filter(\.isActive).map(\.persistentModelID))
        didHydrate = true
    }

    private func finish() {
        let row = settings.first ?? {
            let s = AppSettings()
            context.insert(s)
            return s
        }()
        row.dailyNewLimit = selectedDailyLimit
        // Apply topic choices only to the curated set we actually showed — other
        // topics (e.g. A2/B1/B2 vocab) keep whatever state they had.
        for topic in shownTopics {
            topic.isActive = selectedTopicIDs.contains(topic.persistentModelID)
        }
        row.hasCompletedOnboarding = true
        try? context.save()
        // First launch: RootView observes the flag and swaps in PracticeView.
        // Replay: this closes the Settings-presented cover. Harmless at the root.
        dismiss()
    }
}
