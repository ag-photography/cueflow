import SwiftUI
import SwiftData

/// Root gate: onboarding first, then the native primary navigation.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var settings: [AppSettings]
    @Query private var journalRecords: [LearningJournalRecord]
    @State private var journalError: String?
    @State private var showingRecoveryDetails = false
    let storeRecoveryMessage: String?

    init(storeRecoveryMessage: String? = nil) {
        self.storeRecoveryMessage = storeRecoveryMessage
    }

    private var hasOnboarded: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["CUEFLOW_SKIP_ONBOARDING"] == "1" { return true }
        #endif
        return settings.first?.hasCompletedOnboarding ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            if let storeRecoveryMessage {
                storeRecoveryBanner(storeRecoveryMessage)
            }

            Group {
                if hasOnboarded {
                    MainTabView()
                        .transition(.opacity)
                } else {
                    OnboardingView()
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: hasOnboarded)
        .task {
            if let row = settings.first, let data = try? row.readExperience() {
                await NotificationService.shared.refreshLearningReminder(settings: row, experience: data)
            }
        }
        .task(id: "\(journalRecords.count)-\(settings.count)") {
            do {
                guard let row = settings.first else { return }
                let merged = try LearningJournalStore.merged(row.readExperience(), records: journalRecords)
                try row.writeExperience(merged)
                try context.save()
                journalError = nil
            } catch { context.rollback(); journalError = error.localizedDescription }
        }
        .alert("Lernverlauf konnte nicht zusammengeführt werden", isPresented: Binding(get: { journalError != nil }, set: { if !$0 { journalError = nil } })) {
            Button("OK") { journalError = nil }
        } message: { Text(journalError ?? "") }
    }

    private func storeRecoveryBanner(_ message: String) -> some View {
        Button { showingRecoveryDetails = true } label: {
        HStack(alignment: .center, spacing: DS.space.sm) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .foregroundStyle(DS.gradeWrong)
            VStack(alignment: .leading, spacing: 2) {
                Text("Temporäre Sitzung")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DS.textPrimary)
                Text("Fortschritt nicht dauerhaft gespeichert · Details")
                    .font(.caption)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.space.md)
        .padding(.vertical, DS.space.sm)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider() }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sichere Sitzung. \(message)")
        .sheet(isPresented: $showingRecoveryDetails) {
            NavigationStack {
                ScrollView { Text(message).padding() }
                    .navigationTitle("Temporäre Sitzung")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { showingRecoveryDetails = false } } }
            }
        }
    }
}

private struct MainTabView: View {
    private enum Tab: String { case today, library, progress }
    @State private var selection: Tab
    @SceneStorage("cueFlow.mainTab") private var restoredSelection = Tab.today.rawValue

    init() {
        #if DEBUG
        let requested = ProcessInfo.processInfo.environment["CUEFLOW_INITIAL_TAB"]
            .flatMap(Tab.init(rawValue:)) ?? .today
        _selection = State(initialValue: requested)
        #else
        _selection = State(initialValue: .today)
        #endif
    }

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tag(Tab.today)
                .tabItem { Label("Heute", systemImage: "sun.max.fill") }

            LibraryView()
                .tag(Tab.library)
                .tabItem { Label("Bibliothek", systemImage: "books.vertical.fill") }

            ProfileView(showsDismissButton: false)
                .tag(Tab.progress)
                .tabItem { Label("Fortschritt", systemImage: "chart.bar.fill") }
        }
        .tabViewStyle(.sidebarAdaptable)
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["CUEFLOW_INITIAL_TAB"] == nil,
               let restored = Tab(rawValue: restoredSelection) {
                selection = restored
            }
            #else
            if let restored = Tab(rawValue: restoredSelection) { selection = restored }
            #endif
        }
        .onChange(of: selection) { _, newValue in
            restoredSelection = newValue.rawValue
        }
    }
}

