import SwiftUI
import SwiftData

/// Library (overhauled in build 22): manage topics and content. Topics are the
/// primary object — activating them drives the scheduler's new-card source.
///
/// - Search filters topics and phrases at once.
/// - Active topics surface as a chip strip up top (tap a chip to deactivate).
/// - Language + status filters narrow the topic list.
/// - Each topic row toggles active inline and pushes a detail screen with
///   mastery + its phrases.
/// - Bulk activate/deactivate acts on the currently-filtered topics.
/// - The full phrase list only renders while searching (the store holds ~2000
///   phrases — rendering them all was needless work).
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Topic.name) private var topics: [Topic]
    @Query(sort: \Phrase.createdAt, order: .reverse) private var phrases: [Phrase]
    @Query(sort: \Language.code) private var languages: [Language]
    @Query private var settings: [AppSettings]
    @Query private var reviews: [Review]

    @State private var searchText = ""
    @State private var languageFilter = ""          // "" = all languages
    @State private var activeFilter: ActiveFilter = .all
    @State private var selectedTopic: Topic?

    @State private var showingPasteImport = false
    @State private var showingPDFImport = false
    @State private var showingSettings = false
    @State private var phraseInEditor: Phrase?
    @State private var creatingPhrase = false
    @State private var creatingTopic = false
    @State private var libraryMode: LibraryMode = .learn
    @State private var saveErrorMessage: String?
    @State private var topicPendingDeletion: Topic?
    @State private var phrasePendingDeletion: Phrase?

    private enum ActiveFilter: Hashable { case all, active, inactive }
    private enum LibraryMode: Hashable { case learn, manage }

    private let phraseResultCap = 60

    // MARK: - Derived

    /// Languages that actually have topics — drives whether the language filter
    /// is worth showing at all.
    private var languagesWithTopics: [Language] {
        languages.filter { lang in topics.contains { $0.language?.code == lang.code } }
    }

    private var activeTopics: [Topic] {
        topics.filter(\.isActive)
    }

    private var filteredTopics: [Topic] {
        topics.filter { topic in
            (languageFilter.isEmpty || topic.language?.code == languageFilter)
            && {
                switch activeFilter {
                case .all: return true
                case .active: return topic.isActive
                case .inactive: return !topic.isActive
                }
            }()
            && (searchText.isEmpty || topic.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var filteredPhrases: [Phrase] {
        guard !searchText.isEmpty else { return [] }
        return phrases.filter { phrase in
            (languageFilter.isEmpty || phrase.language?.code == languageFilter)
            && (phrase.sourceText.localizedCaseInsensitiveContains(searchText)
                || phrase.targetText.localizedCaseInsensitiveContains(searchText)
                || (phrase.transliteration?.localizedCaseInsensitiveContains(searchText) ?? false))
        }
    }

    private var showLanguageBadges: Bool {
        languageFilter.isEmpty && languagesWithTopics.count > 1
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Ansicht", selection: $libraryMode) {
                    Text("Lernen").tag(LibraryMode.learn)
                    Text("Verwalten").tag(LibraryMode.manage)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, DS.space.md)
                .padding(.vertical, DS.space.sm)

                if libraryMode == .learn {
                    learningJourneys
                } else {
                    managementList
                }
            }
            .navigationTitle("Bibliothek")
            .navigationDestination(item: $selectedTopic) { topic in
                TopicDetailView(topic: topic)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                    .accessibilityLabel("Einstellungen")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if libraryMode == .manage { addMenu }
                }
            }
            .sheet(isPresented: $showingPasteImport) { PasteImportView() }
            .sheet(isPresented: $showingPDFImport) { PDFImportView() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $creatingPhrase) { PhraseEditorView(phrase: nil) }
            .sheet(item: $phraseInEditor) { phrase in PhraseEditorView(phrase: phrase) }
            .sheet(isPresented: $creatingTopic) { TopicEditorView(topic: nil) }
            .alert("Änderung konnte nicht gespeichert werden", isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "Bitte versuche es erneut.")
            }
            .confirmationDialog(
                "Thema endgültig löschen?",
                isPresented: Binding(
                    get: { topicPendingDeletion != nil },
                    set: { if !$0 { topicPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Thema löschen", role: .destructive) {
                    if let topicPendingDeletion {
                        context.delete(topicPendingDeletion)
                        _ = persistContext()
                    }
                    topicPendingDeletion = nil
                }
                Button("Abbrechen", role: .cancel) { topicPendingDeletion = nil }
            } message: {
                Text("Die Zuordnung zu dieser Mission wird entfernt. Die enthaltenen Phrasen bleiben erhalten.")
            }
            .confirmationDialog(
                "Phrase endgültig löschen?",
                isPresented: Binding(
                    get: { phrasePendingDeletion != nil },
                    set: { if !$0 { phrasePendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Phrase löschen", role: .destructive) {
                    if let phrasePendingDeletion {
                        context.delete(phrasePendingDeletion)
                        _ = persistContext()
                    }
                    phrasePendingDeletion = nil
                }
                Button("Abbrechen", role: .cancel) { phrasePendingDeletion = nil }
            } message: {
                Text("Die Phrase und ihr gesamter Lernfortschritt werden gelöscht. Das lässt sich nicht rückgängig machen.")
            }
        }
    }

    private var managementList: some View {
        List {
            if !activeTopics.isEmpty { activeTopicsSection }
            filterSection
            topicsSection
            if !searchText.isEmpty { phrasesSection }
        }
        .searchable(text: $searchText, prompt: "Themen & Phrasen suchen")
    }

    private var learningJourneys: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Was willst du als Nächstes können?")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(DS.textPrimary)
                    Text("Wähle eine praktische Mission. CueFlow stellt die passenden Ausdrücke automatisch in deine Einheiten.")
                        .font(.subheadline)
                        .foregroundStyle(DS.textSecondary)
                }
                .padding(.vertical, DS.space.xs)
            }

            scenarioCollectionsSection

            Section("Missionen") {
                ForEach(learningTopics.prefix(16)) { topic in
                    missionRow(topic)
                }
                if learningTopics.isEmpty {
                    ContentUnavailableView(
                        "Noch keine Missionen",
                        systemImage: "books.vertical",
                        description: Text("Inhalte kannst du unter Verwalten hinzufügen.")
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var activeLearningEvents: [LearningEvent] {
        let code = settings.first?.activeLanguageCode ?? "ru"
        return LearningMotivation.events(from: reviews.filter {
            $0.card?.phrase?.language?.code == code
        })
    }

    private var scenarioCollectionsSection: some View {
        Section("Situationen") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.space.sm) {
                    ForEach(ScenarioDefinition.defaults) { scenario in
                        scenarioCard(scenario)
                    }
                }
                .padding(.vertical, DS.space.xs)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: DS.space.md, bottom: 0, trailing: 0))
        }
    }

    private func scenarioCard(_ scenario: ScenarioDefinition) -> some View {
        let matchedTopics = learningTopics.filter {
            scenario.topicTerms.contains(baseTopicName($0.name))
        }
        let phraseIDs = Set(matchedTopics.flatMap { $0.phrases ?? [] }.map {
            String(describing: $0.persistentModelID)
        })
        let fraction = LearningMotivation.strongRecallFraction(
            events: activeLearningEvents,
            phraseIDs: phraseIDs
        )
        return Button {
            for topic in matchedTopics { topic.isActive = true }
            guard persistContext() else { return }
            selectedTopic = matchedTopics.first
        } label: {
            VStack(alignment: .leading, spacing: DS.space.sm) {
                HStack {
                    Image(systemName: scenario.systemImage)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(DS.accent)
                        .clipShape(Circle())
                    Spacer()
                    if fraction >= 0.8 {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(DS.gradePerfect)
                    }
                }
                Text(scenario.title)
                    .font(.headline)
                    .foregroundStyle(DS.textPrimary)
                Text(scenario.outcome)
                    .font(.caption)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(3)
                ProgressView(value: fraction)
                    .tint(fraction >= 0.8 ? DS.gradePerfect : DS.accent)
                Text(phraseIDs.isEmpty ? "Noch keine passenden Inhalte" : capabilityLabel(fraction))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(DS.space.md)
            .frame(width: 224, height: 196, alignment: .topLeading)
            .background(DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radius.lg)
                    .stroke(DS.accent.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(matchedTopics.isEmpty)
        .accessibilityLabel("\(scenario.title), \(capabilityLabel(fraction))")
        .accessibilityHint("Aktiviert die passenden Missionen")
    }

    private var learningTopics: [Topic] {
        let code = settings.first?.activeLanguageCode ?? "ru"
        return topics
            .filter { $0.language?.code == code && $0.parent == nil && !($0.phrases?.isEmpty ?? true) }
            .sorted {
                if $0.isActive != $1.isActive { return $0.isActive && !$1.isActive }
                return $0.name.localizedCompare($1.name) == .orderedAscending
            }
    }

    private func missionRow(_ topic: Topic) -> some View {
        let topicPhrases = topic.phrases ?? []
        let introduced = topicPhrases.filter { phrase in
            phrase.cards?.first?.state.isIntroduced == true
        }.count
        let total = topicPhrases.count
        let phraseIDs = Set(topicPhrases.map { String(describing: $0.persistentModelID) })
        let fraction = LearningMotivation.strongRecallFraction(
            events: activeLearningEvents,
            phraseIDs: phraseIDs
        )
        return Button {
            if !topic.isActive {
                topic.isActive = true
                guard persistContext() else { return }
            }
            selectedTopic = topic
        } label: {
            VStack(alignment: .leading, spacing: DS.space.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(topic.name)
                        .font(.headline)
                        .foregroundStyle(DS.textPrimary)
                    Spacer()
                    Text(topic.isActive ? "Aktiv" : "Starten")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.accent)
                }
                Text("\(total) Ausdrücke · etwa \(max(3, Int(ceil(Double(total) * 0.45)))) Min.")
                    .font(.caption)
                    .foregroundStyle(DS.textSecondary)
                ProgressView(value: fraction)
                    .tint(DS.accent)
                Text(introduced == 0
                    ? "Noch nicht begonnen"
                    : "\(capabilityLabel(fraction)) · \(introduced) von \(total) kennengelernt")
                    .font(.caption2)
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(.vertical, DS.space.xs)
        }
        .buttonStyle(.plain)
        .accessibilityHint(topic.isActive ? "Öffnet diese Mission" : "Aktiviert und öffnet diese Mission")
    }

    private func capabilityLabel(_ fraction: Double) -> String {
        switch fraction {
        case 0.8...: return "Gesprächsbereit"
        case 0.4...: return "Im Aufbau"
        case 0.01...: return "Erste sichere Abrufe"
        default: return "Neu"
        }
    }

    private func baseTopicName(_ name: String) -> String {
        name.replacingOccurrences(
            of: #"\s*\([A-Z]{2}\)$"#,
            with: "",
            options: .regularExpression
        )
    }

    // MARK: - Active chip strip

    private var activeTopicsSection: some View {
        Section("Aktive Themen") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.space.sm) {
                    ForEach(activeTopics) { topic in
                        activeChip(topic)
                    }
                }
                .padding(.horizontal, DS.space.md)
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets())
        }
    }

    private func activeChip(_ topic: Topic) -> some View {
        Button {
            withAnimation {
                topic.isActive = false
                _ = persistContext()
            }
        } label: {
            HStack(spacing: 6) {
                Text(topic.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.accent)
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(DS.accent.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DS.accentSoft)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(topic.name) deaktivieren")
    }

    // MARK: - Filters

    @ViewBuilder
    private var filterSection: some View {
        Section {
            if languagesWithTopics.count > 1 {
                Picker("Sprache", selection: $languageFilter) {
                    Text("Alle Sprachen").tag("")
                    ForEach(languagesWithTopics, id: \.code) { lang in
                        Text(lang.germanLabel).tag(lang.code)
                    }
                }
                .pickerStyle(.menu)
            }
            Picker("Status", selection: $activeFilter) {
                Text("Alle").tag(ActiveFilter.all)
                Text("Aktiv").tag(ActiveFilter.active)
                Text("Inaktiv").tag(ActiveFilter.inactive)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Topics

    private var topicsSection: some View {
        Section {
            if filteredTopics.isEmpty {
                Text(topicsEmptyMessage)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredTopics) { topic in
                    topicRow(topic)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                topicPendingDeletion = topic
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                topic.isActive.toggle()
                                _ = persistContext()
                            } label: {
                                Label(topic.isActive ? "Deaktivieren" : "Aktivieren",
                                      systemImage: topic.isActive ? "circle" : "checkmark.circle")
                            }
                            .tint(DS.accent)
                        }
                }
            }
        } header: {
            HStack {
                Text("Themen (\(filteredTopics.count))")
                Spacer()
                bulkMenu
            }
        }
    }

    private func topicRow(_ topic: Topic) -> some View {
        HStack(spacing: DS.space.md) {
            Button {
                topic.isActive.toggle()
                _ = persistContext()
            } label: {
                Image(systemName: topic.isActive ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(topic.isActive ? DS.accent : DS.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(topic.isActive ? "\(topic.name), aktiv" : "\(topic.name), inaktiv")

            Button {
                selectedTopic = topic
            } label: {
                HStack(spacing: DS.space.sm) {
                    Text(topic.name)
                        .foregroundStyle(Color.primary)
                    Spacer()
                    if showLanguageBadges, let label = topic.language?.germanLabel {
                        Text(label)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(DS.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DS.surface2)
                            .clipShape(Capsule())
                    }
                    Text("\(topic.phrases?.count ?? 0)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var bulkMenu: some View {
        Menu {
            Button {
                setActive(true, on: filteredTopics)
            } label: {
                Label("Alle aktivieren", systemImage: "checkmark.circle")
            }
            Button {
                setActive(false, on: filteredTopics)
            } label: {
                Label("Alle deaktivieren", systemImage: "circle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
        }
        .textCase(nil)
        .accessibilityLabel("Stapelaktionen")
    }

    private func setActive(_ active: Bool, on list: [Topic]) {
        withAnimation {
            for topic in list { topic.isActive = active }
            _ = persistContext()
        }
    }

    // MARK: - Phrases (search results only)

    private var phrasesSection: some View {
        Section("Phrasen (\(filteredPhrases.count))") {
            if filteredPhrases.isEmpty {
                Text("Keine passenden Phrasen.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredPhrases.prefix(phraseResultCap)) { phrase in
                    Button {
                        phraseInEditor = phrase
                    } label: {
                        phraseResultRow(phrase)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            phrasePendingDeletion = phrase
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                }
                if filteredPhrases.count > phraseResultCap {
                    Text("… und \(filteredPhrases.count - phraseResultCap) weitere. Suche verfeinern.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @discardableResult
    private func persistContext() -> Bool {
        do {
            try context.save()
            saveErrorMessage = nil
            return true
        } catch {
            context.rollback()
            saveErrorMessage = error.localizedDescription
            return false
        }
    }

    private func phraseResultRow(_ phrase: Phrase) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(phrase.sourceText)
                .foregroundStyle(Color.primary)
            Text(phrase.targetText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !(phrase.topics?.isEmpty ?? true) {
                HStack(spacing: 4) {
                    ForEach(phrase.topics ?? []) { topic in
                        Text(topic.name)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Add menu

    private var addMenu: some View {
        Menu {
            Button {
                creatingPhrase = true
            } label: {
                Label("Phrase hinzufügen", systemImage: "plus.bubble")
            }
            Button {
                creatingTopic = true
            } label: {
                Label("Thema hinzufügen", systemImage: "tag")
            }
            Button {
                showingPasteImport = true
            } label: {
                Label("Stapel-Import", systemImage: "square.and.arrow.down.on.square")
            }
            Button {
                showingPDFImport = true
            } label: {
                Label("PDF importieren", systemImage: "doc.text.magnifyingglass")
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Hinzufügen")
    }

    private var topicsEmptyMessage: String {
        if !searchText.isEmpty { return "Nichts gefunden für \(searchText)." }
        switch activeFilter {
        case .active: return "Keine aktiven Themen. Aktiviere eines, um neue Karten zu bekommen."
        case .inactive: return "Keine inaktiven Themen."
        case .all: return "Noch keine Themen."
        }
    }
}
