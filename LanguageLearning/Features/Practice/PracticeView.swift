import SwiftUI
import SwiftData
import UIKit

/// A small deterministic gate for the practice lifecycle. Every delayed or
/// asynchronous result carries a generation token; changing card, mode,
/// language, or screen invalidates it so stale work cannot mutate the session.
struct PracticeInteractionGate {
    enum Operation: Equatable {
        case grading, choiceDelay, permission, persistence
    }

    struct Token: Equatable {
        fileprivate let generation: UUID
        let operation: Operation
    }

    private(set) var generation = UUID()
    private(set) var activeOperation: Operation?

    var isBusy: Bool { activeOperation != nil }
    var lifecycleID: UUID { generation }

    mutating func begin(_ operation: Operation) -> Token? {
        guard activeOperation == nil else { return nil }
        activeOperation = operation
        return Token(generation: generation, operation: operation)
    }

    func accepts(_ token: Token) -> Bool {
        token.generation == generation && token.operation == activeOperation
    }

    func accepts(lifecycleID: UUID) -> Bool {
        lifecycleID == generation
    }

    @discardableResult
    mutating func finish(_ token: Token) -> Bool {
        guard accepts(token) else { return false }
        activeOperation = nil
        return true
    }

    mutating func invalidate() {
        generation = UUID()
        activeOperation = nil
    }
}

