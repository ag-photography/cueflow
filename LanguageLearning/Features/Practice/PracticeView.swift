import SwiftUI
import SwiftData

struct PracticeView: View {
    let mode: CardDirection

    init(mode: CardDirection = .typeDeToRu) {
        self.mode = mode
    }

    @Environment(\.modelContext) private var context
    @Query private var cards: [StudyCard]
    @Query private var reviews: [Review]
    @Query private var settings: [AppSettings]

    @State private var phase: Phase = .loading
    @State private var input: String = ""
    @State private var promptStart: Date?
    @State private var showingLibrary = false
    @State private var sessionCount: Int = 0
    @State private var sessionCorrect: Int = 0
    @State private var showingSessionSummary = false
    @State private var speechAuthorized: Bool? = nil
    @State private var speechErrorMessage: String?
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

    var body: some View {
        NavigationStack {
            VStack {
                switch phase {
                case .loading:
                    ProgressView()
                        .task { advance() }
                case .prompt(let card):
                    promptContent(card: card, revealed: false)
                case .study(let card):
                    promptContent(card: card, revealed: true)
                case .reveal(let card, let result, let answer, let elapsedMs):
                    revealContent(
                        card: card,
                        result: result,
                        userAnswer: answer,
                        responseTimeMs: elapsedMs
                    )
                case .empty:
                    emptyContent
                }
            }
            .padding()
            .navigationTitle(mode.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingLibrary = true
                    } label: {
                        Image(systemName: "books.vertical")
                    }
                }
            }
            .sheet(isPresented: $showingLibrary, onDismiss: { advance() }) {
                LibraryView()
            }
            .sheet(isPresented: $showingSessionSummary) {
                sessionSummarySheet
            }
        }
    }

    private var sessionSummarySheet: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("\(sessionCorrect)/\(sessionCount)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(.tint)
            Text(sessionAccuracyMessage)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            Button {
                resetSession()
                showingSessionSummary = false
                phase = .loading
            } label: {
                Text("Weiter üben")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            Button("Pause") {
                resetSession()
                showingSessionSummary = false
                phase = .empty
            }
            .padding(.bottom)
        }
        .padding()
        .presentationDetents([.medium])
    }

    private var sessionAccuracyMessage: String {
        let pct = sessionCount == 0 ? 0 : Int((Double(sessionCorrect) / Double(sessionCount)) * 100)
        switch pct {
        case 90...: return "Großartig! 🎯"
        case 70...: return "Solide Runde."
        case 50...: return "Weiter dran bleiben."
        default: return "Schwierige Runde — keine Sorge, Wiederholung hilft."
        }
    }

    private func resetSession() {
        sessionCount = 0
        sessionCorrect = 0
    }

    private func promptContent(card: StudyCard, revealed: Bool) -> some View {
        VStack(spacing: 20) {
            HStack {
                ForEach(card.phrase?.topics ?? []) { topic in
                    Text(topic.name)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
                Spacer()
            }

            Spacer()

            Text(card.phrase?.sourceText ?? "—")
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if revealed {
                VStack(spacing: 6) {
                    HStack {
                        Text("Antwort")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            tts.speak(card.phrase?.targetText ?? "")
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.green)
                    }
                    Text(card.phrase?.targetText ?? "")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.green)
                        .multilineTextAlignment(.center)
                    if shouldShowTransliteration, let translit = card.phrase?.transliteration {
                        Text(translit)
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onAppear { tts.speak(card.phrase?.targetText ?? "") }
            }

            Spacer()

            switch mode {
            case .typeDeToRu:
                typingInputSection(revealed: revealed)
            case .speakDeToRu:
                speakInputSection(revealed: revealed)
            }

            if !revealed {
                Button {
                    showStudyMode()
                } label: {
                    Text("Ich weiß es nicht")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
        }
        .onAppear {
            if promptStart == nil { promptStart = .now }
            if mode == .typeDeToRu { inputFocused = true }
        }
    }

    @ViewBuilder
    private func typingInputSection(revealed: Bool) -> some View {
        // Single-line so Return triggers onSubmit. Russian answers are short
        // phrases — multiline would just hide the Prüfen button behind the
        // keyboard.
        TextField("Auf Russisch tippen…", text: $input)
            .font(.title3)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.go)
            .focused($inputFocused)
            .onSubmit { submit(revealed: revealed) }
            .toolbar {
                // Keyboard accessory — gives an explicit dismiss and a
                // fat one-tap submit that's visible even when the main
                // Prüfen button is just under the keyboard top edge.
                ToolbarItemGroup(placement: .keyboard) {
                    Button("Tastatur zu") { inputFocused = false }
                    Spacer()
                    Button("Prüfen") { submit(revealed: revealed) }
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .fontWeight(.semibold)
                }
            }

        Button {
            submit(revealed: revealed)
        } label: {
            Text("Prüfen")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @ViewBuilder
    private func speakInputSection(revealed: Bool) -> some View {
        VStack(spacing: 12) {
            if !speech.transcription.isEmpty {
                Text(speech.transcription)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if let msg = speechErrorMessage {
                Text(msg)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                if speech.isRecording {
                    speech.stop()
                    submit(revealed: revealed)
                } else {
                    startRecording()
                }
            } label: {
                HStack {
                    Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                    Text(speech.isRecording ? "Stoppen & Prüfen" : "Aufnahme starten")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(speech.isRecording ? .red : .accentColor)
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

    private func revealContent(
        card: StudyCard,
        result: GradeResult,
        userAnswer: String,
        responseTimeMs: Int
    ) -> some View {
        VStack(spacing: 20) {
            HStack {
                gradeChip(for: result.autoGrade)
                Spacer()
                Button {
                    tts.speak(card.phrase?.targetText ?? "")
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
            }
            .padding(.top)

            DiffView(
                expected: card.phrase?.targetText ?? "",
                actual: userAnswer
            )
            .padding(.vertical)

            if shouldShowTransliteration, let translit = card.phrase?.transliteration {
                Text(translit)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            Text("Bewertung — überschreiben falls falsch:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                ForEach(ratingButtons, id: \.rating) { item in
                    overrideButton(
                        rating: item.rating,
                        label: item.label,
                        color: item.color,
                        suggested: result.autoGrade.suggestedRating,
                        onTap: {
                            confirm(
                                rating: item.rating,
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
        .onAppear {
            tts.speak(card.phrase?.targetText ?? "")
        }
    }

    private var emptyContent: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Alles erledigt!")
                .font(.title.weight(.semibold))
            Text("Keine fälligen Karten. Komm später wieder.")
                .font(.body)
                .foregroundStyle(.secondary)
            Button {
                showingLibrary = true
            } label: {
                Label("Bibliothek öffnen", systemImage: "books.vertical")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            Spacer()
        }
    }

    private func gradeChip(for grade: AutoGrade) -> some View {
        Text(grade.label)
            .font(.headline)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(color(for: grade).opacity(0.18))
            .foregroundStyle(color(for: grade))
            .clipShape(Capsule())
    }

    private func color(for grade: AutoGrade) -> Color {
        switch grade {
        case .perfect: return .green
        case .hesitant: return .yellow
        case .minor: return .orange
        case .wrong: return .red
        }
    }

    private struct RatingButton {
        let rating: Int
        let label: String
        let color: Color
    }

    private var ratingButtons: [RatingButton] {
        [
            .init(rating: 1, label: "Nochmal", color: .red),
            .init(rating: 2, label: "Schwer", color: .orange),
            .init(rating: 3, label: "Gut", color: .green),
            .init(rating: 4, label: "Leicht", color: .blue),
        ]
    }

    private func overrideButton(
        rating: Int,
        label: String,
        color: Color,
        suggested: Int,
        onTap: @escaping () -> Void
    ) -> some View {
        let isSuggested = rating == suggested
        return Button(action: onTap) {
            Text(label)
                .font(.subheadline.weight(isSuggested ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isSuggested ? color.opacity(0.18) : Color(.systemGray6))
                .foregroundStyle(isSuggested ? color : Color.primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSuggested ? color : Color.clear, lineWidth: 2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

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

        // Run grading async so we can include the optional Tier-3 judge.
        // The synchronous Tier-1/2 path returns immediately when the judge
        // isn't needed, so there's no perceived latency for the common case.
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
            // Copy-typing after reveal: don't let a perfect copy auto-promote.
            // SRS still treats this as "didn't recall."
            result = GradeResult(
                autoGrade: .wrong,
                tier: result.tier,
                normalizedExpected: result.normalizedExpected,
                normalizedActual: result.normalizedActual,
                editedWords: result.editedWords,
                totalEdits: result.totalEdits
            )
        } else if mode == .speakDeToRu, result.autoGrade == .perfect {
            // Hesitancy: long start delay or mid-utterance pause → demote to Hesitant.
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
            // M2: surface errors visibly in M4 polish; for now log and continue.
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

    private func advance() {
        let limit = settings.first?.dailyNewLimit ?? 10
        if let next = scheduler.nextCard(from: cards, direction: mode, reviews: reviews, dailyNewLimit: limit) {
            phase = .prompt(next)
        } else {
            phase = .empty
        }
    }
}
