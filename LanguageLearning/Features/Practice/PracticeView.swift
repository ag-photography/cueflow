import SwiftUI
import SwiftData
import UIKit

/// Practice screen — the core loop. Custom header at the top with a pill-style
/// mode picker (no more bottom page dots overlaying the rating row). Hero
/// prompt card, distinct reveal layout, modern semantic rating buttons.
struct PracticeView: View {
    @Environment(\.modelContext) private var context
    @Query private var cards: [StudyCard]
    @Query private var reviews: [Review]
    @Query private var settings: [AppSettings]
    @Query private var languages: [Language]

    @State private var mode: CardDirection = .typeDeToRu
    @State private var phase: Phase = .loading
    @State private var input: String = ""
    @State private var promptStart: Date?
    @State private var showingLibrary = false
    @State private var showingProfile = false
    @State private var sessionCount: Int = 0
    @State private var sessionCorrect: Int = 0
    @State private var showingSessionSummary = false
    @State private var speechAuthorized: Bool? = nil
    @State private var speechErrorMessage: String?
    @State private var showingGradeDetails: Bool = false
    @State private var savedAlternativeBanner: String?
    @StateObject private var speech = SpeechRecognitionService()
    @FocusState private var inputFocused: Bool

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
        .background(DS.surface0)
        .sheet(isPresented: $showingLibrary, onDismiss: { advance() }) {
            LibraryView()
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView()
        }
        .sheet(isPresented: $showingSessionSummary) {
            sessionSummarySheet
        }
        .onChange(of: mode) { _, _ in
            // Switching modes resets the current card — keep state coherent.
            resetSession()
            phase = .loading
            input = ""
            speech.clearTranscription()
        }
        .onChange(of: settings.first?.activeLanguageCode) { _, _ in
            // Active language switch: reset session, update speech locale,
            // reload the first card for the new language.
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
        HStack(spacing: DS.space.sm) {
            modePicker
            Spacer()
            headerIconButton(systemName: "chart.bar.fill") { showingProfile = true }
            headerIconButton(systemName: "books.vertical") { showingLibrary = true }
        }
        .padding(.horizontal, DS.space.md)
        .padding(.vertical, DS.space.sm)
        .background(DS.surface0)
    }