/// Practice screen — the core loop. Custom header at the top with a pill-style
/// mode picker (no more bottom page dots overlaying the rating row). Hero
/// prompt card, distinct reveal layout, modern semantic rating buttons.
struct PracticeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Query private var cards: [StudyCard]
    @Query private var reviews: [Review]
    @Query private var settings: [AppSettings]
    @Query private var languages: [Language]
    @Query private var topics: [Topic]

    @State private var mode: CardDirection = .speakDeToRu   // "Üben" (speak-focused)
    @State private var phase: Phase = .loading
    @State private var input: String = ""
    @State private var promptStart: Date?
    @State private var showingLibrary = false
    @State private var showingProfile = false
    @State private var showingSprint = false
    @State private var sessionCount: Int = 0
    @State private var plannedCardIDs: [ContentID]?
    @State private var persistedPlan: PracticePlan?
    @State private var activeSince: Date? = .now
    @State private var playedSummarySound = false
    @State private var answerWasRevealed = false
    @State private var firstRetryAnswer: String?
    @State private var firstRetryCorrect: Bool?
    @State private var restoredTileSupport = false
    @State private var inputAvailableMs: Int?
    @State private var gradingWaitMs: Int?
    @State private var timingInterrupted = false
    @State private var sessionCorrect: Int = 0
    @State private var consecutiveProductiveRecalls: Int = 0
    @State private var sessionSpokenAnswers: Int = 0
    @State private var sessionSpokenWords: Int = 0
    @State private var sessionNewlyRecalled: [String] = []
    @State private var sessionNeedsWork: Int = 0
    @State private var sessionNewRecord: (source: String, milliseconds: Int)?
    @State private var sessionCompletedMission: String?
    @State private var showingSessionSummary = false
    @State private var speechAuthorized: Bool? = nil
    @State private var speechErrorMessage: String?
    @State private var showingGradeDetails: Bool = false
    @State private var savedAlternativeBanner: String?
    @State private var surprisePraiseBanner: String?
    // Set when the user taps "Weiter mit neuen Karten" on the daily-limit
    // screen — lifts the new-card cap for the rest of this mode's session.
    @State private var newCardsUnlocked = false
    // "Ich kann gerade nicht sprechen": pauses the speak step for this session
    // and falls back to keyboard-free multiple-choice on the same schedule.
    @State private var speechMuted = false
    // "Wählen" (multiple-choice) mode: the four options for the current card and
    // the option the user tapped (nil until they answer).
    @State private var choiceOptions: [String] = []
    @State private var choiceModelAcknowledged = false
    @State private var choiceChosen: String? = nil
    @State private var tileOptions: [WordTile] = []
    @State private var selectedTileIDs: [Int] = []
    @State private var reviewModeOverride: CardDirection?
    @State private var lastSubmissionWasSpeech = false
    @State private var retryWasNeeded = false
    // "Sag es im Satz" screen (after scoring, young cards only): flips true once
    // the user has recorded the sentence at least once, which reveals "Weiter".
    @State private var sentenceSpoken = false
    /// The learner asked to see the sentence before speaking it (opt-in reading).
    @State private var sentencePeek = false
    @State private var interactionGate = PracticeInteractionGate()
    @State private var gradingTask: Task<Void, Never>?
    @State private var choiceDelayTask: Task<Void, Never>?
    @State private var permissionTask: Task<Void, Never>?
    @State private var silenceTask: Task<Void, Never>?
    @State private var praiseTask: Task<Void, Never>?
    @State private var savedBannerTask: Task<Void, Never>?
    @State private var persistenceErrorMessage: String?
    @State private var isSessionPaused = false
    @State private var showingExitConfirmation = false
    @State private var reviewedCardIDs: Set<ContentID> = []
    /// Resolved once per card rather than per card *per card* — see
    /// `TutorPriority`. Refreshed whenever the queue advances.
    @State private var tutorPriorityPhraseIDs: Set<ContentID> = []
    @StateObject private var speech = SpeechRecognitionService()
    @FocusState private var inputFocused: Bool
    @Namespace private var tileNamespace
    // Lets the fixed-size serif prompt grow with Dynamic Type (capped so very
    // large accessibility sizes don't push the input off-screen).
    @ScaledMetric(relativeTo: .largeTitle) private var heroTypeScale: CGFloat = 1

    let sessionTarget: Int
    let scope: PracticeScope
    let suppliedPlan: PracticePlan?
    let contextTitle: String?
    private let transliterationGracePeriod = 200
    private let speakHesitantStartDelaySec: Double = 4.0
    private let speakHesitantPauseSec: Double = 1.5

    // Prompt-to-submit time includes reading, typing and ASR latency. Until
    // timing is calibrated per modality, correctness suggests Good, not Easy.
    private let grader = GraderService(fastResponseCutoffMs: 0)
    private let scheduler = SchedulerService()
    private let tts = TTSService.shared

    init(
        sessionTarget: Int = 10,
        scope: PracticeScope = .recommended,
        suppliedPlan: PracticePlan? = nil,
        contextTitle: String? = nil
    ) {
        self.sessionTarget = max(1, sessionTarget)
        self.scope = scope
        self.suppliedPlan = suppliedPlan
        self.contextTitle = contextTitle
    }

    enum Phase {
        case loading
        case prompt(StudyCard)
        case study(StudyCard)
        case reveal(StudyCard, GradeResult, userAnswer: String, responseTimeMs: Int)
        /// "Now you say it": after scoring a young card, a dedicated screen that
        /// makes the user speak the example sentence out loud before continuing.
        /// Unscored — the point is spoken volume, not accuracy.
        case speakSentence(StudyCard)
        case empty
    }

    private var shouldShowTransliteration: Bool {
        switch settings.first?.transliterationVisible {
        case .some(true): return true
        case .some(false): return false
        case .none: return reviews.count < transliterationGracePeriod
        }
    }

    /// The user's currently-selected target language (Russian, Arabic, …).
    /// Falls back to Russian if settings is uninitialised. Drives card filtering,
    /// TTS voice selection, ASR locale, RTL flip and the input placeholder.
    private var activeLanguage: Language? {
        let code = settings.first?.activeLanguageCode ?? "ru"
        return languages.first(where: { $0.code == code })
    }

    /// Cards in the active language only — Russian phrases stay hidden when
    /// the user has Arabic selected and vice versa.
    private var cardsForActiveLanguage: [StudyCard] {
        guard let code = activeLanguage?.code else { return cards }
        return cards.filter { $0.phrase?.language?.code == code }
    }

    /// The cloze item for a card, when the bundled sentence lets us build one.
    /// Cards without a usable item never enter the "Lücken" pool.
    private func clozeItem(for card: StudyCard) -> ClozeItem? {
        guard let phrase = card.phrase else { return nil }
        return ClozeBuilder.item(for: phrase)
    }

    /// What the learner must produce. In "Lücken" that is the inflected surface
    /// form the sentence needs, not the phrase's headword.
    private func expectedAnswer(for card: StudyCard) -> String {
        if mode == .clozeDeToRu, let cloze = clozeItem(for: card) { return cloze.answer }
        return card.phrase?.targetText ?? ""
    }

    private var difficultCards: [StudyCard] {
        DifficultPractice.candidates(
            cards: cards,
            reviews: reviews,
            languageCode: activeLanguage?.code ?? "ru"
        )
    }

    // MARK: - Body

    var body: some View {
        // The round summary renders inside this cover rather than as a sheet
        // stacked on top of it (HIG: one modal at a time).
        Group {
        if showingSessionSummary { sessionSummarySheet } else {
        VStack(spacing: 0) {
            sessionProgressBar
            focusedSessionHeader
            if let persistenceErrorMessage {
                persistenceErrorBanner(persistenceErrorMessage)
                    .padding(.horizontal, DS.space.md)
                    .padding(.top, DS.space.sm)
            }
            Group {
                if isSessionPaused {
                    pausedContent
                } else {
                    content
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, DS.space.md)
        }
        }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .background(DS.pageBackground.ignoresSafeArea())
        .sheet(isPresented: $showingLibrary, onDismiss: { advance() }) {
            LibraryView()
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView()
        }
        .fullScreenCover(isPresented: $showingSprint) {
            SprintView()
        }
        .onChange(of: mode) { _, _ in
            // Switching modes resets the current card — keep state coherent.
            // Each mode decides the daily-limit override independently.
            invalidateInteraction()
            newCardsUnlocked = false
            speechMuted = savedQuietPreference
            resetSession()
            phase = .loading
            input = ""
            speech.clearTranscription()
        }
        .onChange(of: settings.first?.activeLanguageCode) { _, _ in
            // Active language switch: reset session, update speech locale,
            // reload the first card for the new language.
            invalidateInteraction()
            newCardsUnlocked = false
            speechMuted = savedQuietPreference
            resetSession()
            phase = .loading
            input = ""
            speech.clearTranscription()
            if let locale = activeLanguage?.speechLocale {
                speech.setLocale(locale)
            }
        }
        .onAppear {
            speechMuted = savedQuietPreference
            if let locale = activeLanguage?.speechLocale {
                speech.setLocale(locale)
            }
            // `availableNewCount` reads this, and the daily-limit screen can be
            // reached before the queue has advanced once.
            refreshTutorPriority()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active { timingInterrupted = true; recordLifecycle("session_paused"); activeSince = nil; invalidateInteraction() }
            else { activeSince = .now; recordLifecycle("session_resumed") }
        }
        .onChange(of: speech.transcription) { _, newValue in
            markInputAvailable(newValue)
            scheduleSilenceCompletion(after: newValue)
        }
        .onChange(of: input) { _, value in markInputAvailable(value) }
        .onChange(of: speech.lastError) { _, message in
            if message != nil { recordLifecycle("recognition_failed") }
        }
        .onDisappear { recordLifecycle("session_paused"); invalidateInteraction() }
        .modifier(ExposureBoundary())
        .confirmationDialog(
            "Runde beenden?",
            isPresented: $showingExitConfirmation,
            titleVisibility: .visible
        ) {
            Button("Runde beenden", role: .destructive) { if recordLifecycle("session_ended") { dismiss() } }
            Button("Weiter üben", role: .cancel) {}
        } message: {
            Text("Dein bereits gespeicherter Fortschritt bleibt erhalten.")
        }
    }

    // MARK: - Header

    private var focusedSessionHeader: some View {
        HStack(spacing: DS.space.md) {
            Button {
                if sessionCount > 0 {
                    showingExitConfirmation = true
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Runde schließen")
            .accessibilityIdentifier("practice-close")

            VStack(spacing: 2) {
                if let contextTitle {
                    Text(contextTitle).font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.textPrimary)
                        .accessibilityIdentifier("practice-tutor-context")
                }
                Text(plannedOpportunityCount > 0 ? "\(min(sessionCount + 1, plannedOpportunityCount)) von \(plannedOpportunityCount)" : "Runde wird vorbereitet")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(DS.textSecondary)
            }.frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            Button {
                if isSessionPaused {
                    isSessionPaused = false
                    promptStart = .now
                } else {
                    invalidateInteraction()
                    isSessionPaused = true
                }
            } label: {
                Image(systemName: isSessionPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(isSessionPaused ? "Runde fortsetzen" : "Runde pausieren")
        }
        .padding(.horizontal, DS.space.sm)
        .background(DS.surface0)
    }

    private var pausedContent: some View {
        VStack(spacing: DS.space.lg) {
            Spacer()
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(DS.accentText)
            Text("Runde pausiert")
                .font(.title2.weight(.bold))
                .foregroundStyle(DS.textPrimary)
            Text("Atme kurz durch. Deine aktuelle Stelle bleibt erhalten.")
                .font(.subheadline)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                isSessionPaused = false
                promptStart = .now
            } label: {
                Label("Weiter", systemImage: "play.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.space.xl)
                    .padding(.vertical, 14)
                    .background(DS.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(DS.space.lg)
    }

    /// Duolingo-style thin progress bar showing where we are in the current
    /// 10-card block. Fills with brand accent. 4pt tall, full width.
    private var sessionProgressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(DS.surface1)
                Rectangle()
                    .fill(DS.accent)
                    .frame(width: geo.size.width * progressFraction)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: sessionCount)
            }
        }
        .frame(height: 4)
    }

    private var progressFraction: CGFloat {
        guard plannedOpportunityCount > 0 else { return 0 }
        return CGFloat(min(sessionCount, plannedOpportunityCount)) / CGFloat(plannedOpportunityCount)
    }
    private var plannedOpportunityCount: Int {
        guard let plannedCardIDs else { return sessionTarget }
        return sessionCount + plannedCardIDs.filter { !reviewedCardIDs.contains($0) }.count
    }

    /// If today's streak is a milestone (3, 7, 14, 30, 100, 365) AND we
    /// haven't celebrated it yet, return that number. Marking-celebrated is
    /// persisted to AppSettings so multiple sessions on the same day don't
    /// re-trigger the banner.
    private var unseenStreakMilestone: Int? {
        let milestones = [3, 7, 14, 30, 100, 365]
        guard milestones.contains(currentStreak) else { return nil }
        let alreadyCelebrated = settings.first?.lastCelebratedStreak ?? 0
        return currentStreak > alreadyCelebrated ? currentStreak : nil
    }

    private func markStreakCelebrated(_ days: Int) {
        let row = settings.first ?? {
            let s = AppSettings()
            context.insert(s)
            return s
        }()
        row.lastCelebratedStreak = days
        do {
            try context.save()
        } catch {
            context.rollback()
            showPersistenceError(error)
        }
    }

    private func milestoneBanner(days: Int) -> some View {
        HStack(spacing: DS.space.md) {
            Image(systemName: "flame.fill")
                .font(.system(size: 32))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(days) Tage Serie!")
                    .font(.headline.weight(.bold))
                Text(milestoneSubtitle(days: days))
                    .font(.caption)
                    .opacity(0.9)
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(DS.space.md)
        .frame(maxWidth: .infinity)
        .background(DS.accent)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
    }

    private func milestoneSubtitle(days: Int) -> String {
        switch days {
        case 3: return "Drei Tage am Stück — Routine setzt sich."
        case 7: return "Eine Woche am Stück."
        case 14: return "Zwei Wochen — solide."
        case 30: return "Ein Monat. Beeindruckend."
        case 100: return "Hundert Tage. Außergewöhnlich."
        case 365: return "Ein ganzes Jahr. Wow."
        default: return ""
        }
    }

    /// Days in a row with at least one review *in this language* — the same
    /// definition as Fortschritt (`LearningDataCache.streak`).
    private var currentStreak: Int {
        let code = settings.first?.activeLanguageCode ?? ""
        let cal = Calendar.current
        var day = cal.startOfDay(for: .now)
        var streak = 0
        while true {
            let next = cal.date(byAdding: .day, value: 1, to: day) ?? day
            if !reviews.contains(where: {
                $0.timestamp >= day && $0.timestamp < next && $0.card?.phrase?.language?.code == code
            }) {
                break
            }
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return streak
    }

    // MARK: - Phase content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            loadingView.task { advance() }
        case .prompt(let card):
            PracticeStage {
            if mode == .flipDeToRu {
                flipCardScreen(card: card)
            } else if presentAsTiles(card) {
                tileConstructionScreen(card: card)
            } else if presentAsChoice(card) {
                // "Wählen" mode, or "Üben" easing a new card in via recognition.
                chooseCardScreen(card: card)
            } else {
                promptContent(card: card, revealed: false)
            }
            }
        case .study(let card):
            PracticeStage { promptContent(card: card, revealed: true) }
        case .reveal(let card, let result, let answer, let elapsedMs):
            revealContent(card: card, result: result, userAnswer: answer, responseTimeMs: elapsedMs)
        case .speakSentence(let card):
            speakSentenceScreen(card: card)
        case .empty:
            emptyContent
        }
    }

    // MARK: - Productive tile fallback

    private func tileConstructionScreen(card: StudyCard) -> some View {
        let isRTL = card.phrase?.language?.isRTL == true
        let selected = selectedTileIDs.compactMap { id in tileOptions.first { $0.id == id } }
        let remaining = tileOptions.filter { !selectedTileIDs.contains($0.id) }
        return VStack(spacing: DS.space.md) {
            resumeSpeakingBanner
            topicChips(card: card)
            heroPrompt(card: card)
            VStack(alignment: isRTL ? .trailing : .leading, spacing: DS.space.sm) {
                Text("Baue die Antwort")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.textSecondary)
                Group {
                    if selected.isEmpty {
                        Text("Tippe die Wörter in der richtigen Reihenfolge.")
                            .font(.subheadline)
                            .foregroundStyle(DS.textTertiary)
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 76), spacing: DS.space.xs)],
                            spacing: DS.space.xs
                        ) {
                            ForEach(selected) { tile in
                                Button(tile.text) {
                                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                    withAnimation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.78)) {
                                        selectedTileIDs.removeAll { $0 == tile.id }
                                    }
                                }
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, DS.space.sm)
                                .frame(minHeight: 42)
                                .frame(maxWidth: .infinity)
                                .background(DS.accent)
                                .clipShape(RoundedRectangle(cornerRadius: DS.radius.sm))
                                .matchedGeometryEffect(id: tile.id, in: tileNamespace)
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 70, alignment: isRTL ? .trailing : .leading)
                .padding(DS.space.md)
                .background(DS.surface1)
                .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
                .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: DS.space.sm)], spacing: DS.space.sm) {
                ForEach(remaining) { tile in
                    Button(tile.text) {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        withAnimation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.78)) {
                            selectedTileIDs.append(tile.id)
                        }
                    }
                        .font(.body.weight(.medium))
                        .foregroundStyle(DS.textPrimary)
                        .frame(minHeight: 48)
                        .frame(maxWidth: .infinity)
                        .background(DS.surface1)
                        .clipShape(RoundedRectangle(cornerRadius: DS.radius.sm))
                        .matchedGeometryEffect(id: tile.id, in: tileNamespace)
                        .buttonStyle(.plain)
                }
            }
            .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)

            HStack(spacing: DS.space.sm) {
                Button("Zurücksetzen") {
                    withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.2)) {
                        selectedTileIDs.removeAll()
                    }
                }
                    .buttonStyle(.bordered)
                    .tint(DS.textSecondary)
                    .disabled(selectedTileIDs.isEmpty)
                Button("Prüfen") {
                    let answer = TileConstruction.answer(selectedIDs: selectedTileIDs, from: tileOptions)
                    reviewModeOverride = .typeDeToRu
                    submit(revealed: false, answerOverride: answer)
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.accent)
                .disabled(!TileConstruction.isComplete(selectedIDs: selectedTileIDs, tiles: tileOptions)
                    || interactionGate.isBusy)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, DS.space.md)
        .onAppear { if promptStart == nil { promptStart = .now } }
    }

    // MARK: - Flip card mode

    private func flipCardScreen(card: StudyCard) -> some View {
        VStack(spacing: DS.space.md) {
            topicChips(card: card)

            FlipCardView(
                card: card,
                showTransliteration: shouldShowTransliteration,
                onRate: { rating in
                    recordFlipReview(card: card, rating: rating)
                }
            )
            .id(card.persistentModelID)  // forces fresh state per card

            HStack(spacing: DS.space.md) {
                Label("Wischen", systemImage: "arrow.left.and.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DS.textTertiary)
                Spacer()
                Button {
                    // Manual skip — rate as Again so it surfaces again later.
                    recordFlipReview(card: card, rating: 1)
                } label: {
                    Text("Überspringen")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DS.textSecondary)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, DS.space.md)
        .onAppear {
            if promptStart == nil { promptStart = .now }
        }
    }

    private func recordFlipReview(card: StudyCard, rating: Int) {
        guard case .prompt(let current) = phase,
              current === card,
              let token = interactionGate.begin(.persistence)
        else { return }
        do {
            let wasNew = card.state == .new && !reviews.contains { $0.card === card }
            try scheduler.record(rating: rating, on: card)

            let review = Review(
                card: card,
                rating: rating,
                autoGradeRating: rating,  // no auto-grader involved in flip mode
                userAnswer: "",
                mode: mode,
                responseTimeMs: Int((promptStart.map { Date.now.timeIntervalSince($0) } ?? 0) * 1000),
                gradeTier: 0,  // tier 0 = recognition flip, no character grading
                wasNew: wasNew
            )
            review.evidence = .init(support: .selfReported, inputWasSpeech: false, assessedCorrect: rating >= 3, gradingMethod: 0)
            review.evidence?.sessionID = persistedPlan?.id
            context.insert(review)
            try recordPracticeAnswer(review)
            try context.save()
            interactionGate.finish(token)
            persistenceErrorMessage = nil
        } catch {
            context.rollback()
            interactionGate.finish(token)
            showPersistenceError(error)
            return
        }

        promptStart = nil
        reviewedCardIDs.insert(card.contentID)
        sessionCount += 1
        if rating >= 3 { sessionCorrect += 1 }

        if sessionCount >= sessionTarget {
            showingSessionSummary = true
        } else {
            phase = .loading
        }
    }

    // MARK: - Choose (multiple-choice) mode

    private func chooseCardScreen(card: StudyCard) -> some View {
        let introducing = !card.hasBeenIntroduced && !choiceModelAcknowledged
        return VStack(spacing: DS.space.lg) {
            if let praise = surprisePraiseBanner { surpriseBanner(praise) }
            if mode == .speakDeToRu && speechMuted { resumeSpeakingBanner }
            if introducing {
                Text("Erst kennenlernen")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(DS.accentText)
                    .accessibilityIdentifier("practice-discovery")
            } else { topicChips(card: card) }
            heroPrompt(card: card)
            if introducing {
                headwordAnswerCard(card: card, discovery: true)
                Text("Schau dir die Formulierung an. Danach wählst du sie selbst aus.")
                    .font(.subheadline).foregroundStyle(DS.textSecondary)
                primaryButton(title: "Jetzt auswählen", disabled: false) {
                    tts.stop()
                    choiceModelAcknowledged = true
                    promptStart = .now
                }
                .accessibilityIdentifier("practice-discovery-next")
            } else {
                Spacer(minLength: 0)
                VStack(spacing: DS.space.sm) {
                    ForEach(choiceOptions, id: \.self) { option in
                        choiceButton(card: card, option: option)
                    }
                }
            }
        }
        .padding(.vertical, DS.space.md)
        .onAppear {
            if promptStart == nil { promptStart = .now }
        }
    }

    /// Shown while speaking is paused (the "I can't speak right now" fallback):
    /// a calm reminder + one tap back to the speak step.
    private var resumeSpeakingBanner: some View {
        Button {
            speechMuted = false
            phase = .loading
        } label: {
            HStack(spacing: DS.space.sm) {
                Image(systemName: "mic.slash.fill")
                Text("Leise üben").font(.caption.weight(.medium))
                Spacer()
                Text("Wieder sprechen").font(.caption.weight(.semibold))
                Image(systemName: "chevron.right").font(.caption2)
            }
            .foregroundStyle(DS.accentText)
            .padding(.horizontal, DS.space.md)
            .padding(.vertical, 10)
            .background(DS.accentSoft)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Leise üben. Tippen, um wieder zu sprechen.")
    }

    private func choiceButton(card: StudyCard, option: String) -> some View {
        let isCorrect = card.phrase?.targetText == option
        let answered = choiceChosen != nil
        let isChosen = choiceChosen == option
        let isRTL = card.phrase?.language?.isRTL == true

        // Colour states: neutral until answered; then the correct option goes
        // green, a wrong pick goes red, and the rest dim back.
        let fg: Color
        let bg: Color
        let border: Color
        if !answered {
            fg = DS.textPrimary; bg = DS.surface1; border = .clear
        } else if isCorrect {
            fg = DS.gradePerfect; bg = DS.gradePerfect.opacity(0.14); border = DS.gradePerfect
        } else if isChosen {
            fg = DS.gradeWrong; bg = DS.gradeWrong.opacity(0.14); border = DS.gradeWrong
        } else {
            fg = DS.textTertiary; bg = DS.surface1.opacity(0.5); border = .clear
        }

        return Button {
            selectChoice(card: card, option: option)
        } label: {
            HStack(spacing: DS.space.sm) {
                Text(option)
                    .font(LearningTypography.display(.title3, weight: .medium, languageCode: card.phrase?.language?.code))
                    .foregroundStyle(fg)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(isRTL ? .trailing : .leading)
                    .frame(maxWidth: .infinity, alignment: isRTL ? .trailing : .leading)
                if answered && isCorrect {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.gradePerfect)
                } else if answered && isChosen {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(DS.gradeWrong)
                }
            }
            .padding(.horizontal, DS.space.lg)
            .padding(.vertical, DS.space.md)
            .frame(maxWidth: .infinity)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radius.md)
                    .stroke(border, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(answered)
        .accessibilityHint(answered ? "" : "Antwortoption")
    }

    private func selectChoice(card: StudyCard, option: String) {
        guard case .prompt(let current) = phase,
              current === card,
              choiceChosen == nil,
              let token = interactionGate.begin(.choiceDelay)
        else { return }
        let elapsedMs = Int((promptStart.map { Date.now.timeIntervalSince($0) } ?? 0) * 1000)
        let correct = card.phrase?.targetText == option
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { choiceChosen = option }
        if correct {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            CompletionFeedbackService.shared.playStepSuccess(sound: !speechMuted)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        if !speechMuted {
            tts.speak(card.phrase?.targetText ?? "",
                      language: card.phrase.ttsLocaleOrDevice, times: 1)
        }

        // Brief feedback dwell — longer when wrong so the correct answer registers.
        let dwell: UInt64 = correct ? 850_000_000 : 1_700_000_000
        choiceDelayTask?.cancel()
        choiceDelayTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: dwell)
            } catch {
                return
            }
            guard interactionGate.accepts(token),
                  case .prompt(let current) = phase,
                  current === card
            else { return }
            recordChoiceReview(
                card: card,
                chosenAnswer: option,
                correct: correct,
                responseTimeMs: elapsedMs,
                token: token
            )
        }
    }

    private func recordChoiceReview(
        card: StudyCard,
        chosenAnswer: String,
        correct: Bool,
        responseTimeMs: Int,
        token: PracticeInteractionGate.Token
    ) {
        guard interactionGate.accepts(token) else { return }
        let rating = correct ? 3 : 1
        do {
            let wasNew = card.state == .new && !reviews.contains { $0.card === card }
            let review = Review(
                card: card,
                rating: rating,
                autoGradeRating: rating,
                userAnswer: chosenAnswer,
                mode: .chooseDeToRu,
                responseTimeMs: responseTimeMs,
                gradeTier: 0,   // recognition, no character grading
                wasNew: wasNew
            )
            review.evidence = .init(support: .recognition, inputWasSpeech: false, assessedCorrect: correct, gradingMethod: 0)
            review.evidence?.sessionID = persistedPlan?.id
            context.insert(review)
            try recordPracticeAnswer(review)
            try context.save()
            interactionGate.finish(token)
            persistenceErrorMessage = nil
        } catch {
            context.rollback()
            interactionGate.finish(token)
            choiceChosen = nil
            showPersistenceError(error)
            return
        }

        choiceChosen = nil
        promptStart = nil
        reviewedCardIDs.insert(card.contentID)
        sessionCount += 1
        if correct {
            sessionCorrect += 1
        }

        if sessionCount >= sessionTarget {
            showingSessionSummary = true
        } else {
            phase = .loading
        }
    }

    /// Bounded sampling of canonical lesson vocabulary, filtering known
    /// alternative answers and overlapping translations before presentation.
    private func makeChoiceOptions(for card: StudyCard, pool: [StudyCard]) -> [String] {
        guard let phrase = card.phrase else { return [] }
        func item(_ phrase: Phrase) -> MultipleChoice.Item {
            .init(source: phrase.sourceText, target: phrase.targetText,
                  language: phrase.language?.code ?? "", alternatives: phrase.acceptedAlternatives)
        }
        // Bound relationship reads; omitting a choice task is safer than filling
        // it with unrelated or known-equivalent answers.
        return MultipleChoice.options(correct: item(phrase),
            from: pool.shuffled().prefix(50).compactMap { $0.phrase }.map(item))
    }

    private var loadingView: some View {
        VStack(spacing: DS.space.md) {
            Spacer()
            ProgressView().controlSize(.large).tint(DS.accent)
            Spacer()
        }
    }

    // MARK: - Prompt / Study

    private func promptContent(card: StudyCard, revealed: Bool) -> some View {
        VStack(spacing: DS.space.lg) {
            if let saved = savedAlternativeBanner {
                savedBanner(saved)
            }
            if let praise = surprisePraiseBanner {
                surpriseBanner(praise)
            }

            topicChips(card: card)

            heroPrompt(card: card)

            if revealed {
                answerCard(card: card)
            }

            Spacer(minLength: 0)

            inputArea(revealed: revealed)

            // Typing mode keeps this in the keyboard accessory bar (see
            // typingInputSection) so it can't hide behind the keyboard; other
            // modes show it inline here.
            if !revealed && mode != .typeDeToRu && mode != .clozeDeToRu {
                Button {
                    showStudyMode()
                } label: {
                    Text("Antwort zeigen")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.textSecondary)
                        .underline()
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, DS.space.md)
        .onAppear {
            if promptStart == nil { promptStart = .now }
            if mode == .typeDeToRu || mode == .clozeDeToRu { inputFocused = true }
        }
    }

    private func topicChips(card: StudyCard) -> some View {
        VStack(alignment: .leading, spacing: DS.space.xs) {
            if contextTitle == nil, let topic = card.phrase?.topics?.first {
                Text(topic.name).font(.caption).foregroundStyle(DS.textSecondary)
            }
            Text(practiceInstruction(card))
                .font(.subheadline.weight(.medium)).foregroundStyle(DS.accentText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("practice-instruction")
    }

    private func practiceInstruction(_ card: StudyCard) -> String {
        if case .study = phase { return "Schau dir die Formulierung an und probiere sie aus." }
        if presentAsChoice(card) { return "Wähle die passende Formulierung." }
        if presentAsTiles(card) { return "Baue die passende Formulierung." }
        if mode == .clozeDeToRu { return "Ergänze die Formulierung." }
        return card.phrase?.language.map { "Wie sagst du das auf \($0.germanLabel)?" } ?? "Wie sagst du das?"
    }

    @ViewBuilder
    private func heroPrompt(card: StudyCard) -> some View {
        if mode == .clozeDeToRu, let cloze = clozeItem(for: card) {
            clozeHero(cloze, card: card)
        } else {
            germanHero(card: card)
        }
    }

    /// The gapped sentence, with the German translation underneath as the
    /// comprehension anchor — the learner reasons from meaning, not from a
    /// bare grammar puzzle.
    private func clozeHero(_ cloze: ClozeItem, card: StudyCard) -> some View {
        VStack(spacing: DS.space.md) {
            Text(cloze.prompt)
                .font(LearningTypography.display(
                    size: (cloze.prompt.count > 40 ? 24 : 30) * min(heroTypeScale, 1.5),
                    weight: .bold
                ))
                .multilineTextAlignment(.center)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            if let translation = cloze.translation {
                Text(translation)
                    .font(.subheadline)
                    .foregroundStyle(DS.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The headword is only a hint when the sentence needs a *different*
            // form. Showing it when the answer is the headword would hand the
            // answer over.
            if cloze.teachesInflection {
                Text(cloze.headword)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.accentText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(DS.accentSoft)
                    .clipShape(Capsule())
                    .accessibilityLabel("Grundform \(cloze.headword)")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.space.lg)
        .padding(.vertical, DS.space.xl)
        .dsFlashcardSurface()
    }

    private func germanHero(card: StudyCard) -> some View {
        // Learning content uses a modern rounded sans face. Editorial serif is
        // reserved for page greetings; mixing it into flashcards made Cyrillic
        // look like a legacy book typeface and broke the app-wide hierarchy.
        let text = card.phrase?.sourceText ?? "—"
        let base: CGFloat = text.count > 40 ? 22 : (text.count > 30 ? 28 : (text.count > 15 ? 34 : 42))
        let size = base * min(heroTypeScale, 1.5)
        return Text(text)
            .font(LearningTypography.display(size: size, weight: .bold))
            .multilineTextAlignment(.center)
            .foregroundStyle(DS.textPrimary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DS.space.lg)
            .padding(.vertical, DS.space.xxl)
            .dsFlashcardSurface()
            .accessibilityIdentifier("practice-prompt")
    }

    @ViewBuilder
    private func answerCard(card: StudyCard) -> some View {
        if mode == .clozeDeToRu, let cloze = clozeItem(for: card) {
            clozeAnswerCard(cloze, card: card)
        } else {
            headwordAnswerCard(card: card)
        }
    }

    /// On reveal the whole sentence comes back, so the ending is seen in the
    /// context that required it rather than as an isolated word.
    private func clozeAnswerCard(_ cloze: ClozeItem, card: StudyCard) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("Antwort")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.gradePerfect)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Button {
                    tts.speak(
                        cloze.sentence,
                        language: card.phrase.ttsLocaleOrDevice,
                        times: 1
                    )
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.callout)
                        .foregroundStyle(DS.gradePerfect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Satz vorlesen")
            }
            Text(cloze.answer)
                .font(LearningTypography.display(
                    .title2, weight: .bold,
                    languageCode: card.phrase?.language?.code
                ))
                .foregroundStyle(DS.textPrimary)
            Text(cloze.sentence)
                .font(.subheadline)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if cloze.teachesInflection {
                Text("Grundform: \(cloze.headword)")
                    .font(.caption)
                    .foregroundStyle(DS.textTertiary)
            }
        }
        .padding(DS.space.md)
        .frame(maxWidth: .infinity)
        .background(DS.gradePerfect.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
        .onAppear {
            if !speechMuted { tts.speak(cloze.sentence, language: card.phrase.ttsLocaleOrDevice, times: 1) }
        }
    }

    private func headwordAnswerCard(card: StudyCard, discovery: Bool = false) -> some View {
        let tint = discovery ? DS.accentText : DS.gradePerfect
        return VStack(spacing: 6) {
            HStack {
                Text(discovery ? "Formulierung" : "Antwort")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Button {
                    tts.speak(card.phrase?.targetText ?? "", language: card.phrase.ttsLocaleOrDevice, times: 2)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(tint)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Antwort vorlesen")
            }
            Text(card.phrase?.targetText ?? "")
                .font(LearningTypography.display(
                    .title2, weight: .medium,
                    languageCode: card.phrase?.language?.code
                ))
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            if shouldShowTransliteration, let translit = card.phrase?.transliteration {
                Text(translit)
                    .font(.footnote)
                    .foregroundStyle(DS.textTertiary)
            }
        }
        .padding(DS.space.md)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
        .onAppear { if !speechMuted { tts.speak(card.phrase?.targetText ?? "", language: card.phrase.ttsLocaleOrDevice, times: discovery ? 1 : 2) } }
    }

    @ViewBuilder
    private func inputArea(revealed: Bool) -> some View {
        switch mode {
        case .typeDeToRu:
            typingInputSection(revealed: revealed)
        case .speakDeToRu:
            if speechMuted {
                typingInputSection(revealed: revealed)
            } else {
                speakInputSection(revealed: revealed)
            }
        case .clozeDeToRu:
            typingInputSection(revealed: revealed)
        case .chooseDeToRu:
            typingInputSection(revealed: revealed) // No safe choice set: real recall.
        case .flipDeToRu:
            // These modes render their own full screen (FlipCardView /
            // chooseCardScreen), so there's no shared input area.
            EmptyView()
        }
    }

    @ViewBuilder
    private func typingInputSection(revealed: Bool) -> some View {
        // Return on the keyboard submits (`.submitLabel(.go)` shows "Los"); the
        // full-width Prüfen button is the visible fallback. "Ich weiß es nicht"
        // lives in the keyboard accessory bar so it can't hide behind the
        // keyboard (it has nowhere to go in the non-scrolling prompt layout).
        VStack(spacing: DS.space.sm) {
            TextField(activeLanguage?.inputPlaceholder ?? "Antwort tippen…", text: $input)
                .font(.title3)
                .textFieldStyle(.plain)
                .multilineTextAlignment(activeLanguage?.isRTL == true ? .trailing : .leading)
                .padding(.horizontal, DS.space.lg)
                .padding(.vertical, 18)
                .background(DS.surface1)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(inputFocused ? DS.accent : Color.black.opacity(0.08), lineWidth: 2)
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.go)
                .focused($inputFocused)
                .onSubmit { submit(revealed: revealed) }
                .toolbar {
                    if !revealed {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button {
                                showStudyMode()
                            } label: {
                                Text("Antwort zeigen")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(DS.accentText)
                            }
                        }
                    }
                }

            primaryButton(
                title: interactionGate.activeOperation == .grading ? "Wird geprüft…" : "Prüfen",
                disabled: input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || interactionGate.isBusy,
                action: { submit(revealed: revealed) }
            )
        }
    }

    /// Pill-shaped primary action button — Babbel-style fully rounded shape,
    /// Duolingo-style depth via subtle accent-coloured shadow. Disabled state
    /// uses neutral grey so it reads "waiting for input" not "broken".
    private func primaryButton(
        title: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            Text(title)
        }
        .buttonStyle(.dsPrimary)
        .disabled(disabled)
    }

    @ViewBuilder
    private func speakInputSection(revealed: Bool) -> some View {
        VStack(spacing: DS.space.sm) {
            if !speech.transcription.isEmpty {
                Text(speech.transcription)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(DS.space.md)
                    .background(DS.surface1)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
            }

            if let msg = speechErrorMessage {
                Text(msg)
                    .font(.footnote)
                    .foregroundStyle(DS.gradeWrong)
                    .multilineTextAlignment(.center)
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if speech.isRecording {
                    speech.stop()
                    submit(revealed: revealed)
                } else {
                    startRecording()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                    Text(speech.isRecording ? "Stoppen & Prüfen" : "Aufnahme starten")
                }
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    Capsule().fill(speech.isRecording ? DS.gradeWrong : DS.accent)
                )
                .shadow(
                    color: (speech.isRecording ? DS.gradeWrong : DS.accent).opacity(0.30),
                    radius: 8, x: 0, y: 4
                )
            }
            .buttonStyle(.plain)
            .disabled(interactionGate.isBusy && !speech.isRecording)

            if !revealed && !speech.isRecording {
                Button {
                    // Pause speaking for this session; keep practising via
                    // keyboard-free multiple-choice on the same cards.
                    speech.clearTranscription()
                    speechErrorMessage = nil
                    speechMuted = true
                    phase = .loading
                } label: {
                    Label("Ich kann gerade nicht sprechen", systemImage: "mic.slash")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.textSecondary)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func startRecording() {
        guard let token = interactionGate.begin(.permission) else { return }
        speechErrorMessage = nil
        input = ""
        permissionTask?.cancel()
        silenceTask?.cancel()
        permissionTask = Task { @MainActor in
            if speechAuthorized == nil {
                speechAuthorized = await speech.requestAuthorization()
            }
            guard !Task.isCancelled, interactionGate.accepts(token) else { return }
            guard speechAuthorized == true else {
                interactionGate.finish(token)
                speechErrorMessage = nil
                speechMuted = true
                phase = .loading
                return
            }
            do {
                try speech.start()
                interactionGate.finish(token)
            } catch {
                interactionGate.finish(token)
                speechErrorMessage = nil
                speechMuted = true
                phase = .loading
            }
        }
    }

    // MARK: - Reveal

    private func revealContent(
        card: StudyCard,
        result: GradeResult,
        userAnswer: String,
        responseTimeMs: Int
    ) -> some View {
        ScrollView {
            VStack(spacing: DS.space.md) {
                revealHero(card: card, result: result)
                revealAnswerCard(card: card, result: result)
                revealActions(card: card, result: result, userAnswer: userAnswer, responseTimeMs: responseTimeMs)
                if lastSubmissionWasSpeech, !userAnswer.isEmpty {
                    DisclosureGroup("Hinweise zur Spracherkennung") {
                        spokenRecallCard(card: card, userAnswer: userAnswer)
                    }.tint(DS.accentText)
                }
                if shouldShowTransliteration, let translit = card.phrase?.transliteration {
                    Text(translit)
                        .font(.footnote)
                        .foregroundStyle(DS.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                detailsDisclosure(card: card, result: result)
            }
            .padding(.vertical, DS.space.md)
        }
        .safeAreaInset(edge: .bottom) {
            primaryButton(title: "Weiter", disabled: interactionGate.isBusy) {
                confirm(rating: result.autoGrade.suggestedRating, card: card, result: result,
                        userAnswer: userAnswer, responseTimeMs: responseTimeMs)
            }
            .accessibilityIdentifier("practice-continue")
            .padding(.vertical, DS.space.sm)
            .background(DS.surface0)
        }
        .onAppear { if !speechMuted { tts.speak(card.phrase?.targetText ?? "", language: card.phrase.ttsLocaleOrDevice, times: 1) } }
    }

    private func spokenRecallCard(card: StudyCard, userAnswer: String) -> some View {
        let signal = SpokenRecallAnalyzer.analyze(
            expected: expectedAnswer(for: card),
            actual: userAnswer,
            segments: speech.segments,
            startDelaySec: speech.hesitancy.startDelaySec,
            longestPauseSec: speech.hesitancy.longestPauseSec
        )
        return VStack(alignment: .leading, spacing: DS.space.xs) {
            Label(
                signal.headline,
                systemImage: signal.isClearSignal ? "waveform.badge.checkmark" : "waveform.badge.magnifyingglass"
            )
            .font(.subheadline.weight(.bold))
            .foregroundStyle(signal.isClearSignal ? DS.gradePerfect : DS.accent)
            ForEach(signal.notes, id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(DS.textSecondary)
            }
            Text("Hinweis der Spracherkennung, keine phonetische Aussprachebewertung.")
                .font(.caption2)
                .foregroundStyle(DS.textTertiary)
            Button {
                tts.speak(
                    card.phrase?.targetText ?? "",
                    language: card.phrase.ttsLocaleOrDevice,
                    rate: 0.62
                )
            } label: {
                Label("Langsam anhören", systemImage: "tortoise.fill")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(DS.accentText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.space.sm)
        .background(DS.accentSoft.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
        .accessibilityElement(children: .combine)
    }

    /// Compact result summary. The answer, not an oversized grade, is central.
    private func revealHero(card: StudyCard, result: GradeResult) -> some View {
        let color = gradeColor(for: result.autoGrade)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.space.sm))
            : AnyLayout(HStackLayout(spacing: DS.space.md))
        return layout {
            Image(systemName: gradeIcon(for: result.autoGrade))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.18))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(result.autoGrade.label)
                    .font(.title3.bold())
                    .foregroundStyle(DS.textPrimary)
                Text(revealSubtitle(for: result.autoGrade))
                    .font(.caption)
                    .foregroundStyle(DS.textSecondary)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            Button {
                tts.speak(card.phrase?.targetText ?? "", language: card.phrase.ttsLocaleOrDevice, times: 2)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(DS.accentText)
                    .frame(width: 44, height: 44)
                    .background(DS.accentSoft)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Antwort vorlesen")
        }
        .padding(DS.space.md)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius.lg)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
        .id(result.autoGrade)
        .transition(.opacity)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: result.autoGrade
        )
    }

    /// Big-typography answer card so the correct Russian is the focal point
    /// after the grade. The character-level diff now lives in the collapsed
    /// Details disclosure below (build 24 — slimmer reveal).
    private func revealAnswerCard(card: StudyCard, result: GradeResult) -> some View {
        Text(card.phrase?.targetText ?? "")
            .font(LearningTypography.display(
                .title2, weight: .semibold,
                languageCode: card.phrase?.language?.code
            ))
            .foregroundStyle(DS.textPrimary)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(DS.space.md)
            .background(DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
    }

    /// FSRS stability (in days) at or above which a card counts as "really
    /// sitting" — the spoken sentence reinforcement drops away past this. New
    /// cards start at 0, so the sentence beat shows from the very first review
    /// and fades out only once the word is genuinely durable (~3 weeks).
    private let matureStabilityDays: Double = 21

    /// Whether to route through the spoken "say it in a sentence" screen after
    /// scoring this card. Only in Üben (the speaking mode), only while the card
    /// is still young, and only when we actually ship a sentence for the word.
    /// Keeps the spoken sentence on every review until the word is solid, then
    /// lets it go.
    private func shouldShowExampleSentence(_ card: StudyCard) -> Bool {
        mode == .speakDeToRu
            && card.stability < matureStabilityDays
            && (card.phrase?.exampleSentence?.isEmpty == false)
    }

    /// The contextual sentence that *uses* the just-learned word, presented as a
    /// shadowing step: the German meaning and the audio, the target text hidden
    /// until the learner has said it (or asks for it) — repeating from the ear,
    /// never reading aloud. An optional pronunciation line follows the text. Tinted with the accent so it reads as an action ("do
    /// this"), not just more reference text. More spoken output, concentrated on
    /// the words that aren't solid yet.
    @ViewBuilder
    private func exampleSentenceCard(card: StudyCard) -> some View {
        let phrase = card.phrase
        let sentence = phrase?.exampleSentence ?? ""
        let locale = phrase.ttsLocaleOrDevice
        VStack(alignment: .leading, spacing: DS.space.sm) {
            HStack(spacing: 6) {
                Image(systemName: "text.quote")
                    .font(.caption.weight(.bold))
                Text("Hör zu und sprich nach")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                Spacer()
                Button {
                    tts.speak(sentence, language: locale, times: 1)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.subheadline)
                        .foregroundStyle(DS.accentText)
                        .frame(width: 38, height: 38)
                        .background(DS.surface0)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Satz vorlesen")
            }
            .foregroundStyle(DS.accentText)

            if sentenceSpoken || sentencePeek {
                Text(sentence)
                    .font(LearningTypography.display(
                        .title3, weight: .semibold,
                        languageCode: phrase?.language?.code
                    ))
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if shouldShowTransliteration,
                   let translit = phrase?.exampleSentenceTransliteration, !translit.isEmpty {
                    Text(translit)
                        .font(.footnote)
                        .foregroundStyle(DS.textTertiary)
                }
            } else {
                Button("Satz zeigen") { sentencePeek = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.accentText)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("practice-sentence-peek")
            }

            if let translation = phrase?.exampleSentenceTranslation, !translation.isEmpty {
                Text(translation)
                    .font(.subheadline)
                    .foregroundStyle(DS.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.space.md)
        .background(DS.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius.md)
                .stroke(DS.accent.opacity(0.20), lineWidth: 1)
        )
    }

    /// "Now you say it." Shown after the score for a young card: the example
    /// sentence, audio to model it, and a mic that makes the user actually speak
    /// it aloud before moving on. Unscored — recording once is enough to reveal
    /// "Weiter"; a quiet "Überspringen" covers can't-speak-right-now moments.
    private func speakSentenceScreen(card: StudyCard) -> some View {
        let phrase = card.phrase
        let sentence = phrase?.exampleSentence ?? ""
        let locale = phrase.ttsLocaleOrDevice
        return VStack(spacing: DS.space.lg) {
            VStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(DS.accentText)
                    .frame(width: 64, height: 64)
                    .background(DS.accentSoft)
                    .clipShape(Circle())
                Text("Jetzt du – sprich den Satz nach")
                    .font(LearningTypography.display(.title3, weight: .bold))
                    .foregroundStyle(DS.textPrimary)
                Text("Nach dem Hören, ohne Vorlage. Wird nicht bewertet.")
                    .font(.caption)
                    .foregroundStyle(DS.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, DS.space.md)

            exampleSentenceCard(card: card)

            // Live transcription is feedback only ("the mic heard you"), never graded.
            if !speech.transcription.isEmpty {
                Text(speech.transcription)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(DS.space.md)
                    .background(DS.surface1)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
            }
            if let msg = speechErrorMessage {
                Text(msg)
                    .font(.footnote)
                    .foregroundStyle(DS.gradeWrong)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            // The mic is the forcing function: toggle record/stop; stopping marks
            // the sentence spoken, which reveals "Weiter".
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if speech.isRecording {
                    speech.stop()
                    // Unlock "Weiter" only if the mic actually picked you up
                    // saying it — not on a half-second of silence. Still
                    // unscored; "Überspringen" covers a mic that can't hear you.
                    if sentenceRecognizedEnough(card) {
                        sentenceSpoken = true
                        speechErrorMessage = nil
                    } else {
                        sentenceSpoken = false
                        speechErrorMessage = "Ich hab dich kaum gehört – sprich den ganzen Satz laut."
                    }
                } else {
                    startRecording()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                    Text(speech.isRecording
                         ? "Stoppen"
                         : (sentenceSpoken ? "Nochmal sprechen" : "Sprich den Satz"))
                }
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Capsule().fill(speech.isRecording ? DS.gradeWrong : DS.accent))
                .shadow(
                    color: (speech.isRecording ? DS.gradeWrong : DS.accent).opacity(0.30),
                    radius: 8, x: 0, y: 4
                )
            }
            .buttonStyle(.plain)

            if sentenceSpoken && !speech.isRecording {
                primaryButton(title: "Weiter", disabled: false) { finishSentence() }
            } else {
                Button {
                    finishSentence()
                } label: {
                    Text("Überspringen")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.textSecondary)
                        .underline()
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, DS.space.md)
        .onAppear {
            sentenceSpoken = false
            sentencePeek = false
            speech.clearTranscription()
            speechErrorMessage = nil
            tts.speak(sentence, language: locale, times: 1)
        }
    }

    private func revealSubtitle(for grade: AutoGrade) -> String {
        if !selectedTileIDs.isEmpty || restoredTileSupport, grade == .perfect || grade == .hesitant {
            return "Mit Wortbausteinen richtig zusammengesetzt."
        }
        switch grade {
        case .perfect:  return "Sauber gewusst."
        case .hesitant: return "Richtig aus dem Gedächtnis abgerufen."
        case .minor:    return "Ganz nah dran!"
        case .wrong:    return "Kein Stress – du siehst sie bald wieder."
        case .studied:  return "Angeschaut – das zählt auch."
        }
    }

    private func detailsDisclosure(card: StudyCard, result: GradeResult) -> some View {
        DisclosureGroup(isExpanded: $showingGradeDetails) {
            VStack(alignment: .leading, spacing: DS.space.sm) {
                DiffView(expected: expectedAnswer(for: card), actual: result.normalizedActual)
                VStack(alignment: .leading, spacing: 6) {
                    detailRow("Erwartet", result.normalizedExpected)
                    detailRow("Eingabe", result.normalizedActual)
                    detailRow("Bewertungsstufe", "\(result.tier)")
                    if result.editedWords > 0 {
                        detailRow("Wörter mit Abweichung", "\(result.editedWords)")
                        detailRow("Zeichenänderungen", "\(result.totalEdits)")
                    }
                }
                .font(.caption.monospaced())
                .foregroundStyle(DS.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DS.space.sm)
        } label: {
            Text("Details & Abgleich")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
        }
        .padding(.horizontal, DS.space.md)
        .padding(.vertical, DS.space.sm)
        .background(DS.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
    }

    // MARK: - Reveal actions

    /// One tap to accept the engine's auto-grade + a single contextual override —
    /// instead of a 4-way self-rating decision after every card. The grade is
    /// already shown in the hero ("Sitzt!" / "Fast" / "Noch nicht"); "Weiter"
    /// applies it. Mirrors how Duolingo trusts its auto-grade and only surfaces
    /// the "I was actually right" correction.
    @ViewBuilder
    private func revealActions(
        card: StudyCard,
        result: GradeResult,
        userAnswer: String,
        responseTimeMs: Int
    ) -> some View {
        let suggested = result.autoGrade.suggestedRating
        let recalled = suggested >= 3   // perfect / hesitant = recalled it
        VStack(spacing: DS.space.sm) {
            if lastSubmissionWasSpeech && !retryWasNeeded {
                Button {
                    retrySpokenAnswer(card)
                } label: {
                    Label("Noch einmal sagen", systemImage: "arrow.counterclockwise")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .tint(DS.accent)
                .disabled(interactionGate.isBusy)
            }
            // Contextual override: if it counted you right, let you mark it
            // shaky (sooner); if it counted you wrong, let you claim it — which
            // also saves your answer as an accepted alternative (in confirm()).
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                confirm(rating: recalled ? 2 : 3, card: card, result: result,
                        userAnswer: userAnswer, responseTimeMs: responseTimeMs)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: recalled ? "tortoise.fill" : "checkmark.circle")
                    Text(recalled ? "War schwerer – früher zeigen" : "Ich lag richtig")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DS.textSecondary)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .disabled(interactionGate.isBusy)
        }
        .padding(.top, DS.space.sm)
    }

    private func retrySpokenAnswer(_ card: StudyCard) {
        guard case .reveal(let current, let grade, let answer, _) = phase, current === card else { return }
        if !retryWasNeeded {
            firstRetryAnswer = answer
            firstRetryCorrect = grade.autoGrade.suggestedRating >= 3
        }
        invalidateInteraction()
        retryWasNeeded = true
        lastSubmissionWasSpeech = false
        speech.clearTranscription()
        input = ""
        promptStart = .now
        phase = .prompt(card)
    }

    private func gradeColor(for grade: AutoGrade) -> Color {
        switch grade {
        case .perfect: return DS.gradePerfect
        case .hesitant: return DS.gradePerfect
        case .minor: return DS.gradeMinor
        case .wrong: return DS.gradeWrong
        case .studied: return DS.accent
        }
    }

    private func gradeIcon(for grade: AutoGrade) -> String {
        switch grade {
        case .perfect: return "checkmark.circle.fill"
        case .hesitant: return "checkmark.circle"
        case .minor: return "checkmark.circle"        // "almost there", not a warning
        case .wrong: return "arrow.counterclockwise"  // "comes back around", not an X
        case .studied: return "book.fill"
        }
    }

    // MARK: - Empty

    @ViewBuilder
    private var emptyContent: some View {
        if stoppedByDailyLimit {
            dailyLimitContent
        } else {
            allDoneContent
        }
    }

    /// Hit the daily new-card target, but more new cards are waiting — be honest
    /// about why, and let the user keep going instead of implying they're "out".
    private var dailyLimitContent: some View {
        VStack(spacing: DS.space.md) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(DS.accentText)
            Text("Tagesziel erreicht")
                .font(.title2.weight(.semibold))
            Text("Du hast heute \(newCardsDoneToday) neue Ausdrücke gelernt. Es warten noch \(availableNewCount) in deinen aktiven Themen.")
                .font(.subheadline)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.space.lg)
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                newCardsUnlocked = true
                resetSession()
                phase = .loading
            } label: {
                Label("Weiter mit neuen Karten", systemImage: "arrow.right.circle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.space.lg)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(DS.accent))
                    .shadow(color: DS.accent.opacity(0.3), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            Text("Das Tageslimit kannst du in den Einstellungen ändern (Üben → Neue Ausdrücke pro Tag).")
                .font(.caption)
                .foregroundStyle(DS.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.space.lg)
            Spacer()
        }
    }

    private var allDoneContent: some View {
        VStack(spacing: DS.space.md) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 64))
                .foregroundStyle(DS.accentText)
            Text("Alles erledigt!")
                .font(.title2.weight(.semibold))
            Text("Keine fälligen Karten und keine neuen in deinen aktiven Themen. Aktiviere ein Thema oder importiere neue Vokabeln in der Bibliothek.")
                .font(.subheadline)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.space.lg)
            Button {
                showingLibrary = true
            } label: {
                Label("Bibliothek öffnen", systemImage: "books.vertical")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.space.lg)
                    .padding(.vertical, 12)
                    .background(DS.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    // MARK: - Saved banner

    private func savedBanner(_ saved: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
            (Text("Antwort gemerkt: ")
                .foregroundStyle(DS.textSecondary)
                + Text("„\(saved)\"").italic())
        }
        .font(.footnote)
        .foregroundStyle(DS.gradePerfect)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DS.gradePerfect.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Session summary

    private var sessionSummarySheet: some View {
        ScrollView {
        VStack(spacing: DS.space.lg) {
            if let persistenceErrorMessage {
                persistenceErrorBanner(persistenceErrorMessage)
            }
            if let milestone = unseenStreakMilestone {
                milestoneBanner(days: milestone)
                    .onAppear { markStreakCelebrated(milestone) }
            }
            if sessionCount > 0 && persistenceErrorMessage == nil {
                CompletionCelebration(title: "Yes! Runde geschafft!",
                    detail: "\(sessionCount) Antworten geübt. Das hast du dir erarbeitet.")
            }
            VStack(spacing: DS.space.xs) {
                Text(sessionSpokenAnswers > 0 ? "In dieser Runde gesprochen" : "In dieser Runde geübt")
                    .font(.headline)
                    .foregroundStyle(DS.textPrimary)
                Text("\(sessionSpokenAnswers > 0 ? sessionSpokenAnswers : sessionCount)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.accentText)
                Text(sessionSpokenAnswers > 0 ? "Antworten · \(sessionSpokenWords) Wörter" : "Ausdrücke · \(sessionCorrect) richtige Antworten")
                    .font(.subheadline)
                    .foregroundStyle(DS.textSecondary)
            }
            if let recalled = sessionNewlyRecalled.first {
                recapRow(
                    icon: "sparkles",
                    title: "Neu abrufbar",
                    detail: "„\(recalled)“",
                    color: DS.gradePerfect
                )
            }
            if let sessionNewRecord {
                recapRow(
                    icon: "timer",
                    title: "Neue persönliche Bestzeit",
                    detail: "„\(sessionNewRecord.source)“ · \(String(format: "%.1f", Double(sessionNewRecord.milliseconds) / 1_000)) s",
                    color: DS.gradeHesitant
                )
            }
            if let sessionCompletedMission {
                recapRow(
                    icon: "checkmark.seal.fill",
                    title: "Thema gesprächsbereit",
                    detail: sessionCompletedMission,
                    color: DS.gradePerfect
                )
            }
            recapRow(
                icon: sessionNeedsWork == 0 ? "checkmark.circle" : "arrow.clockwise",
                title: sessionNeedsWork == 0 ? "Sicher durch die Runde" : "Noch unsicher",
                detail: sessionNeedsWork == 0
                    ? sessionAccuracyMessage
                    : "\(sessionNeedsWork) \(sessionNeedsWork == 1 ? "Ausdruck kommt" : "Ausdrücke kommen") bald wieder.",
                color: sessionNeedsWork == 0 ? DS.gradePerfect : DS.gradeHesitant
            )
            Spacer()
            Button {
                resetSession()
                showingSessionSummary = false
                phase = .loading
            } label: {
                Text("Weiter üben")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(DS.accent)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            Button("Fertig") {
                resetSession()
                showingSessionSummary = false
                dismiss()
            }
            .foregroundStyle(DS.textSecondary)
            .padding(.bottom)
        }
        .padding()
        }
        .background(DS.pageBackground)
        .onAppear {
            if !playedSummarySound && sessionCount > 0 && persistenceErrorMessage == nil { CompletionFeedbackService.shared.playCompletion(sound: !speechMuted) }
            playedSummarySound = true
        }
    }

    private func recapRow(icon: String, title: String, detail: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: DS.space.sm) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(DS.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, DS.space.md)
    }

    /// Informational, not a slot machine: one plain message per band.
    private var sessionAccuracyMessage: String {
        let pct = sessionCount == 0 ? 0 : Int((Double(sessionCorrect) / Double(sessionCount)) * 100)
        switch pct {
        case 90...: return "Fast alles gewusst."
        case 70...: return "Solide Runde."
        case 50...: return "Die schwierigen kommen bald wieder."
        default: return "Schwierige Runde – die Ausdrücke kommen bald wieder."
        }
    }

    // MARK: - Deterministic lifecycle

    private func invalidateInteraction() {
        gradingTask?.cancel()
        choiceDelayTask?.cancel()
        permissionTask?.cancel()
        gradingTask = nil
        choiceDelayTask = nil
        permissionTask = nil
        silenceTask?.cancel()
        silenceTask = nil
        interactionGate.invalidate()
        choiceChosen = nil
        if speech.isRecording { speech.stop() }
        tts.stop()
        persistenceErrorMessage = nil
    }

    /// Once recognition has produced words and then remains unchanged, finish
    /// naturally. The visible Stop button remains available as an immediate
    /// fallback, and every scheduled completion is cancelled on navigation or
    /// lifecycle changes by `invalidateInteraction()`.
    private func scheduleSilenceCompletion(after transcription: String) {
        silenceTask?.cancel()
        guard speech.isRecording,
              !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        let snapshot = transcription
        let lifecycleID = interactionGate.lifecycleID
        silenceTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
            guard interactionGate.accepts(lifecycleID: lifecycleID),
                  speech.isRecording,
                  speech.transcription == snapshot
            else { return }
            switch phase {
            case .prompt(_):
                speech.stop()
                submit(revealed: false)
            case .study(_):
                speech.stop()
                submit(revealed: true)
            case .speakSentence(let card):
                speech.stop()
                if sentenceRecognizedEnough(card) {
                    sentenceSpoken = true
                    speechErrorMessage = nil
                }
            default:
                break
            }
        }
    }

    private func phaseContains(_ card: StudyCard) -> Bool {
        switch phase {
        case .prompt(let current), .study(let current),
             .reveal(let current, _, _, _), .speakSentence(let current):
            return current === card
        case .loading, .empty:
            return false
        }
    }

    private func showPersistenceError(_ error: Error) {
        persistenceErrorMessage = "Dein Fortschritt konnte nicht gespeichert werden. Bitte versuche es erneut."
        #if DEBUG
        print("Failed to persist practice progress: \(error)")
        #endif
    }

    private func persistenceErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: DS.space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DS.gradeWrong)
            Text(message)
                .font(.footnote)
                .foregroundStyle(DS.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                persistenceErrorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DS.textSecondary)
            }
            .accessibilityLabel("Fehlermeldung schließen")
        }
        .padding(DS.space.sm)
        .background(DS.gradeWrong.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.sm))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Logic

    private func submit(revealed: Bool, answerOverride: String? = nil) {
        guard let token = interactionGate.begin(.grading) else { return }
        let card: StudyCard
        switch phase {
        case .prompt(let c), .study(let c): card = c
        default:
            interactionGate.finish(token)
            return
        }
        let elapsedMs = Int((promptStart.map { Date.now.timeIntervalSince($0) } ?? 0) * 1000)
        let expected = expectedAnswer(for: card)
        // The phrase's accepted alternatives are alternatives for the *headword*
        // and say nothing about the inflected form the sentence needs.
        let alternatives = mode == .clozeDeToRu ? [] : (card.phrase?.acceptedAlternatives ?? [])
        let userAnswer = answerOverride ?? ((mode == .speakDeToRu && !speechMuted) ? speech.transcription : input)
        if speechMuted && mode == .speakDeToRu { reviewModeOverride = .typeDeToRu }
        lastSubmissionWasSpeech = answerOverride == nil
            && mode == .speakDeToRu
            && !speechMuted
            && !speech.transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let useJudge = settings.first?.useAIGradingAssist == true
        inputFocused = false

        gradingTask?.cancel()
        gradingTask = Task { @MainActor in
            let gradingStartedAt = Date.now
            let baseline = await grader.gradeWithJudge(
                german: card.phrase?.sourceText ?? "",
                expected: expected,
                actual: userAnswer,
                acceptedAlternatives: alternatives,
                responseTimeMs: elapsedMs,
                useJudge: useJudge,
                targetLanguage: card.phrase?.language?.germanLabel ?? "der Zielsprache"
            )
            guard !Task.isCancelled,
                  interactionGate.accepts(token),
                  phaseContains(card)
            else { return }
            gradingWaitMs = max(0, Int(Date.now.timeIntervalSince(gradingStartedAt) * 1000))
            interactionGate.finish(token)
            finalize(
                card: card,
                baseline: baseline,
                revealed: revealed,
                applySpeechHesitancy: lastSubmissionWasSpeech,
                userAnswer: userAnswer,
                elapsedMs: elapsedMs
            )
        }
    }

    private func finalize(
        card: StudyCard,
        baseline: GradeResult,
        revealed: Bool,
        applySpeechHesitancy: Bool,
        userAnswer: String,
        elapsedMs: Int
    ) {
        var result = baseline
        if revealed {
            // Study-mode copy-typing: SRS-wise still rating 1 (didn't recall)
            // but the UI grade is .studied when the copy is correct — an
            // encouraging label rather than .wrong. They did real work.
            let copiedCorrectly = result.normalizedActual == result.normalizedExpected
            result = GradeResult(
                autoGrade: copiedCorrectly ? .studied : .wrong,
                tier: result.tier,
                normalizedExpected: result.normalizedExpected,
                normalizedActual: result.normalizedActual,
                editedWords: result.editedWords,
                totalEdits: result.totalEdits
            )
        } else if retryWasNeeded && (result.autoGrade == .perfect || result.autoGrade == .hesitant) {
            result = GradeResult(
                autoGrade: .minor,
                tier: result.tier,
                normalizedExpected: result.normalizedExpected,
                normalizedActual: result.normalizedActual,
                editedWords: result.editedWords,
                totalEdits: result.totalEdits
            )
        } else if mode == .speakDeToRu, applySpeechHesitancy, result.autoGrade == .perfect {
            let h = speech.hesitancy
            if h.startDelaySec > speakHesitantStartDelaySec || h.longestPauseSec > speakHesitantPauseSec {
                result = GradeResult(
                    autoGrade: .hesitant,
                    tier: result.tier,
                    normalizedExpected: result.normalizedExpected,
                    normalizedActual: result.normalizedActual,
                    editedWords: result.editedWords,
                    totalEdits: result.totalEdits
                )
            }
        }
        inputFocused = false
        guard saveAttemptCheckpoint(card: card, result: result, answer: userAnswer, elapsed: elapsedMs,
                                    support: !selectedTileIDs.isEmpty ? .tiles : (answerWasRevealed ? .revealed : retryWasNeeded ? .retry : .none)) else { return }
        if !revealed && result.autoGrade.suggestedRating >= 3 {
            CompletionFeedbackService.shared.playStepSuccess(sound: !speechMuted)
        }
        phase = .reveal(card, result, userAnswer: userAnswer, responseTimeMs: elapsedMs)
    }

    private func showStudyMode() {
        guard case .prompt(let card) = phase else { return }
        guard saveAttemptCheckpoint(card: card, result: nil, answer: "", elapsed: 0, support: .revealed) else { return }
        answerWasRevealed = true
        phase = .study(card)
    }

    private func confirm(
        rating: Int,
        card: StudyCard,
        result: GradeResult,
        userAnswer: String,
        responseTimeMs: Int
    ) {
        guard case .reveal(let current, _, _, _) = phase,
              current === card,
              let token = interactionGate.begin(.persistence)
        else { return }
        var savedAlternative: String?
        let wasNewBeforeReview = card.state == .new && !reviews.contains { $0.card === card }
        let exerciseMode = reviewModeOverride ?? mode
        let cardLanguageCode = card.phrase?.language?.code
        let priorEvents = LearningMotivation.events(from: reviews.filter {
            $0.card?.phrase?.language?.code == cardLanguageCode
        })
        do {
            let wasNew = wasNewBeforeReview
            let support: AttemptEvidence.Support = (!selectedTileIDs.isEmpty || restoredTileSupport) ? .tiles
                : (answerWasRevealed ? .revealed : (retryWasNeeded ? .retry : .none))
            if support != .tiles {
                // A retry cannot erase the first failure; copied answers aren't recall.
                try scheduler.record(rating: support == .none ? rating : 1, on: card)
            }

            if rating >= 3, result.autoGrade.suggestedRating < 3, let phrase = card.phrase {
                let normalized = FuzzyMatcher.normalize(userAnswer)
                if !normalized.isEmpty,
                   normalized != phrase.targetTextNormalized,
                   !phrase.acceptedAlternatives.contains(where: { FuzzyMatcher.normalize($0) == normalized }) {
                    phrase.acceptedAlternatives.append(userAnswer)
                    savedAlternative = userAnswer
                }
            }

            let review = Review(
                card: card,
                rating: rating,
                autoGradeRating: result.autoGrade.suggestedRating,
                userAnswer: userAnswer,
                mode: exerciseMode,
                responseTimeMs: responseTimeMs,
                gradeTier: result.tier,
                wasNew: wasNew
            )
            review.evidence = AttemptEvidence(
                support: rating != result.autoGrade.suggestedRating ? .selfReported : support,
                inputWasSpeech: lastSubmissionWasSpeech,
                assessedCorrect: result.autoGrade.suggestedRating >= 3,
                gradingMethod: result.tier
            )
            review.evidence?.firstAnswer = firstRetryAnswer
            review.evidence?.inputAvailableMs = inputAvailableMs
            review.evidence?.gradingWaitMs = gradingWaitMs
            review.evidence?.timingInterrupted = timingInterrupted
            review.evidence?.sessionID = persistedPlan?.id
            review.evidence?.firstCorrect = firstRetryCorrect
            review.evidence?.previousExposureAt = reviews.filter { $0.card === card }.map(\.timestamp).max()
            if let barrier = try settings.first?.readExperience().otherModeExposureAt?[cardLanguageCode ?? "ru"] {
                review.evidence?.previousExposureAt = max(review.evidence?.previousExposureAt ?? .distantPast, barrier)
            }
            context.insert(review)
            try recordPracticeAnswer(review)
            try context.save()
            interactionGate.finish(token)
            persistenceErrorMessage = nil
        } catch {
            context.rollback()
            interactionGate.finish(token)
            showPersistenceError(error)
            return
        }
        if let savedAlternative { showSavedBanner(for: savedAlternative) }
        captureMeaningfulSessionEvents(
            card: card,
            result: result,
            rating: rating,
            responseTimeMs: responseTimeMs,
            exerciseMode: exerciseMode,
            priorEvents: priorEvents
        )

        input = ""
        speech.clearTranscription()
        promptStart = nil
        reviewedCardIDs.insert(card.contentID)
        sessionCount += 1
        if rating >= 3 {
            sessionCorrect += 1
            let independent = selectedTileIDs.isEmpty && !restoredTileSupport && !retryWasNeeded && !answerWasRevealed
                && rating == result.autoGrade.suggestedRating
            consecutiveProductiveRecalls = independent ? consecutiveProductiveRecalls + 1 : 0
            if independent, wasNewBeforeReview,
               let phrase = card.phrase?.targetText,
               !sessionNewlyRecalled.contains(phrase) {
                sessionNewlyRecalled.append(phrase)
            }
            if independent { maybeCelebrateProductiveRun() }
        } else {
            consecutiveProductiveRecalls = 0
            sessionNeedsWork += 1
        }
        if exerciseMode == .speakDeToRu,
           !userAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sessionSpokenAnswers += 1
            sessionSpokenWords += max(1, userAnswer.split(whereSeparator: { $0.isWhitespace }).count)
        }

        // Young card with a sentence we ship? Detour through the spoken
        // "say it in a sentence" screen before advancing or ending the session.
        // `record(...)` above already updated stability, so the gate uses the
        // post-review value — a card that just matured won't get the detour.
        if shouldShowExampleSentence(card) && !speechMuted {
            sentenceSpoken = false
            phase = .speakSentence(card)
        } else if sessionCount >= sessionTarget {
            showingSessionSummary = true
        } else {
            phase = .loading
        }
    }

    private func captureMeaningfulSessionEvents(
        card: StudyCard,
        result: GradeResult,
        rating: Int,
        responseTimeMs: Int,
        exerciseMode: CardDirection,
        priorEvents: [LearningEvent]
    ) {
        guard rating >= 3,
              result.autoGrade.suggestedRating >= 3,
              selectedTileIDs.isEmpty, !restoredTileSupport, !retryWasNeeded,
              !answerWasRevealed, rating == result.autoGrade.suggestedRating,
              responseTimeMs > 0,
              exerciseMode == .speakDeToRu || exerciseMode == .typeDeToRu,
              let phrase = card.phrase
        else { return }

        let priorBest = LearningMotivation.fastestStrongRecall(events: priorEvents)?.responseTimeMs
        if priorBest == nil || responseTimeMs < priorBest! {
            sessionNewRecord = (phrase.sourceText, responseTimeMs)
        }

        let phraseID = phrase.contentID
        for topic in phrase.topics ?? [] {
            let topicPhraseIDs = Set((topic.phrases ?? []).map(\.contentID))
            let priorFraction = LearningMotivation.strongRecallFraction(
                events: priorEvents,
                phraseIDs: topicPhraseIDs
            )
            guard priorFraction < 0.8 else { continue }
            var strongIDs = Set(priorEvents.filter(\.isStrongProductiveRecall).map(\.phraseID))
            strongIDs.insert(phraseID)
            let newFraction = Double(strongIDs.intersection(topicPhraseIDs).count)
                / Double(max(1, topicPhraseIDs.count))
            if newFraction >= 0.8 {
                sessionCompletedMission = topic.name
                break
            }
        }
    }

    /// Did the recogniser actually pick up the user saying the sentence? We
    /// don't check *correctness* — just that a few words were heard, so "Weiter"
    /// can't be unlocked by tapping record→stop in silence. Lenient by design
    /// (the sentence is usually 4–8 words, and on-device ASR drops some);
    /// "Überspringen" stays as the escape when the mic genuinely can't hear you.
    private func sentenceRecognizedEnough(_ card: StudyCard) -> Bool {
        let heard = speech.transcription
            .split(whereSeparator: { $0.isWhitespace })
            .filter { !$0.isEmpty }
            .count
        let targetWords = (card.phrase?.exampleSentence ?? "")
            .split(whereSeparator: { $0.isWhitespace })
            .filter { !$0.isEmpty }
            .count
        return heard >= max(1, min(2, targetWords))
    }

    /// Advance out of the "say it in a sentence" screen: same end-of-card
    /// branch as `confirm`, just deferred until after the user has spoken.
    private func finishSentence() {
        speech.stop()
        speech.clearTranscription()
        speechErrorMessage = nil
        tts.stop()
        sentenceSpoken = false
        if sessionCount >= sessionTarget {
            showingSessionSummary = true
        } else {
            phase = .loading
        }
    }

    /// Event-based feedback only: every claim corresponds to a measured run of
    /// productive recalls. Recognition-only introductions never increment it.
    private func maybeCelebrateProductiveRun() {
        guard settings.first?.surpriseRewardsEnabled ?? true else { return }
        guard [3, 5, 10].contains(consecutiveProductiveRecalls) else { return }
        let praise = "\(consecutiveProductiveRecalls) selbst abgerufen — stark."
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.7)) {
            surprisePraiseBanner = praise
        }
        praiseTask?.cancel()
        praiseTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 2_500_000_000)
            } catch {
                return
            }
            withAnimation(.easeOut(duration: 0.3)) {
                surprisePraiseBanner = nil
            }
        }
    }

    private func surpriseBanner(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, DS.space.md)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [DS.accent, DS.gradePerfect],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
            .shadow(color: DS.accent.opacity(0.3), radius: 8, y: 3)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func resetSession() {
        plannedCardIDs = nil
        persistedPlan = nil
        playedSummarySound = false
        sessionCount = 0
        sessionCorrect = 0
        consecutiveProductiveRecalls = 0
        sessionSpokenAnswers = 0
        sessionSpokenWords = 0
        sessionNewlyRecalled = []
        sessionNeedsWork = 0
        sessionNewRecord = nil
        sessionCompletedMission = nil
        reviewedCardIDs = []
    }

    private func advance() {
        // Cancel any in-flight TTS so a half-finished reveal doesn't keep
        // speaking after the next prompt has already appeared.
        invalidateInteraction()
        refreshTutorPriority()
        showingGradeDetails = false
        choiceChosen = nil
        selectedTileIDs = []
        reviewModeOverride = nil
        lastSubmissionWasSpeech = false
        retryWasNeeded = false
        firstRetryAnswer = nil
        firstRetryCorrect = nil
        restoredTileSupport = false
        inputAvailableMs = nil
        gradingWaitMs = nil
        timingInterrupted = false
        answerWasRevealed = false
        var pool: [StudyCard]
        switch scope {
        case .difficultThisWeek:
            pool = difficultCards
        case .recommended:
            pool = cardsForActiveLanguage
        case .topic, .scenario:
            pool = cardsForActiveLanguage.filter(scope.includes)
        }
        if mode == .clozeDeToRu {
            // Not every phrase ships a sentence we can gap, so this mode draws
            // from a narrower pool. The scheduler still owns the ordering.
            pool = pool.filter { clozeItem(for: $0) != nil }
        }
        let next: StudyCard?
        do {
            if plannedCardIDs == nil {
                do {
                    guard let row = settings.first else { return }
                    var data = try row.readExperience()
                    let language = activeLanguage?.code ?? "ru"
                    let reusable = (data.practicePlans ?? []).last {
                        $0.canResume(language: language, scope: scope.planKey, mode: mode, budget: sessionTarget, endedIDs: data.endedPlanIDs ?? [])
                        && !$0.remaining(in: pool, reviews: reviews).isEmpty
                    }
                    let supplied = suppliedPlan.flatMap { $0.canResume(language: language, scope: scope.planKey, mode: mode, budget: sessionTarget, endedIDs: data.endedPlanIDs ?? []) && !$0.remaining(in: pool, reviews: reviews).isEmpty ? $0 : nil }
                    let plan = reusable ?? supplied ?? PracticePlan.make(cards: pool, reviews: reviews,
                        language: language, scope: scope.planKey, mode: mode, budget: sessionTarget,
                        dailyLimit: effectiveDailyLimit, tutorIDs: tutorPriorityPhraseIDs)
                    if !(data.practicePlans ?? []).contains(where: { $0.id == plan.id }) {
                        data.practicePlans = (data.practicePlans ?? []) + [plan]
                        data.events.append(.init(name: "practice_started", language: language, sessionID: plan.id, timestamp: .now, stepID: nil))
                        try row.writeExperience(data)
                        try context.save()
                    }
                    persistedPlan = plan
                    let remaining = plan.remaining(in: pool, reviews: reviews, dailyNewLimit: effectiveDailyLimit)
                    plannedCardIDs = remaining.map(\.contentID)
                    let prior = reviews.filter { $0.evidence?.sessionID == plan.id }
                    sessionCount = prior.count
                    sessionCorrect = prior.filter { $0.rating >= 3 }.count
                    sessionSpokenAnswers = prior.filter { $0.evidence?.inputWasSpeech == true }.count
                    sessionSpokenWords = prior.filter { $0.evidence?.inputWasSpeech == true }.reduce(0) { $0 + $1.userAnswer.split(whereSeparator: \.isWhitespace).count }
                } catch {
                    context.rollback()
                    showPersistenceError(error)
                    return
                }
            }
            let byID = Dictionary(pool.map { ($0.contentID, $0) }, uniquingKeysWith: { first, _ in first })
            next = plannedCardIDs?.filter { !reviewedCardIDs.contains($0) }.compactMap { byID[$0] }.first
        }
        if let next {
            if restoreAttemptCheckpoint(for: next) { return }
            choiceOptions = []
            choiceModelAcknowledged = false
            if presentAsTiles(next) {
                tileOptions = makeTileOptions(for: next)
            } else if requestsChoice(next) {
                choiceOptions = makeChoiceOptions(for: next, pool: pool)
                if choiceOptions.isEmpty && mode == .chooseDeToRu { reviewModeOverride = .typeDeToRu }
                if !choiceOptions.isEmpty && !next.hasBeenIntroduced {
                    // Record exposure before showing the model. Interruption
                    // resumes as supported study, never as unaided recall.
                    guard saveAttemptCheckpoint(card: next, result: nil, answer: "", elapsed: 0,
                                                support: .revealed) else { return }
                    answerWasRevealed = true
                }
            }
            phase = .prompt(next)
        } else {
            if sessionCount > 0 {
                showingSessionSummary = true
            } else {
                phase = .empty
            }
        }
    }

    private func saveAttemptCheckpoint(card: StudyCard, result: GradeResult?, answer: String, elapsed: Int,
                                       support: AttemptEvidence.Support) -> Bool {
        guard let plan = persistedPlan, let row = settings.first else { return true }
        do {
            var data = try row.readExperience()
            let previous = data.cardAttempts?.last { $0.planID == plan.id && $0.cardKey == PracticePlan.key(card) }
            var checkpoint = CardAttemptCheckpoint(planID: plan.id, cardKey: PracticePlan.key(card), result: result,
                answer: answer, responseTimeMs: elapsed, support: support, spoken: lastSubmissionWasSpeech,
                firstAnswer: previous?.firstAnswer ?? (result == nil ? nil : answer),
                firstCorrect: previous?.firstCorrect ?? result.map { $0.autoGrade.suggestedRating >= 3 },
                reviewMode: reviewModeOverride?.rawValue)
            if let previous { checkpoint.id = previous.id }
            checkpoint.inputAvailableMs = inputAvailableMs
            checkpoint.gradingWaitMs = gradingWaitMs
            checkpoint.timingInterrupted = timingInterrupted
            data.save(checkpoint)
            try row.writeExperience(data)
            try context.save()
            return true
        } catch { context.rollback(); showPersistenceError(error); return false }
    }

    private func restoreAttemptCheckpoint(for card: StudyCard) -> Bool {
        guard let plan = persistedPlan,
              let data = try? settings.first?.readExperience(),
              let checkpoint = data.cardAttempts?.last(where: { $0.planID == plan.id && $0.cardKey == PracticePlan.key(card) }) else { return false }
        firstRetryAnswer = checkpoint.firstAnswer
        firstRetryCorrect = checkpoint.firstCorrect
        retryWasNeeded = checkpoint.support == .retry
        answerWasRevealed = checkpoint.support == .revealed
        lastSubmissionWasSpeech = checkpoint.spoken
        reviewModeOverride = checkpoint.reviewMode.flatMap(CardDirection.init(rawValue:))
        // Retain tile support without rebuilding/shuffling the old tile bank.
        restoredTileSupport = checkpoint.support == .tiles
        inputAvailableMs = checkpoint.inputAvailableMs
        gradingWaitMs = checkpoint.gradingWaitMs
        timingInterrupted = checkpoint.timingInterrupted ?? true
        if let result = checkpoint.result {
            phase = .reveal(card, result, userAnswer: checkpoint.answer, responseTimeMs: checkpoint.responseTimeMs)
        } else { phase = .study(card) }
        return true
    }

    private func markInputAvailable(_ text: String) {
        guard inputAvailableMs == nil, !text.isEmpty, let promptStart else { return }
        inputAvailableMs = max(0, Int(Date.now.timeIntervalSince(promptStart) * 1000))
    }

    private func recordPracticeAnswer(_ review: Review) throws {
        guard let row = settings.first, let evidence = review.evidence else { return }
        var data = try row.readExperience()
        guard !data.events.contains(where: { $0.id == evidence.id }) else { return }
        let language = review.card?.phrase?.language?.code ?? "ru"
        let session = persistedPlan?.id ?? evidence.id
        data.events.append(.init(id: evidence.id, name: "practice_answer", language: language,
            sessionID: session, timestamp: review.timestamp, stepID: nil,
            activeSeconds: min(60, max(0, activeSince.map { Date.now.timeIntervalSince($0) } ?? 0))))
        if let plan = persistedPlan, plan.remaining(in: cards, reviews: reviews + [review]).isEmpty,
           !data.events.contains(where: { $0.sessionID == plan.id && $0.name == "practice_completed" }) {
            data.events.append(.init(name: "practice_completed", language: language, sessionID: plan.id, timestamp: .now, stepID: nil))
        }
        try row.writeExperience(data)
        activeSince = .now
    }

    @discardableResult private func recordLifecycle(_ name: String) -> Bool {
        guard let plan = persistedPlan else { return true }
        do {
            guard let row = settings.first else { return false }
            var data = try row.readExperience()
            if (data.endedPlanIDs ?? []).contains(plan.id) || data.events.contains(where: { $0.sessionID == plan.id && $0.name == "practice_completed" }) { return true }
            let previous = data.events.last { $0.sessionID == plan.id }
            if previous?.name == name { return true }
            if name == "session_ended" { data.endedPlanIDs = (data.endedPlanIDs ?? []) + [plan.id] }
            data.events.append(.init(name: name, language: plan.language, sessionID: plan.id, timestamp: .now, stepID: nil,
                activeSeconds: min(60, max(0, activeSince.map { Date.now.timeIntervalSince($0) } ?? 0))))
            try row.writeExperience(data)
            try context.save()
            activeSince = scenePhase == .active ? .now : nil
            return true
        } catch { context.rollback(); showPersistenceError(error); return false }
    }

    /// Show the card as multiple-choice now: always in "Wählen", and in "Üben"
    /// (speakDeToRu) for brand-new cards — a gentle recognition step before we
    /// ask the user to *speak* a word they've just met.
    private func presentAsChoice(_ card: StudyCard) -> Bool {
        requestsChoice(card) && choiceOptions.count >= 2
    }

    private func requestsChoice(_ card: StudyCard) -> Bool {
        mode == .chooseDeToRu || (mode == .speakDeToRu && smartPresentation(for: card) == .choice)
    }

    private func presentAsTiles(_ card: StudyCard) -> Bool {
        mode == .speakDeToRu && smartPresentation(for: card) == .tiles
    }

    private func smartPresentation(for card: StudyCard) -> AdaptivePresentation {
        if ProductionFollowUp.pending(reviews.filter { $0.card === card }) { return .speech }
        if speechMuted { return .speech } // Shared input renders unaided typing in quiet mode.
        let ratings = reviews
            .filter { $0.card === card }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(3)
            .map(\.rating)
        return AdaptiveExercisePolicy.presentation(
            state: card.state == .new && reviews.contains(where: { $0.card === card }) ? .learning : card.state,
            targetWordCount: card.phrase?.targetText.split(whereSeparator: { $0.isWhitespace }).count ?? 0,
            speechAvailable: !speechMuted,
            recentRatings: ratings
        )
    }

    private func makeTileOptions(for card: StudyCard) -> [WordTile] {
        TileConstruction.tokens(for: card.phrase?.targetText ?? "").shuffled()
    }

    /// The configured daily new-card limit — unless the user has tapped
    /// "keep going" this session, in which case it's lifted.
    private var effectiveDailyLimit: Int {
        newCardsUnlocked ? .max : (settings.first?.dailyNewLimit ?? 10)
    }

    private var savedQuietPreference: Bool {
        (try? settings.first?.readExperience().preference(for: activeLanguage?.code ?? "ru").quiet) ?? false
    }

    /// New cards still available to introduce in the current mode (active
    /// topics or priority/homework), regardless of the daily cap.
    private var availableNewCount: Int {
        cardsForActiveLanguage.filter(scope.includes).filter { card in
            guard !card.hasBeenIntroduced, let phrase = card.phrase else { return false }
            return (phrase.topics?.contains(where: \.isActive) ?? false)
                || tutorPriorityPhraseIDs.contains(phrase.contentID)
        }.count
    }

    private func refreshTutorPriority() {
        tutorPriorityPhraseIDs = TutorPriority.phraseIDs(topics: topics, cards: cards)
    }

    /// New cards already introduced today in the current mode.
    private var newCardsDoneToday: Int {
        let cal = Calendar.current
        return reviews.filter {
            $0.wasNew && cal.isDateInToday($0.timestamp)
        }.count
    }

    /// The empty screen is the daily-limit screen (not "truly out") when new
    /// cards remain but the cap has been hit and not yet lifted.
    private var stoppedByDailyLimit: Bool {
        !newCardsUnlocked
            && availableNewCount > 0
            && newCardsDoneToday >= (settings.first?.dailyNewLimit ?? 10)
    }

    private func showSavedBanner(for answer: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            savedAlternativeBanner = answer
        }
        savedBannerTask?.cancel()
        savedBannerTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
            } catch {
                return
            }
            withAnimation(.easeInOut(duration: 0.25)) {
                savedAlternativeBanner = nil
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: DS.space.sm) {
            Text(label)
                .frame(width: 160, alignment: .leading)
                .foregroundStyle(DS.textTertiary)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}
