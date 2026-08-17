import SwiftUI
import SwiftData

/// Root gate: onboarding first, then the native primary navigation.
struct RootView: View {
    @Query private var settings: [AppSettings]
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
    }

    private func storeRecoveryBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: DS.space.sm) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .foregroundStyle(DS.gradeWrong)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sichere Sitzung")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(DS.textPrimary)
                Text(message)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sichere Sitzung. \(message)")
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
    @Query private var cards: [StudyCard]
    @Query private var reviews: [Review]
    @Query private var settings: [AppSettings]
    @Query(sort: \Topic.name) private var topics: [Topic]

    @AppStorage("sprintBest") private var sprintBest = 0
    @AppStorage("lastQuestCelebrationDay") private var lastQuestCelebrationDay = -1
    @AppStorage("preferredSessionTarget") private var sessionTarget = 10
    @AppStorage("weeklyRecapEnabled") private var weeklyRecapEnabled = false
    @State private var showingPractice = false
    @State private var showingSprint = false
    @State private var showingConversation = false
    @State private var showingListeningLab = false
    @State private var showingSkillPath = false
    @State private var showingSettings = false
    @State private var practiceScope: PracticeScope = .recommended

    private var activeLanguageCode: String { settings.first?.activeLanguageCode ?? "ru" }
    private var activeCards: [StudyCard] {
        cards.filter { $0.phrase?.language?.code == activeLanguageCode }
    }
    private var dueCount: Int {
        activeCards.filter { $0.state != .new && $0.dueDate <= .now }.count
    }
    private var availableNewCount: Int {
        activeCards.filter {
            $0.state == .new && (($0.phrase?.topics?.contains(where: { $0.isActive }) ?? false)
                || ($0.phrase?.isPriorityActive ?? false))
        }.count
    }
    private var plannedNewCount: Int {
        min(availableNewCount, settings.first?.dailyNewLimit ?? 10)
    }
    private var estimatedMinutes: Int {
        max(2, Int(ceil(Double(max(1, min(sessionTarget, dueCount + plannedNewCount))) * 0.55)))
    }
    private var reviewsToday: Int {
        reviews.filter { Calendar.current.isDateInToday($0.timestamp) }.count
    }
    private var currentMission: Topic? {
        topics.first { $0.isActive && $0.language?.code == activeLanguageCode }
    }
    private var learningEvents: [LearningEvent] {
        LearningMotivation.events(from: reviews.filter {
            $0.card?.phrase?.language?.code == activeLanguageCode
        })
    }
    private var dailyQuests: [DailyQuestProgress] {
        LearningMotivation.dailyQuests(events: learningEvents)
    }
    private var allQuestsComplete: Bool { dailyQuests.allSatisfy(\.isComplete) }
    private var fastestRecall: LearningEvent? {
        LearningMotivation.fastestStrongRecall(events: learningEvents)
    }
    private var recentImprovement: ImprovingExpression? {
        LearningMotivation.mostRecentImprovement(events: learningEvents)
    }
    private var todayIndex: Int {
        Int(Calendar.current.startOfDay(for: .now).timeIntervalSinceReferenceDate / 86_400)
    }
    private var difficultCards: [StudyCard] {
        DifficultPractice.candidates(
            cards: cards,
            reviews: reviews,
            languageCode: activeLanguageCode
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: verticalSizeClass == .compact ? DS.space.sm : DS.space.lg) {
                    greeting
                    recommendedSession
                    if !difficultCards.isEmpty { difficultPracticeCard }
                    dailyQuestCard
                    skillPathCard
                    sprintCard
                    listeningCard
                    conversationCard
                    if fastestRecall != nil || recentImprovement != nil { achievementCard }
                    missionCard
                }
                .padding(DS.space.md)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(DS.surface0.ignoresSafeArea())
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
            .fullScreenCover(isPresented: $showingPractice) {
                PracticeView(
                    sessionTarget: min(sessionTarget, practiceScope == .difficultThisWeek ? difficultCards.count : sessionTarget),
                    isFocusedSession: true,
                    scope: practiceScope
                )
            }
            .fullScreenCover(isPresented: $showingSprint) { SprintView() }
            .fullScreenCover(isPresented: $showingListeningLab) { ListeningLabView() }
            .fullScreenCover(isPresented: $showingConversation) { ConversationView() }
            .navigationDestination(isPresented: $showingSkillPath) { SkillPathView() }
            .onAppear {
                LearningDataCache.shared.update(cards: cards, reviews: reviews, topics: topics)
                celebrateCompletedQuestsIfNeeded()
                WidgetSnapshotService.refresh(cards: cards, settings: settings)
                consumePendingAction()
            }
            .task { await refreshWeeklyRecap() }
            .onChange(of: reviews.count) { _, _ in
                LearningDataCache.shared.update(cards: cards, reviews: reviews, topics: topics)
                WidgetSnapshotService.refresh(cards: cards, settings: settings)
            }
            .onChange(of: cards.count) { _, _ in
                LearningDataCache.shared.update(cards: cards, reviews: reviews, topics: topics)
            }
            .onChange(of: activeLanguageCode) { _, _ in
                LearningDataCache.shared.update(cards: cards, reviews: reviews, topics: topics)
                WidgetSnapshotService.refresh(cards: cards, settings: settings)
            }
            .onOpenURL { url in
                guard url.scheme == "cueflow" else { return }
                switch url.host {
                case "practice":
                    practiceScope = .recommended
                    showingPractice = true
                case "listening": showingListeningLab = true
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

    private var conversationCard: some View {
        Button { showingConversation = true } label: {
            HStack(spacing: DS.space.md) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.title2)
                    .foregroundStyle(DS.accent)
                    .frame(width: 54, height: 54)
                    .background(DS.accentSoft)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("GESPRÄCH")
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(DS.accent)
                    Text("Im echten Kontext sprechen")
                        .font(.headline)
                        .foregroundStyle(DS.textPrimary)
                    Text("Kurzes Rollenspiel mit deinen aktuellen Ausdrücken")
                        .font(.caption)
                        .foregroundStyle(DS.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(DS.space.md)
            .background(DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.lg))
            .modifier(DS.Elevation(level: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("conversation-start")
        .accessibilityHint("Öffnet ein privates Rollenspiel auf dem Gerät")
    }

    private var skillPathCard: some View {
        Button { showingSkillPath = true } label: {
            HStack(spacing: DS.space.md) {
                Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(DS.accent)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("DEIN LERNWEG")
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(DS.accent)
                    Text("Sieh, was du schon anwenden kannst")
                        .font(.headline)
                        .foregroundStyle(DS.textPrimary)
                    Text("Fähigkeiten, nächste Stufe und Wochenmissionen")
                        .font(.caption)
                        .foregroundStyle(DS.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(DS.textTertiary)
            }
            .padding(DS.space.md)
            .background(DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.lg))
            .modifier(DS.Elevation(level: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("skill-path-start")
    }

    private var listeningCard: some View {
        Button { showingListeningLab = true } label: {
            HStack(spacing: DS.space.md) {
                Image(systemName: "ear.and.waveform")
                    .font(.title2)
                    .foregroundStyle(DS.accent)
                    .frame(width: 54, height: 54)
                    .background(DS.accentSoft)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("HÖRSTUDIO")
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(DS.accent)
                    Text("Erst verstehen, dann nachsprechen")
                        .font(.headline)
                        .foregroundStyle(DS.textPrimary)
                    Text("Kurze Hörimpulse mit langsamem Modell")
                        .font(.caption)
                        .foregroundStyle(DS.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(DS.textTertiary)
            }
            .padding(DS.space.md)
            .background(DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.lg))
            .modifier(DS.Elevation(level: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("listening-lab-start")
        .accessibilityHint("Startet fünf unbewertete Hör- und Nachsprechübungen")
    }

    private var dailyQuestCard: some View {
        VStack(alignment: .leading, spacing: DS.space.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HEUTE IM FLOW")
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(DS.accent)
                    Text(allQuestsComplete ? "Tagesziele geschafft" : "Drei kleine Ziele")
                        .font(.headline)
                        .foregroundStyle(DS.textPrimary)
                }
                Spacer()
                Image(systemName: allQuestsComplete ? "checkmark.seal.fill" : "flag.checkered")
                    .font(.title2)
                    .foregroundStyle(allQuestsComplete ? DS.gradePerfect : DS.accent)
                    .symbolEffect(.bounce, value: allQuestsComplete && !reduceMotion)
            }
            ForEach(dailyQuests) { quest in
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
            if let fastestRecall {
                achievementRow(
                    icon: "timer",
                    title: "Schnellster sicherer Abruf",
                    detail: "„\(fastestRecall.sourceText)“ · \(String(format: "%.1f", Double(fastestRecall.responseTimeMs) / 1_000)) s",
                    color: DS.gradeHesitant
                )
            }
            if let recentImprovement {
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
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
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
        guard allQuestsComplete, lastQuestCelebrationDay != todayIndex else { return }
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

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greetingText)
                .font(.system(verticalSizeClass == .compact ? .title2 : .largeTitle, design: .serif, weight: .bold))
                .foregroundStyle(DS.textPrimary)
            if verticalSizeClass != .compact {
                Text(reviewsToday == 0 ? "Bereit, etwas spontan abzurufen?" : "Heute schon \(reviewsToday) Antworten produziert.")
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

            Text("Weiterlernen")
                .font((verticalSizeClass == .compact ? Font.title3 : Font.title2).weight(.bold))
                .foregroundStyle(DS.textPrimary)
            Text("\(dueCount) Wiederholungen · \(plannedNewCount) neue Ausdrücke")
                .font(.subheadline)
                .foregroundStyle(DS.textSecondary)
            if verticalSizeClass != .compact {
                Label("Etwa \(estimatedMinutes) Minuten", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(DS.textSecondary)
            }

            Button {
                practiceScope = .recommended
                showingPractice = true
            } label: {
                Label("Einheit starten", systemImage: "arrow.right.circle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, verticalSizeClass == .compact ? 10 : 16)
                    .background(DS.accent)
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
                    Text("\(difficultCards.count) \(difficultCards.count == 1 ? "Ausdruck" : "Ausdrücke") gezielt festigen")
                        .font(.caption)
                        .foregroundStyle(DS.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(DS.space.md)
            .background(DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("difficult-practice-start")
        .accessibilityHint("Startet eine Einheit nur mit kürzlich schwierigen Ausdrücken")
    }

    private var sprintCard: some View {
        Button { showingSprint = true } label: {
            HStack(spacing: DS.space.md) {
                Image(systemName: "bolt.fill")
                    .font(.title2)
                    .foregroundStyle(DS.accent)
                    .frame(width: 48, height: 48)
                    .background(DS.accentSoft)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("60-Sekunden-Sprint")
                        .font(.headline)
                        .foregroundStyle(DS.textPrimary)
                    Text(sprintBest > 0 ? "Bestleistung: \(sprintBest)" : "Schnell sprechen, ohne SRS-Druck")
                        .font(.caption)
                        .foregroundStyle(DS.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(DS.space.md)
            .background(DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sprint-start")
    }

    @ViewBuilder
    private var missionCard: some View {
        if let mission = currentMission {
            VStack(alignment: .leading, spacing: DS.space.sm) {
                Text("AKTUELLE MISSION")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(DS.textTertiary)
                Text(mission.name)
                    .font(.headline)
                    .foregroundStyle(DS.textPrimary)
                Text("\(mission.phrases?.count ?? 0) nützliche Ausdrücke · produktiv üben")
                    .font(.caption)
                    .foregroundStyle(DS.textSecondary)
            }
            .padding(DS.space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
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
