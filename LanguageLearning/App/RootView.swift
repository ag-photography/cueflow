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

    @AppStorage("lastQuestCelebrationDay") private var lastQuestCelebrationDay = -1
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
    @State private var showingDailyDetails = false
    @State private var activitySaveError: String?
    @State private var tutorDailyDemand: Int?
    @State private var tutorRounds: [TutorFocusPlanner.QuickRound] = []
    @State private var selectedTutorTopicID: PersistentIdentifier?
    @State private var activeTutorRound: TutorFocusPlanner.QuickRound?
    @State private var showingTutorFocus = false
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
                    if let activitySaveError { Text(activitySaveError).font(.caption).foregroundStyle(DS.gradeHesitant) }
                    arcadeInvitation
                    arcadeChoices
                    practiceInvitation
                    playShelf
                    otherPracticeMenu
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
            .sheet(isPresented: $showingTutorFocus, onDismiss: { preparePlan() }) { TutorFocusView() }
            .fullScreenCover(item: $activeTutorRound, onDismiss: { preparePlan() }) { round in
                PracticeView(sessionTarget: 3, isFocusedSession: true,
                    scope: .topic(id: round.topic.persistentModelID), suppliedPlan: round.plan,
                    contextTitle: round.topic.name)
            }
            .fullScreenCover(item: $arcadeMode) { ArcadeView(mode: $0) }
            .sheet(isPresented: $showingEpisodes) { EpisodeCollectionView() }
            .fullScreenCover(item: $selectedEpisode) { EpisodeView(episode: $0, previewSessionID: episodePreviewIDs[$0.id]) }
            .fullScreenCover(isPresented: $showingPractice, onDismiss: { launchedPlan = nil }) {
                PracticeView(
                    sessionTarget: launchedPlan?.budget ?? practiceSessionTarget,
                    isFocusedSession: true,
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
            situationResume: nil,
            hasTutor: tutor != nil,
            hasPractice: previewRemaining > 0,
            hasSituation: false)
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
            Text(choice == .tutor ? tutor?.topic.name ?? "Unterricht" : choice == .situation ? episode?.title ?? "Im Alltag" : resuming ? continuationTitle ?? "Deine Runde fortsetzen" : "Mach die Wörter zu deinen.")
                .font(.title.bold()).fixedSize(horizontal: false, vertical: true)
            Text(choice == .tutor ? "\(tutor?.remainingCount ?? 0) Ausdrücke · ohne Zeitdruck" :
                 choice == .practice ? "\(continuationPlan == nil ? previewRemaining : continuationRemaining) Ausdrücke · eine überschaubare Runde" :
                 choice == .situation ? "\(episode?.uniqueExpressions ?? 0) Ausdrücke · etwa 2 Minuten" : "Gerade ist keine Runde verfügbar. Wähle ein Thema oder füge Unterrichtsvokabeln hinzu.")
                .font(.subheadline).foregroundStyle(DS.textSecondary)
            if choice != nil {
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
                    Label(resuming ? "Meine Runde fortsetzen" : "Los geht’s", systemImage: "play.fill")
                        .font(.headline.bold()).frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(DS.playInk)
                        .background(DS.playMint, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(PracticePressStyle())
                    .accessibilityIdentifier("today-primary-start")
            }
        }.dsCard(elevation: 1, padding: DS.space.lg)
            .overlay { RoundedRectangle(cornerRadius: DS.radius.lg).strokeBorder(DS.playMint.opacity(0.3), lineWidth: 1) }
            .task(id: "\(String(describing: choice))-\(episode?.id ?? "")-\(isCovered)") {
                if choice == .situation, let episode { recordEpisodePreview(episode) }
            }
    }

    private var arcadeInvitation: some View {
        VStack(alignment: .leading, spacing: 18) {
            if verticalSizeClass != .compact {
                Label("DEINE WÖRTER. DEIN SPIEL.", systemImage: "sparkles")
                    .font(.caption.weight(.heavy)).tracking(1).foregroundStyle(DS.accentText)
                HStack(alignment: .center) {
                    Text("Kleine Runde.\nGroßes Yes!")
                        .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 54, weight: .bold)).rotationEffect(.degrees(-10))
                        .foregroundStyle(DS.playMint).accessibilityHidden(true)
                }
                Text("Wischen. Hören. Bauen. Laut sagen.")
                    .font(.subheadline).foregroundStyle(DS.textSecondary)
            } else {
                Text("Deine Wörter. Dein Spiel.").font(.title2.bold())
            }
            Button { arcadeMode = .mix } label: {
                Label("Spiele-Mix starten", systemImage: "play.fill")
                    .font(.headline.bold()).foregroundStyle(DS.playInk)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(DS.playMint, in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(PracticePressStyle()).accessibilityIdentifier("arcade-mix-start")
            if verticalSizeClass != .compact {
                Text("Etwa 2–3 Minuten · dein Wortschatz · ohne Zeitdruck")
                    .font(.caption).foregroundStyle(DS.textSecondary)
            }
        }.padding(24)
            .background(DS.surface1, in: RoundedRectangle(cornerRadius: 26))
            .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(DS.playMint.opacity(0.35), lineWidth: 1) }
    }

    private var arcadeChoices: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Such dir dein Spiel aus").font(.system(.title2, design: .rounded, weight: .bold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .leading, spacing: 12) {
                    quickPlay("Word Snap", detail: "Paare finden & wegklicken", icon: "square.grid.2x2.fill", color: DS.conversationColor,
                              identifier: "arcade-snap-start", width: nil) { arcadeMode = .snap }
                    quickPlay("Sound Hunt", detail: "Hören. Erkennen. Nachsprechen.", icon: "waveform", color: DS.listeningColor,
                              identifier: "arcade-sound-start", width: nil) { arcadeMode = .sound }
                    quickPlay("Swipe Match", detail: "Wisch zur richtigen Bedeutung", icon: "arrow.left.arrow.right", color: DS.sprintColor,
                              identifier: "arcade-swipe-start", width: nil) { arcadeMode = .swipe }
                    quickPlay("Phrase Builder", detail: "Satz bauen und laut sprechen", icon: "puzzlepiece.extension.fill", color: DS.conversationColor,
                              identifier: "arcade-builder-start", width: nil) { arcadeMode = .builder }
                    quickPlay("Quick Recall", detail: "Aus dem Kopf – laut gesagt", icon: "brain.head.profile", color: DS.listeningColor,
                              identifier: "arcade-recall-start", width: nil) { arcadeMode = .recall }
            }.padding(.vertical, 4)
        }
    }

    private var playShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Heute lieber …").font(.system(.title2, design: .rounded, weight: .bold))
            Text("Wähle, worauf du Lust hast.").font(.subheadline).foregroundStyle(DS.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) { quickPlayCards }
                    .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder private var quickPlayCards: some View {
        quickPlay("Tempo machen", detail: "60-Sekunden-Sprint", icon: "bolt.fill", color: DS.sprintColor,
                  identifier: "home-sprint") { showingSprint = true }
        quickPlay("Ins Gespräch", detail: "Eine Rolle. Deine Worte.", icon: "bubble.left.and.bubble.right.fill", color: DS.conversationColor,
                  identifier: "home-conversation") { showingConversation = true }
        quickPlay("Ganz Ohr sein", detail: "Hören & nachsprechen", icon: "headphones", color: DS.listeningColor,
                  identifier: "home-listening") { showingListeningLab = true }
    }

    private func quickPlay(_ title: String, detail: String, icon: String, color: Color,
                           identifier: String, width: CGFloat? = 152, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.title2.bold()).foregroundStyle(color)
                    .frame(width: 46, height: 46).background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                Text(title).font(.headline).foregroundStyle(DS.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.caption).foregroundStyle(DS.textSecondary).fixedSize(horizontal: false, vertical: true)
                Image(systemName: "arrow.up.right").font(.caption.bold()).foregroundStyle(DS.accentText)
            }.frame(width: width, alignment: .leading)
                .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
                .padding(16)
                .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 20))
                .background(DS.surface1, in: RoundedRectangle(cornerRadius: 20))
                .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(color.opacity(0.45), lineWidth: 1) }
        }.buttonStyle(.plain).accessibilityIdentifier(identifier)
    }

    private var otherPracticeMenu: some View {
        Menu {
            Button("Wiederholen") { practiceScope = .recommended; showingPractice = true }
                .accessibilityIdentifier("recommended-session-start")
            if let episode = suggestedEpisode {
                Button("Situation üben") { selectedEpisode = episode }.accessibilityIdentifier("episode-start")
            }
            Button("Alle Situationen") { showingEpisodes = true }
            if !tutorRounds.isEmpty {
                Menu("Aus deinem Unterricht") {
                    ForEach(tutorRounds.filter { $0.remainingCount > 0 }) { round in
                        Button(round.topic.name) { activeTutorRound = round }
                    }
                }
            }
            Button("Unterricht verwalten") { showingTutorFocus = true }
            Divider()
            Button("Lernweg") { showingSkillPath = true }.accessibilityIdentifier("skill-path-start")
            Button("Sprint") { showingSprint = true }.accessibilityIdentifier("sprint-start")
            Button("Hörstudio") { showingListeningLab = true }.accessibilityIdentifier("listening-lab-start")
            Button("Lesen") { showingReading = true }.accessibilityIdentifier("reading-start")
            Button("Gespräch") { showingConversation = true }.accessibilityIdentifier("conversation-start")
        } label: {
            Label("Andere Übung wählen", systemImage: "slider.horizontal.3")
                .frame(maxWidth: .infinity, minHeight: 44)
        }.tint(DS.accentText).accessibilityIdentifier("today-other-practice")
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
                Label(checking ? "Was ist hängen geblieben?" : "IM ALLTAG", systemImage: episode.symbol)
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
                Label(resuming ? "Situation fortsetzen" : checking ? "Kurz erinnern" : "Situation üben", systemImage: "play.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, verticalSizeClass == .compact ? 0 : 8)
            }.buttonStyle(.borderedProminent).tint(DS.accent).accessibilityIdentifier("episode-start")
            if verticalSizeClass != .compact { HStack {
                Text("\(data.learningDays(language: activeLanguageCode))/\(data.preference(for: activeLanguageCode).weeklyDays) Lerntage diese Woche")
                    .font(.caption).foregroundStyle(DS.textSecondary)
                Spacer()
                Button { showingEpisodes = true } label: {
                    Text("Alle Situationen").font(.caption.weight(.semibold))
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

    private var tutorQuickRoundCard: some View {
        let round = tutorRounds.first { $0.topic.persistentModelID == selectedTutorTopicID }
            ?? tutorRounds.first { $0.remainingCount > 0 } ?? tutorRounds[0]
        return VStack(alignment: .leading, spacing: DS.space.sm) {
            Label("AUS DEINEM UNTERRICHT", systemImage: "person.text.rectangle")
                .font(.caption.weight(.bold)).foregroundStyle(DS.accentText)
            Text(round.topic.name).font(.title3.bold())
            if let date = round.topic.tutorNextLessonAt {
                Text("Nächste Stunde: \(date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(DS.textSecondary)
            }
            Text(round.remainingCount > 0
                 ? "\(round.remainingCount) Ausdrücke aus deiner Liste · ohne Zeitdruck"
                 : "Für diese Einheit ist gerade keine weitere Runde geplant. Dein Tageslimit und die Wiederholungstermine bleiben erhalten.")
                .font(.subheadline).foregroundStyle(DS.textSecondary)
            if round.remainingCount > 0 {
                Button { activeTutorRound = round } label: {
                    Label("Kleine Unterrichtsrunde", systemImage: "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent).tint(DS.accent)
                    .accessibilityIdentifier("tutor-quick-round-start")
            }
            ViewThatFits(in: .horizontal) {
                HStack { tutorTopicMenu; Spacer(); tutorManageButton }
                VStack(alignment: .leading) { tutorTopicMenu; tutorManageButton }
            }
        }.dsCard(elevation: 1, padding: DS.space.md)
    }

    private var tutorTopicMenu: some View {
        Menu {
            ForEach(tutorRounds) { round in
                Button(round.topic.name) { selectedTutorTopicID = round.topic.persistentModelID }
            }
        } label: {
            Label("Einheit wählen", systemImage: "arrow.left.arrow.right")
                .font(.caption.weight(.semibold)).frame(minHeight: 44)
        }.tint(DS.accentText).accessibilityIdentifier("tutor-quick-round-topics")
    }

    private var tutorManageButton: some View {
        Button("Unterricht verwalten") { showingTutorFocus = true }
            .font(.caption.weight(.semibold)).frame(minHeight: 44).foregroundStyle(DS.accentText)
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
                    .foregroundStyle(DS.accentText)
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
                        .foregroundStyle(DS.accentText)
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
                    .foregroundStyle(DS.accentText)
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
                .foregroundStyle(DS.accentText)
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
                    .foregroundStyle(DS.accentText)
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
