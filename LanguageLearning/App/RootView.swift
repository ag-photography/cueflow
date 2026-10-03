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

/// The calm launch destination: one recommended action, a visible Sprint, and
/// enough context to understand why today's session is useful.
private struct TodayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.modelContext) private var context
    @Query private var cards: [StudyCard]
    @Query private var reviews: [Review]
    @Query private var settings: [AppSettings]
    @Query(sort: \Topic.name) private var topics: [Topic]
    @Query(sort: \Language.code) private var languages: [Language]

    @AppStorage("lastQuestCelebrationDay") private var lastQuestCelebrationDay = -1
    @AppStorage("preferredSessionTarget") private var sessionTarget = 10
    @AppStorage("weeklyRecapEnabled") private var weeklyRecapEnabled = false
    @State private var showingPractice = false
    @State private var showingSprint = false
    @State private var showingConversation = false
    @State private var showingListeningLab = false
    @State private var showingReading = false
    @State private var showingSkillPath = false
    @State private var showingSettings = false
    @State private var selectedEpisode: LearningEpisode?
    @State private var showingEpisodes = false
    @State private var practiceScope: PracticeScope = .recommended
    @State private var previewPlan: PracticePlan?
    @State private var previewRemaining = 0
    @State private var episodePreviewIDs: [String: UUID] = [:]
    @State private var showingDailyDetails = false
    @State private var activitySaveError: String?
    @State private var tutorDailyDemand: Int?
    @State private var isReturning = false

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
                    if verticalSizeClass != .compact { greeting }
                    if let activitySaveError { Text(activitySaveError).font(.caption).foregroundStyle(DS.gradeHesitant) }
                    if experience?.trial?.variant == "cards-first" && experience?.trial?.endedAt == nil {
                        recommendedSession
                        if let episode = suggestedEpisode { episodeCard(episode) }
                    } else {
                        if let episode = suggestedEpisode { episodeCard(episode) }
                        if suggestedEpisode == nil || isReturning { recommendedSession }
                        else { revisionShortcut }
                    }
                    if let experience {
                        StoryPassportLink(passport: .init(language: activeLanguageCode, experience: experience)) { showingEpisodes = true }
                    }
                    exploreCard
                    DisclosureGroup("Deine Ziele & Lernmomente", isExpanded: $showingDailyDetails) {
                        VStack(spacing: DS.space.md) {
                            if snapshot.difficultCount > 0 { difficultPracticeCard }
                            dailyQuestCard
                            if snapshot.fastestRecall != nil || snapshot.recentImprovement != nil { achievementCard }
                            missionCard
                        }.padding(.top, DS.space.md)
                    }
                    .tint(DS.accentText)
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
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Einstellungen")
                    .accessibilityIdentifier("today-settings")
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingEpisodes) { EpisodeCollectionView() }
            .fullScreenCover(item: $selectedEpisode) { EpisodeView(episode: $0, previewSessionID: episodePreviewIDs[$0.id]) }
            .fullScreenCover(isPresented: $showingPractice) {
                PracticeView(
                    sessionTarget: practiceSessionTarget,
                    isFocusedSession: true,
                    scope: practiceScope,
                    suppliedPlan: practiceScope == .recommended ? previewPlan : nil
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
    private var suggestedEpisode: LearningEpisode? {
        guard let experience else { return nil }
        if let open = experience.runs.last(where: { $0.language == activeLanguageCode && $0.isOpen }),
           let episode = EpisodeLibrary.all.first(where: { $0.id == open.episodeID && $0.version == open.contentVersion }) { return episode }
        if let due = experience.dueEpisode(language: activeLanguageCode) { return due }
        return EpisodeLibrary.recommendation(
            language: activeLanguageCode, purpose: experience.preference(for: activeLanguageCode).purpose,
            focusNames: snapshot.tutorFocusNames,
            completed: experience.completed(in: activeLanguageCode))
    }

    private func episodeCard(_ episode: LearningEpisode) -> some View {
        let data = experience ?? .init()
        let resuming = data.runs.contains { $0.episodeID == episode.id && $0.isOpen }
        let checking = data.isCheckDue(episode)
        return VStack(alignment: .leading, spacing: verticalSizeClass == .compact ? DS.space.xs : DS.space.md) {
            if verticalSizeClass != .compact {
                StoryArtwork(episode: episode)
                    .aspectRatio(320.0 / 150.0, contentMode: .fit)
                    .frame(maxHeight: 150)
            }
            HStack {
                Label(checking ? "Was ist hängen geblieben?" : "DEIN KLEINES ABENTEUER", systemImage: episode.symbol)
                    .font(.caption.weight(.bold)).foregroundStyle(DS.accentText)
                Spacer()
                Text("Vorschau").font(.caption2).foregroundStyle(DS.textSecondary)
            }
            Text(episode.title).font(verticalSizeClass == .compact ? .headline : .title2.bold())
            if verticalSizeClass != .compact {
                Text(episode.outcome).font(.subheadline).foregroundStyle(DS.textSecondary)
            }
            Text(checking ? "3 kurze Antworten · ohne Vorlage" : "\(episode.uniqueExpressions) Ausdrücke · \(episode.steps.count) Schritte · etwa 2 Minuten")
                .font(.caption).foregroundStyle(DS.textSecondary)
            Button { selectedEpisode = episode } label: {
                Label(resuming ? "Geschichte fortsetzen" : checking ? "Kurz erinnern" : "Geschichte starten", systemImage: "play.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, verticalSizeClass == .compact ? 0 : 8)
            }.buttonStyle(.borderedProminent).tint(DS.accent).accessibilityIdentifier("episode-start")
            if verticalSizeClass != .compact { HStack {
                Text("\(data.learningDays(language: activeLanguageCode))/\(data.preference(for: activeLanguageCode).weeklyDays) Lerntage diese Woche")
                    .font(.caption).foregroundStyle(DS.textSecondary)
                Spacer()
                Button { showingEpisodes = true } label: {
                    Text("Alle Geschichten").font(.caption.weight(.semibold))
                        .frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(DS.accentText)
            } }
        }.dsCard(elevation: 2, padding: verticalSizeClass == .compact ? DS.space.sm : DS.space.md)
            .onAppear { recordEpisodePreview(episode) }
    }

    private var revisionShortcut: some View {
        VStack(alignment: .leading, spacing: DS.space.sm) {
            Button {
                practiceScope = .recommended
                showingPractice = true
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Lieber kurz wiederholen?").font(.subheadline.weight(.semibold))
                        Text("\(previewPlan != nil ? previewRemaining : sessionTarget) Ausdrücke · eine kleine Runde")
                            .font(.caption).foregroundStyle(DS.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                }.frame(minHeight: 48)
            }.buttonStyle(.plain).foregroundStyle(DS.accentText)
                .accessibilityIdentifier("recommended-session-start")
            Menu {
                sessionChoice("Schnellrunde", target: 5)
                sessionChoice("Tägliche Einheit", target: 10)
                sessionChoice("Intensiv üben", target: 20)
            } label: { Label(sessionLabel, systemImage: "slider.horizontal.3").font(.caption).padding(.vertical, 8) }
            if let pacing = snapshot.pacing, pacing.remainingNewCount > 0 {
                Text("Tutor-Fokus: \(tutorDailyDemand ?? pacing.dailyNewTarget) neue Ausdrücke je Lerntag. Termine und Umfang findest du in der Bibliothek.")
                    .font(.caption).foregroundStyle(DS.textSecondary)
            }
        }.padding(.horizontal, DS.space.sm)
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

    private var exploreCard: some View {
        VStack(alignment: .leading, spacing: DS.space.md) {
            DSSectionHeader(
                title: "Mehr entdecken",
                subtitle: "Fünf kurze Wege, dieselben Ausdrücke aktiv anzuwenden."
            )
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: DS.space.sm), GridItem(.flexible())],
                spacing: DS.space.sm
            ) {
                activityTile(
                    title: "Lernweg", icon: "point.bottomleft.forward.to.point.topright.scurvepath.fill",
                    identifier: "skill-path-start"
                ) { showingSkillPath = true }
                activityTile(
                    title: "Sprint", icon: "bolt.fill",
                    identifier: "sprint-start"
                ) { showingSprint = true }
                activityTile(
                    title: "Hörstudio", icon: "ear.and.waveform",
                    identifier: "listening-lab-start"
                ) { showingListeningLab = true }
                activityTile(
                    title: "Lesen", icon: "book.pages",
                    identifier: "reading-start"
                ) { showingReading = true }
                activityTile(
                    title: "Gespräch", icon: "person.2.wave.2.fill",
                    identifier: "conversation-start"
                ) { showingConversation = true }
            }
        }
        .dsCard(elevation: 1, padding: DS.space.md)
    }

    private func activityTile(
        title: String,
        icon: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DS.space.sm) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(DS.accent)
                    .frame(width: 36, height: 36)
                    .background(DS.accentSoft)
                    .clipShape(Circle())
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(DS.space.sm)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(DS.surface0.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var dailyQuestCard: some View {
        VStack(alignment: .leading, spacing: DS.space.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HEUTE IM FLOW")
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(DS.accent)
                    Text(snapshot.allQuestsComplete ? "Tagesziele geschafft" : "Drei kleine Ziele")
                        .font(.headline)
                        .foregroundStyle(DS.textPrimary)
                }
                Spacer()
                Image(systemName: snapshot.allQuestsComplete ? "checkmark.seal.fill" : "flag.checkered")
                    .font(.title2)
                    .foregroundStyle(snapshot.allQuestsComplete ? DS.gradePerfect : DS.accent)
                    .symbolEffect(.bounce, value: snapshot.allQuestsComplete && !reduceMotion)
            }
            ForEach(snapshot.dailyQuests) { quest in
                questRow(quest)
            }
        }
        .padding(DS.space.md)
        .background(DS.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.lg))
        .modifier(DS.Elevation(level: 1))
        .accessibilityElement(children: .contain)
    }

    private func questRow(_ quest: DailyQuestProgress) -> some View {
        HStack(spacing: DS.space.sm) {
            Image(systemName: quest.isComplete ? "checkmark.circle.fill" : quest.systemImage)
                .font(.headline)
                .foregroundStyle(quest.isComplete ? DS.gradePerfect : DS.accent)
                .frame(width: 34, height: 34)
                .background((quest.isComplete ? DS.gradePerfect : DS.accent).opacity(0.10))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(quest.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.textPrimary)
                    Spacer()
                    Text("\(min(quest.current, quest.target))/\(quest.target)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DS.textSecondary)
                }
                ProgressView(value: quest.fraction)
                    .tint(quest.isComplete ? DS.gradePerfect : DS.accent)
                Text(quest.detail)
                    .font(.caption2)
                    .foregroundStyle(DS.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(quest.isComplete ? "Abgeschlossen" : "\(quest.current) von \(quest.target)")
    }

    private var achievementCard: some View {
        VStack(alignment: .leading, spacing: DS.space.md) {
            Text("DEINE MOMENTE")
                .font(.caption2.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(DS.textTertiary)
            if let fastestRecall = snapshot.fastestRecall {
                achievementRow(
                    icon: "timer",
                    title: "Schnellster sicherer Abruf",
                    detail: "„\(fastestRecall.sourceText)“ · \(String(format: "%.1f", Double(fastestRecall.responseTimeMs) / 1_000)) s",
                    color: DS.gradeHesitant
                )
            }
            if let recentImprovement = snapshot.recentImprovement {
                achievementRow(
                    icon: "arrow.up.right",
                    title: "Comeback",
                    detail: "„\(recentImprovement.sourceText)“ hast du nach einem Fehler sicher abgerufen.",
                    color: DS.gradePerfect
                )
            }
        }
        .padding(DS.space.md)
        .background(DS.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.lg, style: .continuous))
    }

    private func achievementRow(icon: String, title: String, detail: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: DS.space.sm) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.10))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(DS.textPrimary)
                Text(detail).font(.caption).foregroundStyle(DS.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func celebrateCompletedQuestsIfNeeded() {
        guard snapshot.allQuestsComplete, lastQuestCelebrationDay != todayIndex else { return }
        lastQuestCelebrationDay = todayIndex
        CompletionFeedbackService.shared.playCompletion()
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
        showingPractice || showingSprint || showingListeningLab
            || showingConversation || showingReading || selectedEpisode != nil || showingSettings || showingEpisodes
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
        celebrateCompletedQuestsIfNeeded()
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greetingText)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(DS.textPrimary)
            if verticalSizeClass != .compact {
                Text(snapshot.reviewsToday == 0
                     ? "Bereit, etwas spontan abzurufen?"
                     : "Heute schon \(snapshot.reviewsToday) Antworten produziert.")
                    .font(.subheadline)
                    .foregroundStyle(DS.textSecondary)
            }
        }
    }

    private var recommendedSession: some View {
        VStack(alignment: .leading, spacing: verticalSizeClass == .compact ? DS.space.xs : DS.space.md) {
            HStack {
                Label("Empfohlen", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.accent)
                Spacer()
                Menu {
                    sessionChoice("Schnellrunde", target: 5)
                    sessionChoice("Tägliche Einheit", target: 10)
                    sessionChoice("Intensiv üben", target: 20)
                } label: {
                    Label(sessionLabel, systemImage: "chevron.down")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DS.textSecondary)
                }
            }

            Text("Gezielt wiederholen")
                .font((verticalSizeClass == .compact ? Font.title3 : Font.title2).weight(.bold))
                .foregroundStyle(DS.textPrimary)
            if isReturning {
                Text("Schön, dass du wieder da bist. Kein Nachholen nötig – fünf Ausdrücke reichen für den Wiedereinstieg.")
                    .font(.subheadline).foregroundStyle(DS.textSecondary)
                Button("Mit einer Fünferrunde zurückkommen") { sessionTarget = 5 }
                    .font(.subheadline.weight(.semibold))
            }
            Text(previewPlan != nil ? "\(previewRemaining) Ausdrücke · eine überschaubare Runde" : "Bis zu \(sessionTarget) Ausdrücke · eine überschaubare Runde")
                .font(.subheadline)
                .foregroundStyle(DS.textSecondary)
            if let tutorPacing = snapshot.pacing, tutorPacing.remainingNewCount > 0 {
                Label(
                    "Tutor-Fokus: \(tutorDailyDemand ?? tutorPacing.dailyNewTarget) neue je Lerntag · \(tutorPacing.daysUntilLesson) Tage bis zur nächsten Stunde",
                    systemImage: "person.2.fill"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(DS.accent)
                if (tutorDailyDemand ?? tutorPacing.dailyNewTarget) > (settings.first?.dailyNewLimit ?? 10) {
                    Text("Das liegt über deinem Tageslimit. Dein Limit bleibt unverändert; passe bei Bedarf Termin oder Umfang in der Bibliothek an.")
                        .font(.caption).foregroundStyle(DS.textSecondary)
                }
            }
            if verticalSizeClass != .compact {
                Label("Etwa \(previewPlan != nil ? max(1, Int(ceil(Double(previewRemaining * 33) / 60))) : estimatedMinutes) Minuten", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(DS.textSecondary)
            }

            Button {
                practiceScope = .recommended
                showingPractice = true
            } label: {
                Label("Wiederholungsrunde starten", systemImage: "arrow.right.circle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(DS.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, verticalSizeClass == .compact ? 10 : 16)
                    .background(DS.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recommended-session-start")
        }
        .padding(verticalSizeClass == .compact ? DS.space.md : DS.space.lg)
        .background(DS.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.lg))
        .modifier(DS.Elevation(level: 2))
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
        let pool = cards.filter { $0.phrase?.language?.code == activeLanguageCode }
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

    private var difficultPracticeCard: some View {
        Button {
            practiceScope = .difficultThisWeek
            showingPractice = true
        } label: {
            HStack(spacing: DS.space.md) {
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.title2)
                    .foregroundStyle(DS.gradeHesitant)
                    .frame(width: 48, height: 48)
                    .background(DS.gradeHesitant.opacity(0.12))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Diese Woche schwer gefallen")
                        .font(.headline)
                        .foregroundStyle(DS.textPrimary)
                    Text("\(snapshot.difficultCount) \(snapshot.difficultCount == 1 ? "Ausdruck" : "Ausdrücke") gezielt festigen")
                        .font(.caption)
                        .foregroundStyle(DS.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(DS.space.md)
            .background(DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("difficult-practice-start")
        .accessibilityHint("Startet eine Einheit nur mit kürzlich schwierigen Ausdrücken")
    }

    @ViewBuilder
    private var missionCard: some View {
        if let missionName = snapshot.missionName {
            VStack(alignment: .leading, spacing: DS.space.sm) {
                Text("AKTUELLE MISSION")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(DS.textTertiary)
                Text(missionName)
                    .font(.headline)
                    .foregroundStyle(DS.textPrimary)
                Text("\(snapshot.missionPhraseCount) nützliche Ausdrücke · produktiv üben")
                    .font(.caption)
                    .foregroundStyle(DS.textSecondary)
            }
            .padding(DS.space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.lg, style: .continuous))
        }
    }

    private func sessionChoice(_ label: String, target: Int) -> some View {
        Button { sessionTarget = target } label: {
            if sessionTarget == target {
                Label(label, systemImage: "checkmark")
            } else {
                Text(label)
            }
        }
    }

    private var sessionLabel: String {
        switch sessionTarget {
        case 5: return "Schnellrunde"
        case 20: return "Intensiv"
        default: return "Tägliche Einheit"
        }
    }

    private var greetingText: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Guten Morgen"
        case 12..<18: return "Guten Tag"
        default: return "Guten Abend"
        }
    }
}
