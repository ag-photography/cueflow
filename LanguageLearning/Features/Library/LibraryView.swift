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
    @Query(sort: \Language.code) private var languages: [Language]
    @Query private var settings: [AppSettings]

    @State private var searchText = ""
    @State private var languageFilter = ""          // "" = all languages
    @State private var activeFilter: ActiveFilter = .all
    @State private var selectedTopic: Topic?
    @State private var practiceTopic: Topic?

    @State private var showingPasteImport = false
    @State private var showingPDFImport = false
    @State private var showingTutorFocus = false
    @State private var showingSettings = false
    @State private var phraseInEditor: Phrase?
    @State private var creatingPhrase = false
    @State private var creatingTopic = false
    @State private var libraryMode: LibraryMode = .learn
    @State private var saveErrorMessage: String?
    @State private var topicPendingDeletion: Topic?
    @State private var phrasePendingDeletion: Phrase?
    @State private var phraseSearchResults: [Phrase] = []
    @State private var cachedLearningEvents: [LearningEvent] = []
    @State private var cachedLearningEventsRevision = -1
    @State private var cachedLearningEventsLanguageCode = ""
    @State private var progressRefreshWorkItem: DispatchWorkItem?
    @State private var contentReady = true

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
        return phraseSearchResults.filter { phrase in
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
                if contentReady {
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
                } else {
                    libraryPlaceholder
                }
            }
            .accessibilityIdentifier("library-root")
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
            .sheet(isPresented: $showingTutorFocus) { TutorFocusView() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $creatingPhrase) { PhraseEditorView(phrase: nil) }
            .sheet(item: $phraseInEditor) { phrase in PhraseEditorView(phrase: phrase) }
            .sheet(isPresented: $creatingTopic) { TopicEditorView(topic: nil) }
            .fullScreenCover(item: $practiceTopic) { topic in
                PracticeView(
                    sessionTarget: min(10, max(1, topic.phrases?.count ?? 1)),
                    isFocusedSession: true,
                    scope: .topic(id: topic.persistentModelID)
                )
            }
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
            .task(id: "\(searchText)|\(languageFilter)") {
                await refreshPhraseSearch()
            }
            .onAppear { scheduleLearningEventsRefresh() }
            .onChange(of: activeLanguageCode) { _, _ in scheduleLearningEventsRefresh() }
            .onDisappear { progressRefreshWorkItem?.cancel() }
        }
    }

    private var managementList: some View {
        List {
            Section {
                NavigationLink {
                    ContentReviewView()
                } label: {
                    Label("Inhalte prüfen", systemImage: "checkmark.seal")
                }
            } footer: {
                Text("Neue manuelle und Tutor-Inhalte durchlaufen eine explizite Qualitätsprüfung.")
            }
            if !activeTopics.isEmpty { activeTopicsSection }
            filterSection
            topicsSection
            if !searchText.isEmpty { phrasesSection }
        }
        .searchable(text: $searchText, prompt: "Themen & Phrasen suchen")
    }

    private var libraryPlaceholder: some View {
        ScrollView {
            VStack(spacing: DS.space.lg) {
                RoundedRectangle(cornerRadius: DS.radius.pill)
                    .fill(DS.surface1)
                    .frame(height: 44)
                ForEach(0..<3, id: \.self) { index in
                    VStack(alignment: .leading, spacing: DS.space.sm) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DS.surface2)
                            .frame(width: index == 0 ? 150 : 210, height: 18)
                        RoundedRectangle(cornerRadius: DS.radius.md)
                            .fill(DS.surface1)
                            .frame(height: index == 0 ? 150 : 104)
                    }
                }
            }
            .padding(DS.space.md)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Bibliothek wird geladen")
        }
        .background(DS.surface0)
    }

    private var learningJourneys: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.space.lg) {
                tutorFocusCard

                VStack(alignment: .leading, spacing: 4) {
                    Text("Was willst du als Nächstes können?")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Wähle eine praktische Mission. CueFlow stellt die passenden Ausdrücke automatisch in deine Einheiten.")
                        .font(.subheadline)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                scenarioCollections

                Text("Deine Themen")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(DS.textPrimary)

                LazyVStack(spacing: DS.space.sm) {
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
            .padding(.horizontal, DS.space.md)
            .padding(.top, DS.space.sm)
            .padding(.bottom, 120)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(DS.surface0)
    }

    private var activeLearningEvents: [LearningEvent] {
        cachedLearningEvents
    }

    private var activeLanguageCode: String {
        settings.first?.activeLanguageCode ?? "ru"
    }

    @MainActor
    private func refreshPhraseSearch() async {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phraseSearchResults = []
            return
        }
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }
        let descriptor = FetchDescriptor<Phrase>(
            sortBy: [SortDescriptor(\Phrase.createdAt, order: .reverse)]
        )
        phraseSearchResults = (try? context.fetch(descriptor)) ?? []
    }

    private func scheduleLearningEventsRefresh() {
        progressRefreshWorkItem?.cancel()
        let code = activeLanguageCode
        if LearningDataCache.shared.isPrimed {
            guard cachedLearningEventsRevision != LearningDataCache.shared.revision
                    || cachedLearningEventsLanguageCode != code else { return }
            cachedLearningEvents = LearningDataCache.shared.events(languageCode: code)
            cachedLearningEventsRevision = LearningDataCache.shared.revision
            cachedLearningEventsLanguageCode = code
            return
        }
        let work = DispatchWorkItem {
            let fetched = (try? context.fetch(FetchDescriptor<Review>())) ?? []
            cachedLearningEvents = LearningMotivation.events(from: fetched.filter {
                $0.card?.phrase?.language?.code == code
            })
        }
        progressRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }
    private var curriculumProgress: [CurriculumStepProgress] {
        let fractions = Dictionary(uniqueKeysWithValues: ScenarioDefinition.defaults.map {
            ($0.id, scenarioFraction($0))
        })
        return CurriculumPlanner.progress(
            scenarios: ScenarioDefinition.defaults,
            fractions: fractions
        )
    }
    private var recommendedScenarioID: String? {
        CurriculumPlanner.recommendation(from: curriculumProgress)?.id
    }

    private var tutorFocusTopics: [Topic] {
        learningTopics.filter(\.isTutorFocusActive).sorted {
            ($0.tutorNextLessonAt ?? .distantFuture) < ($1.tutorNextLessonAt ?? .distantFuture)
        }
    }
    private var tutorFocusTopic: Topic? { tutorFocusTopics.first }
    private var tutorFocusProgress: (introduced: Int, total: Int) {
        let phrases = Dictionary(
            tutorFocusTopics.flatMap { $0.phrases ?? [] }.map {
                (String(describing: $0.persistentModelID), $0)
            },
            uniquingKeysWith: { first, _ in first }
        ).values
        return (
            phrases.count { phrase in (phrase.cards ?? []).contains { $0.state.isIntroduced } },
            phrases.count
        )
    }

    private var tutorFocusCard: some View {
        VStack(alignment: .leading, spacing: DS.space.md) {
            HStack(alignment: .top, spacing: DS.space.md) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.title2)
                    .foregroundStyle(DS.onAccent)
                    .frame(width: 48, height: 48)
                    .background(DS.accent)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("TUTOR-FOKUS")
                        .font(.caption.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(DS.accent)
                    if let tutorFocusTopic {
                        Text(tutorFocusTopics.count == 1
                             ? tutorFocusTopic.name
                             : "\(tutorFocusTopics.count) laufende Einheiten")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(DS.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(tutorFocusProgress.introduced) von \(tutorFocusProgress.total) Ausdrücken vorbereitet" + tutorDeadlineText)
                            .font(.subheadline)
                            .foregroundStyle(DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Lerne passend zu deinem Unterricht")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(DS.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Füge z. B. „Jahreszeiten“ und den Termin deiner nächsten Stunde hinzu.")
                            .font(.subheadline)
                            .foregroundStyle(DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .layoutPriority(1)
                Spacer(minLength: 0)
            }

            HStack(spacing: DS.space.sm) {
                if let tutorFocusTopic {
                    Button {
                        practiceTopic = tutorFocusTopic
                    } label: {
                        Label("Jetzt üben", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.accent)
                    .accessibilityIdentifier("tutor-focus-practice")
                }

                if tutorFocusTopic == nil {
                    Button {
                        showingTutorFocus = true
                    } label: {
                        Label("Thema hinzufügen", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.accent)
                    .accessibilityIdentifier("tutor-focus-add")
                } else {
                    Button {
                        showingTutorFocus = true
                    } label: {
                        Label("Ergänzen", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(DS.accent)
                    .accessibilityIdentifier("tutor-focus-add")
                }
            }
        }
        .dsCard(elevation: 1, padding: DS.space.md)
    }

    private var tutorDeadlineText: String {
        guard let date = tutorFocusTopics.compactMap(\.tutorNextLessonAt).min() else {
            return " · Termin noch nicht gesetzt."
        }
        return " · nächste Stunde \(date.formatted(date: .abbreviated, time: .omitted))."
    }

    private var scenarioCollections: some View {
        VStack(alignment: .leading, spacing: DS.space.sm) {
            Text("Situationen")
                .font(.headline)
                .foregroundStyle(DS.textPrimary)
            NavigationLink {
                SkillPathView()
            } label: {
                Label("Kompletten Lernweg ansehen", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath.fill")
                    .font(.subheadline.weight(.semibold))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.space.sm) {
                    ForEach(ScenarioDefinition.defaults) { scenario in
                        scenarioCard(scenario)
                    }
                }
                .padding(.vertical, DS.space.xs)
            }
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
                    if recommendedScenarioID == scenario.id {
                        Label("Empfohlen", systemImage: "sparkles")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(DS.accent)
                    } else if fraction >= 0.8 {
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
            .frame(width: 236, height: 204, alignment: .topLeading)
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

    private func scenarioFraction(_ scenario: ScenarioDefinition) -> Double {
        let matchedTopics = learningTopics.filter {
            scenario.topicTerms.contains(baseTopicName($0.name))
        }
        let phraseIDs = Set(matchedTopics.flatMap { $0.phrases ?? [] }.map {
            String(describing: $0.persistentModelID)
        })
        return LearningMotivation.strongRecallFraction(
            events: activeLearningEvents,
            phraseIDs: phraseIDs
        )
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
            .dsCard(elevation: 0, padding: DS.space.md)
            .overlay(
                RoundedRectangle(cornerRadius: DS.radius.md)
                    .stroke(topic.isActive ? DS.accent.opacity(0.22) : Color.clear, lineWidth: 1)
            )
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
                showingTutorFocus = true
            } label: {
                Label("Tutor-Fokus", systemImage: "person.2.wave.2")
            }
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