/// A short practice invitation followed by a visible world to explore.
/// Collection rewards are derived from saved learning evidence.
private struct TodayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.modelContext) private var context
    @Query private var cards: [StudyCard]
    @Query private var reviews: [Review]
    @Query private var settings: [AppSettings]
    @Query(sort: \Topic.name) private var topics: [Topic]
    @Query(sort: \Language.code) private var languages: [Language]

    @AppStorage("preferredSessionTarget") private var sessionTarget = 10
    @AppStorage("weeklyRecapEnabled") private var weeklyRecapEnabled = false
    @State private var showingPractice = false
    @State private var showingSprint = false
    @State private var arcadeMode: ArcadeMode?
    @State private var showingConversation = false
    @State private var showingListeningLab = false
    @State private var showingReading = false
    @State private var showingSkillPath = false
    @State private var showingSettings = false
    @State private var selectedEpisode: LearningEpisode?
    @State private var showingEpisodes = false
    @State private var practiceScope: PracticeScope = .recommended
    @State private var previewPlan: PracticePlan?
    @State private var continuationPlan: PracticePlan?
    @State private var continuationRemaining = 0
    @State private var continuationTitle: String?
    @State private var continuationScope: PracticeScope = .recommended
    @State private var launchedPlan: PracticePlan?
    @State private var previewRemaining = 0
    @State private var episodePreviewIDs: [String: UUID] = [:]
    @State private var activitySaveError: String?
    @State private var tutorDailyDemand: Int?
    @State private var tutorRounds: [TutorFocusPlanner.QuickRound] = []
    @State private var selectedTutorTopicID: PersistentIdentifier?
    @State private var activeTutorRound: TutorFocusPlanner.QuickRound?
    @State private var showingTutorFocus = false
    @State private var isReturning = false
    @State private var showingFreePractice = false

    /// Everything below the fold is read from here. Deriving it in `body`
    /// meant recomputing it on every tab switch, for every tab.
    @State private var today: TodaySnapshot?
    @State private var loadedRevision = -1
    @State private var loadedLanguageCode = ""

    private var activeLanguageCode: String { settings.first?.activeLanguageCode ?? "ru" }
    private var snapshot: TodaySnapshot { today ?? .empty }
    private var dueCount: Int { snapshot.dueCount }
    private var plannedNewCount: Int {
        min(
            snapshot.availableNewCount,
            settings.first?.dailyNewLimit ?? 10
        )
    }
    private var estimatedMinutes: Int {
        max(2, Int(ceil(Double(max(1, min(sessionTarget, dueCount + plannedNewCount))) * 0.55)))
    }
    private var todayIndex: Int {
        Int(Calendar.current.startOfDay(for: .now).timeIntervalSinceReferenceDate / 86_400)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: verticalSizeClass == .compact ? DS.space.sm : DS.space.lg) {
                    if let activitySaveError { Text(activitySaveError).font(.caption).foregroundStyle(DS.gradeHesitant) }
                    // One next thing; everything else waits, collapsed, in "Frei üben".
                    practiceInvitation
                    freePractice
                }
                .padding(.horizontal, DS.space.md)
                .padding(.top, DS.space.sm)
                .padding(.bottom, DS.space.xxl)
                .frame(maxWidth: DS.mainContentWidth)
                .frame(maxWidth: .infinity)
            }
            .background(DS.pageBackground.ignoresSafeArea())
            .navigationTitle("Heute")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Einstellungen")
                    .accessibilityIdentifier("today-settings")
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingTutorFocus, onDismiss: { preparePlan() }) { TutorFocusView() }
            .fullScreenCover(item: $activeTutorRound, onDismiss: { preparePlan() }) { round in
                PracticeView(sessionTarget: 3,
                    scope: .topic(id: round.topic.persistentModelID), suppliedPlan: round.plan,
                    contextTitle: round.topic.name)
            }
            .fullScreenCover(item: $arcadeMode) { ArcadeView(mode: $0) }
            .sheet(isPresented: $showingEpisodes) { EpisodeCollectionView() }
            .fullScreenCover(item: $selectedEpisode) { EpisodeView(episode: $0, previewSessionID: episodePreviewIDs[$0.id]) }
            .fullScreenCover(isPresented: $showingPractice, onDismiss: { launchedPlan = nil }) {
                PracticeView(
                    sessionTarget: launchedPlan?.budget ?? practiceSessionTarget,
                    scope: practiceScope,
                    suppliedPlan: launchedPlan ?? (practiceScope == .recommended ? previewPlan : nil),
                    contextTitle: launchedPlan == nil ? nil : continuationTitle
                )
            }
            .fullScreenCover(isPresented: $showingSprint) { SprintView() }
            .fullScreenCover(isPresented: $showingListeningLab) { ListeningLabView() }
            .fullScreenCover(isPresented: $showingReading) { ReadingView() }
            .fullScreenCover(isPresented: $showingConversation) { ConversationView() }
            .navigationDestination(isPresented: $showingSkillPath) { SkillPathView() }
            .onAppear { consumePendingAction() }
            .task(id: refreshKey) { await reloadSnapshot() }
            .task(id: "\(refreshKey)-\(sessionTarget)") { preparePlan() }
            .task { await refreshWeeklyRecap() }
            .onOpenURL { url in
                guard url.scheme == "cueflow" else { return }
                switch url.host {
                case "episode":
                    if let episode = EpisodeLibrary.all.first(where: { $0.id == url.lastPathComponent && $0.language == activeLanguageCode }) {
                        selectedEpisode = episode
                    } else { showingEpisodes = true }
                case "practice":
                    practiceScope = .recommended
                    showingPractice = true
                case "listening": showingListeningLab = true
                case "arcade": arcadeMode = ArcadeMode(rawValue: url.lastPathComponent) ?? .mix
                case "reading": showingReading = true
                case "skill-path": showingSkillPath = true
                case "conversation": showingConversation = true
                default: break
                }
            }
        }
    }

    private func consumePendingAction() {
        switch CueFlowPendingAction.consume() {
        case .practice:
            practiceScope = .recommended
            showingPractice = true
        case .conversation:
            showingConversation = true
        case .listening:
            showingListeningLab = true
        case nil:
            break
        }
    }

    private var experience: LearningExperience? { try? settings.first?.readExperience() }

    private var primaryTutorRound: TutorFocusPlanner.QuickRound? {
        let eligible = tutorRounds.filter { $0.remainingCount > 0 }
        let saved = Set((experience?.practicePlans ?? []).map(\.id))
        return eligible.filter { saved.contains($0.plan.id) }.max { $0.plan.createdAt < $1.plan.createdAt }
            ?? eligible.first { $0.topic.persistentModelID == selectedTutorTopicID } ?? eligible.first
    }

    private var recommendation: TodayPracticeRecommendation? {
        let data = experience
        let tutor = primaryTutorRound
        let saved = Set((data?.practicePlans ?? []).map(\.id))
        return TodayPracticeRecommendation.choose(
            tutorResume: tutor.flatMap { saved.contains($0.plan.id) ? $0.plan.createdAt : nil },
            practiceResume: continuationPlan?.createdAt,
            situationResume: openEpisodeRunDate,
            hasTutor: tutor != nil,
            hasPractice: previewRemaining > 0,
            hasSituation: suggestedEpisode != nil)
    }

    /// A Situation the learner started and left open competes as a resumable
    /// round, like a saved practice or tutor round.
    private var openEpisodeRunDate: Date? {
        experience?.runs.filter { $0.isOpen && $0.language == activeLanguageCode }.map(\.updatedAt).max()
    }

    private var practiceInvitation: some View {
        let choice = recommendation
        let tutor = primaryTutorRound
        let episode = suggestedEpisode
        let saved = Set((experience?.practicePlans ?? []).map(\.id))
        let resuming: Bool = switch choice {
        case .tutor: tutor.map { saved.contains($0.plan.id) } ?? false
        case .practice: continuationPlan != nil
        case .situation: experience?.runs.contains { $0.isOpen && $0.language == activeLanguageCode && $0.episodeID == episode?.id } ?? false
        case nil: false
        }
        return VStack(alignment: .leading, spacing: DS.space.md) {
            Label(resuming ? "Deine Runde wartet" : choice == .tutor ? "Für deinen nächsten Unterricht" : "Deine kurze Sprachpause",
                  systemImage: choice == .tutor ? "person.text.rectangle" : "bubble.left.and.text.bubble.right")
                .font(.subheadline.weight(.semibold)).foregroundStyle(DS.accentText)
            Text(choice == .tutor ? tutor?.topic.name ?? "Unterricht" : choice == .situation ? episode?.title ?? "Im Alltag" : resuming ? continuationTitle ?? "Deine Runde fortsetzen" : "Mach die Ausdrücke zu deinen.")
                .font(.title.bold()).fixedSize(horizontal: false, vertical: true)
            Text(choice == .tutor ? "\(tutor?.remainingCount ?? 0) Ausdrücke · ohne Zeitdruck" :
                 choice == .practice ? "\(continuationPlan == nil ? previewRemaining : continuationRemaining) Ausdrücke · eine überschaubare Runde" :
                 choice == .situation ? "\(episode?.uniqueExpressions ?? 0) Ausdrücke · etwa 2 Minuten" : "Gerade ist keine Runde verfügbar. Wähle ein Thema oder füge Unterrichtsvokabeln hinzu.")
                .font(.subheadline).foregroundStyle(DS.textSecondary)
            if choice != nil {
                Text(whyNow(choice))
                    .font(.caption.weight(.semibold)).foregroundStyle(DS.textSecondary)
                    .accessibilityIdentifier("today-why-now")
                Button {
                    switch choice {
                    case .tutor: activeTutorRound = tutor
                    case .practice:
                        launchedPlan = continuationPlan
                        practiceScope = continuationPlan == nil ? .recommended : continuationScope
                        showingPractice = true
                    case .situation: selectedEpisode = episode
                    case nil: break
                    }
                } label: {
                    Label(resuming ? "Fortsetzen" : "Weiterlernen", systemImage: "play.fill")
                }.buttonStyle(.dsPrimary)
                    .accessibilityIdentifier("today-primary-start")
            }
        }.dsCard(elevation: 1, padding: DS.space.lg)
            .task(id: "\(String(describing: choice))-\(episode?.id ?? "")-\(isCovered)") {
                if choice == .situation, let episode { recordEpisodePreview(episode) }
            }
    }

    private func whyNow(_ choice: TodayPracticeRecommendation?) -> String {
        let reason: String = switch choice {
        case .tutor: "Für deinen nächsten Unterricht"
        case .situation: "Eine Situation aus dem Alltag"
        case .practice where dueCount > 0: "\(dueCount) Ausdrücke sind heute dran"
        case .practice: "Neue Ausdrücke für heute"
        case nil: ""
        }
        return "≈ \(estimatedMinutes) Min · \(reason)"
    }

    /// Free choice, collapsed by default: every activity once, one name each.
    private var freePractice: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { showingFreePractice.toggle() }
            } label: {
                HStack {
                    Label("Frei üben", systemImage: "square.grid.2x2").font(.headline).foregroundStyle(DS.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down").font(.subheadline.bold()).foregroundStyle(DS.accentText)
                        .rotationEffect(.degrees(showingFreePractice ? 180 : 0))
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityIdentifier("today-other-practice")
                .accessibilityValue(showingFreePractice ? "geöffnet" : "geschlossen")
            if showingFreePractice {
            VStack(alignment: .leading, spacing: DS.space.md) {
                freeSection("Sprechen") {
                    freeRow("Sprint", "60 Sekunden, so viel du sagen kannst", "bolt.fill", "sprint-start") { showingSprint = true }
                    freeRow("Gespräch", "Eine Rolle, deine Worte", "bubble.left.and.bubble.right.fill", "conversation-start") { showingConversation = true }
                }
                freeSection("Hören") {
                    freeRow("Hörstudio", "Hören, verstehen, nachsprechen", "headphones", "listening-lab-start") { showingListeningLab = true }
                }
                freeSection("Situationen") {
                    if let episode = suggestedEpisode {
                        freeRow(episode.title, "Nächste Situation", "theatermasks.fill", "episode-start") { selectedEpisode = episode }
                    }
                    freeRow("Alle Situationen", nil, "square.stack", "episodes-all") { showingEpisodes = true }
                }
                freeSection("Spiele") {
                    ForEach(ArcadeMode.standalone) { game in
                        freeRow(game.title, nil, game.symbol, "arcade-\(game.rawValue)-start") { arcadeMode = game }
                    }
                }
                freeSection("Üben & Unterricht") {
                    freeRow("Nur wiederholen", nil, "arrow.clockwise", "recommended-session-start") {
                        practiceScope = .recommended; showingPractice = true
                    }
                    ForEach(tutorRounds.filter { $0.remainingCount > 0 }) { round in
                        freeRow(round.topic.name, "Aus deinem Unterricht", "person.text.rectangle", "tutor-round-\(round.topic.name)") { activeTutorRound = round }
                    }
                    freeRow("Unterricht verwalten", nil, "slider.horizontal.3", "tutor-manage") { showingTutorFocus = true }
                    freeRow("Lernweg", nil, "map", "skill-path-start") { showingSkillPath = true }
                }
            }.padding(.top, DS.space.sm)
            }
        }
    }

    private func freeSection<Content: View>(_ title: String, @ViewBuilder _ rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(DS.textSecondary)
                .textCase(.uppercase).padding(.bottom, 4)
            rows()
        }
    }

    private func freeRow(_ title: String, _ detail: String?, _ icon: String, _ identifier: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.space.sm) {
                Image(systemName: icon).foregroundStyle(DS.accentText).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(DS.textPrimary)
                    if let detail { Text(detail).font(.caption).foregroundStyle(DS.textSecondary) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(DS.textTertiary)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(identifier)
    }

    private var suggestedEpisode: LearningEpisode? {
        guard let experience else { return nil }
        if let open = experience.runs.filter({ $0.language == activeLanguageCode && $0.isOpen }).max(by: { $0.updatedAt < $1.updatedAt }),
           let episode = EpisodeLibrary.all.first(where: { $0.id == open.episodeID && $0.version == open.contentVersion }) { return episode }
        if let due = experience.dueEpisode(language: activeLanguageCode) { return due }
        return EpisodeLibrary.recommendation(
            language: activeLanguageCode, purpose: experience.preference(for: activeLanguageCode).purpose,
            focusNames: snapshot.tutorFocusNames,
            completed: experience.completed(in: activeLanguageCode))
    }

    private func recordEpisodePreview(_ episode: LearningEpisode) {
        guard !isCovered, episodePreviewIDs[episode.id] == nil, let row = settings.first else { return }
        do {
            var data = try row.readExperience()
            let id = UUID()
            data.events.append(.init(name: "today_story_preview", language: episode.language,
                sessionID: id, timestamp: .now, stepID: episode.id))
            try row.writeExperience(data)
            try context.save()
            episodePreviewIDs[episode.id] = id
            activitySaveError = nil
        } catch { context.rollback(); activitySaveError = "Nutzungsereignis nicht gespeichert: \(error.localizedDescription)" }
    }

    private func refreshWeeklyRecap() async {
        guard weeklyRecapEnabled else { return }
        let summary = WeeklyRecap.summary(
            reviews: reviews,
            languageCode: activeLanguageCode
        )
        await NotificationService.shared.scheduleWeeklyRecap(summary)
    }

    /// Changes whenever the store or the active language moves. Counts are the
    /// cheap part of the fingerprint; the cache does the precise check.
    /// True while a session is covering Heute. Its numbers can't be seen, and
    /// they'd be recomputed after every answer.
    private var isCovered: Bool {
        showingPractice || arcadeMode != nil || showingSprint || showingListeningLab
            || showingConversation || showingReading || selectedEpisode != nil || showingSettings || showingEpisodes
            || activeTutorRound != nil || showingTutorFocus
    }

    private var refreshKey: String {
        // Stored properties only — no relationship access. Activating a topic
        // changes no count, so the flags are part of the key.
        let active = topics.count(where: \.isActive)
        let focused = topics.count(where: \.isTutorFocus)
        return "\(activeLanguageCode)|\(cards.count)|\(reviews.count)|\(topics.count)|\(active)|\(focused)|\(isCovered)"
    }

    private func reloadSnapshot() async {
        // `isCovered` is part of `refreshKey`, so dismissing the cover fires
        // this again and the deferred refresh happens then.
        guard !isCovered else { return }
        let cache = LearningDataCache.shared
        let phraseCount = (try? context.fetchCount(FetchDescriptor<Phrase>())) ?? 0
        cache.update(
            cards: cards, reviews: reviews, topics: topics,
            languages: languages, phraseCount: phraseCount
        )
        guard loadedRevision != cache.revision
                || loadedLanguageCode != activeLanguageCode
                || today == nil else { return }
        let result = await cache.snapshots(languageCode: activeLanguageCode)
        guard !Task.isCancelled else { return }
        today = result.snapshots.today
        loadedRevision = result.revision
        loadedLanguageCode = activeLanguageCode
        WidgetSnapshotService.refresh(
            dueCount: result.snapshots.today.dueCount,
            newCount: result.snapshots.today.availableNewCount,
            languageCode: activeLanguageCode
        )
    }

    private var practiceSessionTarget: Int {
        switch practiceScope {
        case .difficultThisWeek:
            return min(sessionTarget, snapshot.difficultCount)
        case .topic, .scenario:
            return sessionTarget
        case .recommended:
            return sessionTarget
        }
    }

    private func preparePlan() {
        guard !isCovered else { return }
        tutorRounds = TutorFocusPlanner.quickRounds(topics: topics, cards: cards, reviews: reviews,
            language: activeLanguageCode, dailyLimit: settings.first?.dailyNewLimit ?? 10,
            savedPlans: experience?.practicePlans ?? [], endedIDs: experience?.endedPlanIDs ?? [])
        let pool = cards.filter { $0.phrase?.language?.code == activeLanguageCode }
        let scopes: [PracticeScope] = [.recommended, .difficultThisWeek]
            + topics.filter { $0.language?.code == activeLanguageCode }.map { .topic(id: $0.persistentModelID) }
            + ScenarioDefinition.defaults.map { .scenario(id: $0.id) }
        continuationPlan = nil
        continuationRemaining = 0
        continuationTitle = nil
        for plan in (experience?.practicePlans ?? []).sorted(by: { $0.createdAt > $1.createdAt }) {
            guard let scope = scopes.first(where: { $0.planKey == plan.scope }),
                  plan.canResume(language: activeLanguageCode, scope: scope.planKey, mode: .speakDeToRu,
                                 budget: plan.budget, endedIDs: experience?.endedPlanIDs ?? []),
                  !plan.remaining(in: pool.filter(scope.includes), reviews: reviews,
                                  dailyNewLimit: settings.first?.dailyNewLimit ?? 10).isEmpty else { continue }
            continuationPlan = plan
            continuationRemaining = plan.remaining(in: pool.filter(scope.includes), reviews: reviews,
                dailyNewLimit: settings.first?.dailyNewLimit ?? 10).count
            continuationScope = scope
            continuationTitle = topics.first { scope == .topic(id: $0.persistentModelID) }?.name
            break
        }
        let latest = max(reviews.filter { $0.card?.phrase?.language?.code == activeLanguageCode }.map(\.timestamp).max() ?? .distantPast,
                         experience?.runs.filter { $0.language == activeLanguageCode }.map(\.updatedAt).max() ?? .distantPast)
        isReturning = latest != .distantPast && Date.now.timeIntervalSince(latest) >= 7 * 86_400
        let introduced = Set(pool.filter(\.hasBeenIntroduced).compactMap { $0.phrase?.contentID })
        var allocated: Set<ContentID> = []
        var demand = 0
        for topic in topics.filter({ $0.language?.code == activeLanguageCode && $0.isTutorFocusActive })
            .sorted(by: { ($0.tutorNextLessonAt ?? .distantFuture) < ($1.tutorNextLessonAt ?? .distantFuture) }) {
            let ids = Set((topic.phrases ?? []).map(\.contentID)).subtracting(allocated)
            allocated.formUnion(ids)
            demand += TutorStudyBudget.make(remaining: ids.subtracting(introduced).count, deadline: topic.tutorNextLessonAt,
                weekdays: experience?.preference(for: activeLanguageCode).effectiveStudyWeekdays,
                dailyLimit: settings.first?.dailyNewLimit ?? 10).requiredPerOpportunity
        }
        tutorDailyDemand = demand
        if let saved = (experience?.practicePlans ?? []).last(where: {
            $0.canResume(language: activeLanguageCode, scope: "recommended", mode: .speakDeToRu, budget: sessionTarget, endedIDs: experience?.endedPlanIDs ?? [])
            && !$0.remaining(in: pool, reviews: reviews).isEmpty
        }) { previewPlan = saved; previewRemaining = saved.remaining(in: pool, reviews: reviews).count; return }
        previewPlan = PracticePlan.make(cards: pool, reviews: reviews, language: activeLanguageCode,
            scope: "recommended", mode: .speakDeToRu, budget: sessionTarget,
            dailyLimit: settings.first?.dailyNewLimit ?? 10,
            tutorIDs: TutorPriority.phraseIDs(topics: topics, cards: cards))
        previewRemaining = previewPlan?.items.count ?? 0
    }

}
