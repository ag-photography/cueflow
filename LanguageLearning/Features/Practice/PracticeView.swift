import SwiftUI
import SwiftData
import UIKit

/// Practice screen — the core loop. Custom header at the top with a pill-style
/// mode picker (no more bottom page dots overlaying the rating row). Hero
/// prompt card, distinct reveal layout, modern semantic rating buttons.
struct PracticeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var cards: [StudyCard]
    @Query private var reviews: [Review]
    @Query private var settings: [AppSettings]
    @Query private var languages: [Language]

    @State private var mode: CardDirection = .speakDeToRu   // "Üben" (speak-focused)
    @State private var phase: Phase = .loading
    @State private var input: String = ""
    @State private var promptStart: Date?
    @State private var showingLibrary = false
    @State private var showingProfile = false
    @State private var showingSprint = false
    @State private var sessionCount: Int = 0
    @State private var sessionCorrect: Int = 0
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
    @State private var choiceChosen: String? = nil
    // "Sag es im Satz" screen (after scoring, young cards only): flips true once
    // the user has recorded the sentence at least once, which reveals "Weiter".
    @State private var sentenceSpoken = false
    @StateObject private var speech = SpeechRecognitionService()
    @FocusState private var inputFocused: Bool
    // Lets the fixed-size serif prompt grow with Dynamic Type (capped so very
    // large accessibility sizes don't push the input off-screen).
    @ScaledMetric(relativeTo: .largeTitle) private var heroTypeScale: CGFloat = 1

    private let sessionTarget = 10
    private let transliterationGracePeriod = 200
    private let speakHesitantStartDelaySec: Double = 4.0
    private let speakHesitantPauseSec: Double = 1.5

    private let grader = GraderService()
    private let scheduler = SchedulerService()
    private let tts = TTSService.shared

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

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            sessionProgressBar
            headerBar
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, DS.space.md)
        }
        .background(
            // Subtle top-to-bottom warmth so the prompt card floats on depth
            // rather than flat cream. Header sits on the surface0 top stop, so
            // there's no seam.
            LinearGradient(
                colors: [DS.surface0, DS.surface2.opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .sheet(isPresented: $showingLibrary, onDismiss: { advance() }) {
            LibraryView()
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView()
        }
        .fullScreenCover(isPresented: $showingSprint) {
            SprintView()
        }
        .sheet(isPresented: $showingSessionSummary) {
            sessionSummarySheet
        }
        .onChange(of: mode) { _, _ in
            // Switching modes resets the current card — keep state coherent.
            // Each mode decides the daily-limit override independently.
            newCardsUnlocked = false
            speechMuted = false
            resetSession()
            phase = .loading
            input = ""
            speech.clearTranscription()
        }
        .onChange(of: settings.first?.activeLanguageCode) { _, _ in
            // Active language switch: reset session, update speech locale,
            // reload the first card for the new language.
            newCardsUnlocked = false
            speechMuted = false
            resetSession()
            phase = .loading
            input = ""
            speech.clearTranscription()
            if let locale = activeLanguage?.speechLocale {
                speech.setLocale(locale)
            }
        }
        .onAppear {
            if let locale = activeLanguage?.speechLocale {
                speech.setLocale(locale)
            }
        }
    }

    // MARK: - Header

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
                    .animation(.easeOut(duration: 0.3), value: sessionCount)
            }
        }
        .frame(height: 4)
    }

    private var progressFraction: CGFloat {
        guard sessionTarget > 0 else { return 0 }
        return CGFloat(min(sessionCount, sessionTarget)) / CGFloat(sessionTarget)
    }

    private var headerBar: some View {
        VStack(spacing: DS.space.sm) {
            HStack(spacing: DS.space.sm) {
                Spacer()
                if currentStreak > 0 {
                    streakChip
                }
                sprintHeaderButton
                headerIconButton(systemName: "chart.bar.fill", label: "Fortschritt") { showingProfile = true }
                headerIconButton(systemName: "books.vertical", label: "Bibliothek") { showingLibrary = true }
            }
            // Own full-width row so all four exercise modes fit comfortably.
            modePicker
        }
        .padding(.horizontal, DS.space.md)
        .padding(.vertical, DS.space.sm)
        .background(DS.surface0)
    }

    /// Streak chip — internal trigger (Hook Model): "don't break the chain".
    /// Small, restrained — no panicking-owl energy.
    private var streakChip: some View {
        Button {
            showingProfile = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.caption)
                Text("\(currentStreak)")
                    .font(.caption.weight(.bold).monospacedDigit())
            }
            .foregroundStyle(DS.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(DS.accentSoft)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Serie: \(currentStreak) Tage")
        .accessibilityHint("Öffnet den Fortschritt")
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
        try? context.save()
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
        case 7: return "Eine Woche. Das ist schon Habit."
        case 14: return "Zwei Wochen — solide."
        case 30: return "Ein Monat. Beeindruckend."
        case 100: return "Hundert Tage. Außergewöhnlich."
        case 365: return "Ein ganzes Jahr. Wow."
        default: return ""
        }
    }

    /// Days in a row with at least one review, counting back from today.
    /// Today only counts if there's been a review today (strict — no grace).
    private var currentStreak: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: .now)
        var streak = 0
        while true {
            let next = cal.date(byAdding: .day, value: 1, to: day) ?? day
            if !reviews.contains(where: { $0.timestamp >= day && $0.timestamp < next }) {
                break
            }
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return streak
    }

    /// Sprint entry — accent-tinted so it reads as a distinct "fun" action, not
    /// just another grey nav icon. (Placement provisional: a session-summary
    /// "want a fast round?" entry may suit it better than the busy header.)
    private var sprintHeaderButton: some View {
        Button { showingSprint = true } label: {
            Image(systemName: "bolt.fill")
                .font(.callout)
                .foregroundStyle(DS.accent)
                .frame(width: 36, height: 36)
                .background(DS.accentSoft)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sprint")
        .accessibilityHint("60-Sekunden-Sprechrunde")
    }

    private func headerIconButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.callout)
                .foregroundStyle(DS.textPrimary)
                .frame(width: 36, height: 36)
                .background(DS.surface1)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(CardDirection.allCases, id: \.self) { direction in
                modePickerButton(direction: direction)
            }
        }
        .padding(4)
        .background(DS.surface1)
        .clipShape(Capsule())
        // Compact 3-way control (tab-bar-like): cap growth so the segments
        // keep fitting at accessibility sizes. The reading content scales fully.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private func modePickerButton(direction: CardDirection) -> some View {
        let selected = mode == direction
        let fg: Color = selected ? .white : DS.textSecondary
        let bg: Color = selected ? DS.accent : .clear
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { mode = direction }
        } label: {
            Text(direction.displayName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(fg)
                .background(bg)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(direction.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Phase content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            loadingView.task { advance() }
        case .prompt(let card):
            if mode == .flipDeToRu {
                flipCardScreen(card: card)
            } else if presentAsChoice(card) {
                // "Wählen" mode, or "Üben" easing a new card in via recognition.
                chooseCardScreen(card: card)
            } else {
                promptContent(card: card, revealed: false)
            }
        case .study(let card):
            promptContent(card: card, revealed: true)
        case .reveal(let card, let result, let answer, let elapsedMs):
            revealContent(card: card, result: result, userAnswer: answer, responseTimeMs: elapsedMs)
        case .speakSentence(let card):
            speakSentenceScreen(card: card)
        case .empty:
            emptyContent
        }
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
        do {
            let wasNew = card.state == .new
            try scheduler.record(rating: rating, on: card)

            let review = Review(
                card: card,
                rating: rating,
                autoGradeRating: rating,  // no auto-grader involved in flip mode
                userAnswer: "",
                mode: card.direction,
                responseTimeMs: Int((promptStart.map { Date.now.timeIntervalSince($0) } ?? 0) * 1000),
                gradeTier: 0,  // tier 0 = recognition flip, no character grading
                wasNew: wasNew
            )
            context.insert(review)
            try context.save()
        } catch {
            print("Failed to record flip review: \(error)")
        }

        promptStart = nil
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
        VStack(spacing: DS.space.lg) {
            if let praise = surprisePraiseBanner { surpriseBanner(praise) }
            if mode == .speakDeToRu && speechMuted { resumeSpeakingBanner }
            topicChips(card: card)
            heroPrompt(card: card)
            Spacer(minLength: 0)
            VStack(spacing: DS.space.sm) {
                ForEach(choiceOptions, id: \.self) { option in
                    choiceButton(card: card, option: option)
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
                Text("Sprechen pausiert").font(.caption.weight(.medium))
                Spacer()
                Text("Wieder sprechen").font(.caption.weight(.semibold))
                Image(systemName: "chevron.right").font(.caption2)
            }
            .foregroundStyle(DS.accent)
            .padding(.horizontal, DS.space.md)
            .padding(.vertical, 10)
            .background(DS.accentSoft)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sprechen pausiert. Tippen, um wieder zu sprechen.")
    }

    private func choiceButton(card: StudyCard, option: String) -> some View {
        let isCorrect = card.phrase?.targetText == option
        let answered = choiceChosen != nil
        let isChosen = choiceChosen == option

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
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .foregroundStyle(fg)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        guard choiceChosen == nil else { return }
        let elapsedMs = Int((promptStart.map { Date.now.timeIntervalSince($0) } ?? 0) * 1000)
        let correct = card.phrase?.targetText == option
        withAnimation(.easeOut(duration: 0.2)) { choiceChosen = option }
        if correct {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        tts.speak(card.phrase?.targetText ?? "",
                  language: card.phrase?.language?.ttsLocale ?? "ru-RU", times: 1)

        // Brief feedback dwell — longer when wrong so the correct answer registers.
        let dwell: UInt64 = correct ? 850_000_000 : 1_700_000_000
        Task {
            try? await Task.sleep(nanoseconds: dwell)
            await MainActor.run {
                recordChoiceReview(card: card, correct: correct, responseTimeMs: elapsedMs)
            }
        }
    }

    private func recordChoiceReview(card: StudyCard, correct: Bool, responseTimeMs: Int) {
        let rating = correct ? (responseTimeMs <= 4000 ? 4 : 3) : 1
        do {
            let wasNew = card.state == .new
            try scheduler.record(rating: rating, on: card)
            let review = Review(
                card: card,
                rating: rating,
                autoGradeRating: rating,
                userAnswer: choiceChosen ?? "",
                mode: card.direction,
                responseTimeMs: responseTimeMs,
                gradeTier: 0,   // recognition, no character grading
                wasNew: wasNew
            )
            context.insert(review)
            try context.save()
        } catch {
            print("Failed to record choice review: \(error)")
        }

        choiceChosen = nil
        promptStart = nil
        sessionCount += 1
        if correct {
            sessionCorrect += 1
            maybeTriggerSurprisePraise()
        }

        if sessionCount >= sessionTarget {
            showingSessionSummary = true
        } else {
            phase = .loading
        }
    }

    /// Builds 4 options for a choose card: the correct answer plus three
    /// distractors sampled from the active-language pool. Samples (rather than
    /// scanning every card and faulting its topics) so it stays fast even with
    /// thousands of cards.
    private func makeChoiceOptions(for card: StudyCard, pool: [StudyCard]) -> [String] {
        guard let phrase = card.phrase else { return [] }
        let correct = phrase.targetText
        let phraseID = phrase.persistentModelID
        var candidates: [String] = []
        var seen: Set<String> = [correct]
        var attempts = 0
        while candidates.count < 10 && attempts < 50 {
            attempts += 1
            guard let c = pool.randomElement(),
                  let p = c.phrase, p.persistentModelID != phraseID else { continue }
            let target = p.targetText
            if !target.isEmpty, !seen.contains(target) {
                seen.insert(target)
                candidates.append(target)
            }
        }
        return MultipleChoice.options(correct: correct, from: candidates, distractors: 3)
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
            if !revealed && mode != .typeDeToRu {
                Button {
                    showStudyMode()
                } label: {
                    Text("Ich weiß es nicht")
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
            if mode == .typeDeToRu { inputFocused = true }
        }
    }

    private func topicChips(card: StudyCard) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(card.phrase?.topics ?? []) { topic in
                    Text(topic.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DS.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(DS.surface1)
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heroPrompt(card: StudyCard) -> some View {
        // Serif typography (Apple "New York" via design: .serif) for a
        // premium reading-app feel — borrowed from Babbel's headline style.
        // Same size scaling as FlipCardView's faces, and the same surface /
        // radius / shadow, so the prompt reads identically across all three
        // modes — one unified "card" metaphor (build 24).
        let text = card.phrase?.sourceText ?? "—"
        let base: CGFloat = text.count > 40 ? 22 : (text.count > 30 ? 28 : (text.count > 15 ? 34 : 42))
        let size = base * min(heroTypeScale, 1.5)
        return Text(text)
            .font(.system(size: size, weight: .bold, design: .serif))
            .multilineTextAlignment(.center)
            .foregroundStyle(DS.textPrimary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DS.space.lg)
            .padding(.vertical, DS.space.xxl)
            .dsFlashcardSurface()
    }

    private func answerCard(card: StudyCard) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("Antwort")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.gradePerfect)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Button {
                    tts.speak(card.phrase?.targetText ?? "", language: card.phrase?.language?.ttsLocale ?? "ru-RU", times: 2)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.callout)
                        .foregroundStyle(DS.gradePerfect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Antwort vorlesen")
            }
            Text(card.phrase?.targetText ?? "")
                .font(.system(.title2, design: .rounded, weight: .medium))
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
        .background(DS.gradePerfect.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
        .onAppear { tts.speak(card.phrase?.targetText ?? "", language: card.phrase?.language?.ttsLocale ?? "ru-RU", times: 2) }
    }

    @ViewBuilder
    private func inputArea(revealed: Bool) -> some View {
        switch mode {
        case .typeDeToRu:
            typingInputSection(revealed: revealed)
        case .speakDeToRu:
            speakInputSection(revealed: revealed)
        case .flipDeToRu, .chooseDeToRu:
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
                // No forced RTL: the Arabic starter pack stores Latin
                // transliteration as the practice target, so .leading is
                // correct for both Russian Cyrillic and Latin-translit Arabic.
                // SwiftUI's bidi handles the rare case where the user types
                // genuine Arabic script.
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
                                Text("Ich weiß es nicht")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(DS.accent)
                            }
                        }
                    }
                }

            primaryButton(
                title: "Prüfen",
                disabled: input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
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
                .font(.headline.weight(.bold))
                .foregroundStyle(disabled ? DS.disabledText : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    Capsule()
                        .fill(disabled ? DS.disabled : DS.accent)
                )
                .shadow(
                    color: disabled ? .clear : DS.accent.opacity(0.30),
                    radius: 8,
                    x: 0,
                    y: 4
                )
        }
        .buttonStyle(.plain)
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
        speechErrorMessage = nil
        input = ""
        Task {
            if speechAuthorized == nil {
                speechAuthorized = await speech.requestAuthorization()
            }
            guard speechAuthorized == true else {
                speechErrorMessage = "Mikrofon- und Spracherkennungs-Berechtigung erforderlich."
                return
            }
            do {
                try speech.start()
            } catch {
                speechErrorMessage = error.localizedDescription
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
                if shouldShowTransliteration, let translit = card.phrase?.transliteration {
                    Text(translit)
                        .font(.footnote)
                        .foregroundStyle(DS.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                detailsDisclosure(card: card, result: result)
                revealActions(card: card, result: result, userAnswer: userAnswer, responseTimeMs: responseTimeMs)
            }
            .padding(.vertical, DS.space.md)
        }
        .onAppear { tts.speak(card.phrase?.targetText ?? "", language: card.phrase?.language?.ttsLocale ?? "ru-RU", times: 2) }
    }

    /// Big grade-themed hero panel — animates in with a spring on appear so
    /// the result lands with more punch than the old small chip. Tinted by
    /// grade colour, large icon + label, speaker control on the right.
    private func revealHero(card: StudyCard, result: GradeResult) -> some View {
        let color = gradeColor(for: result.autoGrade)
        return HStack(spacing: DS.space.md) {
            Image(systemName: gradeIcon(for: result.autoGrade))
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 56, height: 56)
                .background(color.opacity(0.18))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(result.autoGrade.label)
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundStyle(DS.textPrimary)
                Text(revealSubtitle(for: result.autoGrade))
                    .font(.caption)
                    .foregroundStyle(DS.textSecondary)
            }
            Spacer()
            Button {
                tts.speak(card.phrase?.targetText ?? "", language: card.phrase?.language?.ttsLocale ?? "ru-RU", times: 2)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.title3)
                    .foregroundStyle(DS.accent)
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
        .id(result.autoGrade)   // re-runs the appear-animation on grade change
        .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
        .animation(
            reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.7),
            value: result.autoGrade
        )
    }

    /// Big-typography answer card so the correct Russian is the focal point
    /// after the grade. The character-level diff now lives in the collapsed
    /// Details disclosure below (build 24 — slimmer reveal).
    private func revealAnswerCard(card: StudyCard, result: GradeResult) -> some View {
        Text(card.phrase?.targetText ?? "")
            .font(.system(.title2, design: .serif, weight: .semibold))
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
    /// "now say it out loud" reinforcement: the target sentence big, an optional
    /// pronunciation line and the German translation, plus a speaker button to
    /// hear it modelled. Tinted with the accent so it reads as an action ("do
    /// this"), not just more reference text. More spoken output, concentrated on
    /// the words that aren't solid yet.
    @ViewBuilder
    private func exampleSentenceCard(card: StudyCard) -> some View {
        let phrase = card.phrase
        let sentence = phrase?.exampleSentence ?? ""
        let locale = phrase?.language?.ttsLocale ?? "ru-RU"
        VStack(alignment: .leading, spacing: DS.space.sm) {
            HStack(spacing: 6) {
                Image(systemName: "text.quote")
                    .font(.caption.weight(.bold))
                Text("Sag es im Satz")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                Spacer()
                Button {
                    tts.speak(sentence, language: locale, times: 1)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.subheadline)
                        .foregroundStyle(DS.accent)
                        .frame(width: 38, height: 38)
                        .background(DS.surface0)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Satz vorlesen")
            }
            .foregroundStyle(DS.accent)

            Text(sentence)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if shouldShowTransliteration,
               let translit = phrase?.exampleSentenceTransliteration, !translit.isEmpty {
                Text(translit)
                    .font(.footnote)
                    .foregroundStyle(DS.textTertiary)
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
        let locale = phrase?.language?.ttsLocale ?? "ru-RU"
        return VStack(spacing: DS.space.lg) {
            VStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .frame(width: 64, height: 64)
                    .background(DS.accentSoft)
                    .clipShape(Circle())
                Text("Jetzt du – sprich den Satz")
                    .font(.system(.title3, design: .serif, weight: .bold))
                    .foregroundStyle(DS.textPrimary)
                Text("Laut nachsprechen. Wird nicht bewertet – einfach sagen.")
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
            speech.clearTranscription()
            speechErrorMessage = nil
            tts.speak(sentence, language: locale, times: 1)
        }
    }

    private func revealSubtitle(for grade: AutoGrade) -> String {
        switch grade {
        case .perfect:  return "Sauber gewusst."
        case .hesitant: return "Richtig – nächstes Mal flüssiger."
        case .minor:    return "Ganz nah dran!"
        case .wrong:    return "Kein Stress – du siehst sie bald wieder."
        case .studied:  return "Angeschaut – das zählt auch."
        }
    }

    private func detailsDisclosure(card: StudyCard, result: GradeResult) -> some View {
        DisclosureGroup(isExpanded: $showingGradeDetails) {
            VStack(alignment: .leading, spacing: DS.space.sm) {
                DiffView(expected: card.phrase?.targetText ?? "", actual: result.normalizedActual)
                VStack(alignment: .leading, spacing: 6) {
                    detailRow("Erwartet", result.normalizedExpected)
                    detailRow("Eingabe", result.normalizedActual)
                    detailRow("Tier", "\(result.tier)")
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
            primaryButton(title: "Weiter", disabled: false) {
                confirm(rating: suggested, card: card, result: result,
                        userAnswer: userAnswer, responseTimeMs: responseTimeMs)
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
        }
        .padding(.top, DS.space.sm)
    }

    private func gradeChip(for grade: AutoGrade) -> some View {
        let color = gradeColor(for: grade)
        return HStack(spacing: 6) {
            Image(systemName: gradeIcon(for: grade))
                .font(.callout)
            Text(grade.label)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, DS.space.md)
        .padding(.vertical, 8)
        .foregroundStyle(.white)
        .background(color)
        .clipShape(Capsule())
    }

    private func gradeColor(for grade: AutoGrade) -> Color {
        switch grade {
        case .perfect: return DS.gradePerfect
        case .hesitant: return DS.gradeHesitant
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
                .foregroundStyle(DS.accent)
            Text("Tagesziel erreicht")
                .font(.title2.weight(.semibold))
            Text("Du hast heute \(newCardsDoneToday) neue Karten gelernt. Es warten noch \(availableNewCount) in deinen aktiven Themen.")
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
            Text("Das Tageslimit kannst du in den Einstellungen ändern (Üben → Neue Karten pro Tag).")
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
                .foregroundStyle(DS.accent)
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
        VStack(spacing: DS.space.lg) {
            if let milestone = unseenStreakMilestone {
                milestoneBanner(days: milestone)
                    .onAppear { markStreakCelebrated(milestone) }
            }
            Spacer()
            Text("\(sessionCorrect)/\(sessionCount)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(DS.accent)
            Text(sessionAccuracyMessage)
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal)
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
            Button("Pause") {
                resetSession()
                showingSessionSummary = false
                phase = .empty
            }
            .foregroundStyle(DS.textSecondary)
            .padding(.bottom)
        }
        .padding()
        .presentationDetents([.medium])
    }

    private var sessionAccuracyMessage: String {
        // Variable reward (Hook Model): rotating messages within each accuracy
        // band so the same outcome doesn't always read identical. Pick by
        // session count modulo the bucket size — deterministic per session
        // but cycles through.
        let pct = sessionCount == 0 ? 0 : Int((Double(sessionCorrect) / Double(sessionCount)) * 100)
        let candidates: [String]
        switch pct {
        case 90...:
            candidates = [
                "Großartig!",
                "Auf Flammen heute.",
                "Sauber durch.",
                "Das saß."
            ]
        case 70...:
            candidates = [
                "Solide Runde.",
                "Gute Arbeit.",
                "Stetiger Fortschritt.",
                "Macht sich bezahlt."
            ]
        case 50...:
            candidates = [
                "Weiter dran bleiben.",
                "Knapp die Hälfte — passt schon.",
                "Schwierige Wörter brauchen Zeit.",
                "Morgen probierst du wieder."
            ]
        default:
            candidates = [
                "Schwierige Runde — Wiederholung hilft.",
                "Die kommen bald wieder, dann besser.",
                "Knapp, aber dranbleiben.",
                "SRS sorgt dafür, dass du sie nicht vergisst."
            ]
        }
        return candidates[abs(sessionCount.hashValue) % candidates.count]
    }

    // MARK: - Logic (unchanged)

    private func submit(revealed: Bool) {
        let card: StudyCard
        switch phase {
        case .prompt(let c), .study(let c): card = c
        default: return
        }
        let elapsedMs = Int((promptStart.map { Date.now.timeIntervalSince($0) } ?? 0) * 1000)
        let expected = card.phrase?.targetText ?? ""
        let alternatives = card.phrase?.acceptedAlternatives ?? []
        let userAnswer = (mode == .speakDeToRu) ? speech.transcription : input
        let useJudge = settings.first?.useAIGradingAssist == true
        inputFocused = false

        Task {
            let baseline = await grader.gradeWithJudge(
                german: card.phrase?.sourceText ?? "",
                expected: expected,
                actual: userAnswer,
                acceptedAlternatives: alternatives,
                responseTimeMs: elapsedMs,
                useJudge: useJudge
            )
            await MainActor.run {
                finalize(
                    card: card,
                    baseline: baseline,
                    revealed: revealed,
                    userAnswer: userAnswer,
                    elapsedMs: elapsedMs
                )
            }
        }
    }

    private func finalize(
        card: StudyCard,
        baseline: GradeResult,
        revealed: Bool,
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
        } else if mode == .speakDeToRu, result.autoGrade == .perfect {
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
        phase = .reveal(card, result, userAnswer: userAnswer, responseTimeMs: elapsedMs)
    }

    private func showStudyMode() {
        guard case .prompt(let card) = phase else { return }
        phase = .study(card)
    }

    private func confirm(
        rating: Int,
        card: StudyCard,
        result: GradeResult,
        userAnswer: String,
        responseTimeMs: Int
    ) {
        do {
            let wasNew = card.state == .new
            try scheduler.record(rating: rating, on: card)

            if rating >= 3, result.autoGrade.suggestedRating < 3, let phrase = card.phrase {
                let normalized = FuzzyMatcher.normalize(userAnswer)
                if !normalized.isEmpty,
                   normalized != phrase.targetTextNormalized,
                   !phrase.acceptedAlternatives.contains(where: { FuzzyMatcher.normalize($0) == normalized }) {
                    phrase.acceptedAlternatives.append(userAnswer)
                    showSavedBanner(for: userAnswer)
                }
            }

            let review = Review(
                card: card,
                rating: rating,
                autoGradeRating: result.autoGrade.suggestedRating,
                userAnswer: userAnswer,
                mode: card.direction,
                responseTimeMs: responseTimeMs,
                gradeTier: result.tier,
                wasNew: wasNew
            )
            context.insert(review)
            try context.save()
        } catch {
            print("Failed to record review: \(error)")
        }

        input = ""
        speech.clearTranscription()
        promptStart = nil
        sessionCount += 1
        if rating >= 3 {
            sessionCorrect += 1
            // Variable-ratio reinforcement: ~12% chance per correct answer
            // to trigger a surprise praise. The banner shows on the next
            // prompt screen for ~2.5s, then fades.
            maybeTriggerSurprisePraise()
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

    /// Slot-machine-style variable reward: rare bonus praise on top of the
    /// normal grade. Only fires on confirmed correct ratings, so it always
    /// celebrates real progress. Configurable; can be disabled in Settings.
    private func maybeTriggerSurprisePraise() {
        guard settings.first?.surpriseRewardsEnabled ?? true else { return }
        guard Double.random(in: 0..<1) < 0.12 else { return }
        let praise = Self.surprisePraises.randomElement() ?? "🎯"
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.7)) {
            surprisePraiseBanner = praise
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    surprisePraiseBanner = nil
                }
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

    private static let surprisePraises: [String] = [
        "🎯  Sauber!",
        "💫  Auf Flammen.",
        "🔥  Drei am Stück.",
        "⭐  Das hat gesessen.",
        "✨  Im Fluss.",
        "🚀  Du fliegst.",
        "💡  Klick.",
        "🏆  Stark.",
        "🌟  Volltreffer.",
        "💪  Solide."
    ]

    private func resetSession() {
        sessionCount = 0
        sessionCorrect = 0
    }

    private func advance() {
        // Cancel any in-flight TTS so a half-finished reveal doesn't keep
        // speaking after the next prompt has already appeared.
        tts.stop()
        showingGradeDetails = false
        choiceChosen = nil
        let pool = cardsForActiveLanguage   // compute the language scan once
        if let next = scheduler.nextCard(from: pool, direction: mode, reviews: reviews, dailyNewLimit: effectiveDailyLimit) {
            if presentAsChoice(next) {
                choiceOptions = makeChoiceOptions(for: next, pool: pool)
            }
            phase = .prompt(next)
        } else {
            phase = .empty
        }
    }

    /// Show the card as multiple-choice now: always in "Wählen", and in "Üben"
    /// (speakDeToRu) for brand-new cards — a gentle recognition step before we
    /// ask the user to *speak* a word they've just met.
    private func presentAsChoice(_ card: StudyCard) -> Bool {
        mode == .chooseDeToRu
            || (mode == .speakDeToRu && (card.state == .new || speechMuted))
    }

    /// The configured daily new-card limit — unless the user has tapped
    /// "keep going" this session, in which case it's lifted.
    private var effectiveDailyLimit: Int {
        newCardsUnlocked ? .max : (settings.first?.dailyNewLimit ?? 10)
    }

    /// New cards still available to introduce in the current mode (active
    /// topics or priority/homework), regardless of the daily cap.
    private var availableNewCount: Int {
        cardsForActiveLanguage.filter {
            $0.direction == mode && $0.state == .new
            && (($0.phrase?.topics.contains(where: { $0.isActive }) ?? false)
                || ($0.phrase?.isPriorityActive ?? false))
        }.count
    }

    /// New cards already introduced today in the current mode.
    private var newCardsDoneToday: Int {
        let cal = Calendar.current
        return reviews.filter {
            $0.wasNew && cal.isDateInToday($0.timestamp) && $0.card?.direction == mode
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
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    savedAlternativeBanner = nil
                }
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