    private func headerIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.callout)
                .foregroundStyle(DS.textPrimary)
                .frame(width: 36, height: 36)
                .background(DS.surface1)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
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
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(fg)
                .background(bg)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
            } else {
                promptContent(card: card, revealed: false)
            }
        case .study(let card):
            promptContent(card: card, revealed: true)
        case .reveal(let card, let result, let answer, let elapsedMs):
            revealContent(card: card, result: result, userAnswer: answer, responseTimeMs: elapsedMs)
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

            topicChips(card: card)

            heroPrompt(card: card)

            if revealed {
                answerCard(card: card)
            }

            Spacer(minLength: 0)

            inputArea(revealed: revealed)

            if !revealed {
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
        // Scales down for longer phrases so wrapping stays graceful.
        let text = card.phrase?.sourceText ?? "—"
        let size: CGFloat = text.count > 30 ? 30 : (text.count > 15 ? 38 : 46)
        return Text(text)
            .font(.system(size: size, weight: .bold, design: .serif))
            .multilineTextAlignment(.center)
            .foregroundStyle(DS.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DS.space.md)
            .padding(.vertical, DS.space.lg)
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
            }
            Text(card.phrase?.targetText ?? "")
                .font(.system(.title2, design: .rounded, weight: .medium))
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.center)
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
        case .flipDeToRu:
            // Flip mode renders FlipCardView at the screen level, no
            // separate input area is needed.
            EmptyView()
        }
    }

    @ViewBuilder
    private func typingInputSection(revealed: Bool) -> some View {
        // Single column, no keyboard accessory bar. Return on the keyboard
        // submits (`.submitLabel(.go)` shows "Los"). The full-width Prüfen
        // button is the visible fallback when the keyboard is dismissed.
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
                HStack {
                    gradeChip(for: result.autoGrade)
                    Spacer()
                    Button {
                        tts.speak(card.phrase?.targetText ?? "", language: card.phrase?.language?.ttsLocale ?? "ru-RU", times: 2)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title3)
                            .foregroundStyle(DS.accent)
                            .frame(width: 40, height: 40)
                            .background(DS.accentSoft)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, DS.space.sm)

                DiffView(expected: card.phrase?.targetText ?? "", actual: userAnswer)
                    .padding(DS.space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.surface1)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))

                if shouldShowTransliteration, let translit = card.phrase?.transliteration {
                    Text(translit)
                        .font(.footnote)
                        .foregroundStyle(DS.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                detailsDisclosure(result: result)

                Text("Wie gut wusstest du es?")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, DS.space.sm)

                ratingButtons(card: card, result: result, userAnswer: userAnswer, responseTimeMs: responseTimeMs)
            }
            .padding(.vertical, DS.space.md)
        }
        .onAppear { tts.speak(card.phrase?.targetText ?? "", language: card.phrase?.language?.ttsLocale ?? "ru-RU", times: 2) }
    }

    private func detailsDisclosure(result: GradeResult) -> some View {
        DisclosureGroup(isExpanded: $showingGradeDetails) {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DS.space.sm)
        } label: {
            Text("Details")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
        }
        .padding(.horizontal, DS.space.md)
        .padding(.vertical, DS.space.sm)
        .background(DS.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
    }

    // MARK: - Rating buttons

    private struct RatingSpec {
        let rating: Int
        let label: String
        let symbol: String
        let color: Color
    }

    private var ratingSpecs: [RatingSpec] {
        [
            .init(rating: 1, label: "Nochmal", symbol: "arrow.counterclockwise", color: DS.gradeWrong),
            .init(rating: 2, label: "Schwer", symbol: "tortoise.fill", color: DS.gradeMinor),
            .init(rating: 3, label: "Gut", symbol: "checkmark", color: DS.gradePerfect),
            .init(rating: 4, label: "Leicht", symbol: "sparkles", color: DS.accent),
        ]
    }

    private func ratingButtons(
        card: StudyCard,
        result: GradeResult,
        userAnswer: String,
        responseTimeMs: Int
    ) -> some View {
        HStack(spacing: 8) {
            ForEach(ratingSpecs, id: \.rating) { spec in
                ratingButton(
                    spec: spec,
                    suggested: result.autoGrade.suggestedRating,
                    onTap: {
                        confirm(
                            rating: spec.rating,
                            card: card,
                            result: result,
                            userAnswer: userAnswer,
                            responseTimeMs: responseTimeMs
                        )
                    }
                )
            }
        }
    }

    private func ratingButton(
        spec: RatingSpec,
        suggested: Int,
        onTap: @escaping () -> Void
    ) -> some View {
        let isSuggested = spec.rating == suggested
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: spec.symbol)
                    .font(.title3)
                Text(spec.label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isSuggested ? .white : spec.color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSuggested ? spec.color : spec.color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
            .shadow(
                color: isSuggested ? spec.color.opacity(0.25) : .clear,
                radius: 4,
                x: 0,
                y: 2
            )
        }
        .buttonStyle(.plain)
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
        case .hesitant: return "hourglass"
        case .minor: return "exclamationmark.circle.fill"
        case .wrong: return "xmark.circle.fill"
        case .studied: return "book.fill"
        }
    }

    // MARK: - Empty

    private var emptyContent: some View {
        VStack(spacing: DS.space.md) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 64))
                .foregroundStyle(DS.accent)
            Text("Alles erledigt!")
                .font(.title2.weight(.semibold))
            Text("Keine fälligen Karten. Komm später wieder, oder importiere neue Vokabeln.")
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
        let pct = sessionCount == 0 ? 0 : Int((Double(sessionCorrect) / Double(sessionCount)) * 100)
        switch pct {
        case 90...: return "Großartig!"
        case 70...: return "Solide Runde."
        case 50...: return "Weiter dran bleiben."
        default: return "Schwierige Runde — Wiederholung hilft."
        }
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
        if rating >= 3 { sessionCorrect += 1 }

        if sessionCount >= sessionTarget {
            showingSessionSummary = true
        } else {
            phase = .loading
        }
    }

    private func resetSession() {
        sessionCount = 0
        sessionCorrect = 0
    }

    private func advance() {
        let limit = settings.first?.dailyNewLimit ?? 10
        showingGradeDetails = false
        if let next = scheduler.nextCard(from: cardsForActiveLanguage, direction: mode, reviews: reviews, dailyNewLimit: limit) {
            phase = .prompt(next)
        } else {
            phase = .empty
        }
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
