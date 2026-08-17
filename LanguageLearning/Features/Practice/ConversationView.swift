import SwiftUI
import SwiftData

struct ConversationView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [AppSettings]

    @StateObject private var speech = SpeechRecognitionService()
    @State private var selectedScenario: GuidedRoleplay?
    @State private var turns: [ConversationTurn] = []
    @State private var stepIndex = 0
    @State private var independentTurns = 0
    @State private var coachingNote: String?
    @State private var isComplete = false
    @State private var draft = ""
    @State private var isThinking = false
    @State private var errorMessage: String?
    @FocusState private var isDraftFocused: Bool

    private var languageCode: String { settings.first?.activeLanguageCode ?? "ru" }
    private var pack: LanguagePack { LanguagePack.configuration(for: languageCode) ?? .russian }
    private var scenario: String { selectedScenario?.title ?? "Gespräch" }
    private var canSend: Bool {
        selectedScenario != nil
            && !isComplete
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isThinking
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if selectedScenario == nil {
                    scenarioPicker
                } else {
                    contextHeader
                    Divider()
                    conversation
                    if isComplete { completionFooter } else { composer }
                }
            }
            .background(DS.surface0)
            .navigationTitle("Gespräch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .onAppear {
                speech.setLocale(pack.speechLocale)
            }
            .onDisappear {
                speech.stop()
                TTSService.shared.stop()
            }
            .onChange(of: speech.transcription) { _, value in
                if speech.isRecording { draft = value }
            }
            .alert("Gespräch gerade nicht verfügbar", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Bitte versuche es später erneut.")
            }
        }
    }

    private var scenarioPicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space.lg) {
                VStack(alignment: .leading, spacing: DS.space.xs) {
                    Text("Wo möchtest du sprechen?")
                        .font(.system(.title, design: .serif, weight: .bold))
                        .foregroundStyle(DS.textPrimary)
                    Text("Geführte Rollenspiele funktionieren auf jedem Gerät. Du antwortest frei; Beispiele helfen nur, wenn du sie brauchst.")
                        .font(.subheadline)
                        .foregroundStyle(DS.textSecondary)
                }
                ForEach(GuidedRoleplayLibrary.scenarios(languageCode: languageCode)) { roleplay in
                    Button { begin(roleplay) } label: {
                        HStack(spacing: DS.space.md) {
                            Image(systemName: roleplay.systemImage)
                                .font(.title2)
                                .foregroundStyle(DS.accent)
                                .frame(width: 52, height: 52)
                                .background(DS.accentSoft)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(roleplay.title)
                                    .font(.headline)
                                    .foregroundStyle(DS.textPrimary)
                                Text(roleplay.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(DS.textSecondary)
                                Text("3 kurze Gesprächszüge")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(DS.accent)
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
                    .accessibilityIdentifier("roleplay-\(roleplay.id)")
                    .accessibilityHint("Startet das Rollenspiel")
                }
                Label("Rollenspiele verändern deinen FSRS-Lernplan nicht.", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(DS.textSecondary)
            }
            .padding(DS.space.md)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
    }

    private var contextHeader: some View {
        HStack(spacing: DS.space.sm) {
            Image(systemName: "person.2.wave.2.fill")
                .foregroundStyle(DS.accent)
                .frame(width: 38, height: 38)
                .background(DS.accentSoft)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(scenario)
                    .font(.headline)
                    .foregroundStyle(DS.textPrimary)
                Text("Kurze Antworten · privat auf dem Gerät · ohne Bewertung")
                    .font(.caption)
                    .foregroundStyle(DS.textSecondary)
            }
            Spacer()
        }
        .padding(DS.space.md)
        .accessibilityElement(children: .combine)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DS.space.sm) {
                    ForEach(turns) { turn in
                        bubble(turn)
                            .id(turn.id)
                    }
                    if isThinking {
                        HStack(spacing: 6) {
                            ProgressView()
                            Text("Antwort wird formuliert …")
                                .font(.subheadline)
                                .foregroundStyle(DS.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, DS.space.md)
                    }
                    if let coachingNote {
                        Label(coachingNote, systemImage: "lightbulb.fill")
                            .font(.footnote)
                            .foregroundStyle(DS.textSecondary)
                            .padding(DS.space.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DS.accentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
                            .padding(.horizontal, DS.space.md)
                    }
                }
                .padding(.vertical, DS.space.md)
            }
            .onChange(of: turns.count) { _, _ in
                if let last = turns.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func bubble(_ turn: ConversationTurn) -> some View {
        let learner = turn.speaker == .learner
        return HStack(alignment: .bottom, spacing: DS.space.xs) {
            if learner { Spacer(minLength: 48) }
            VStack(alignment: learner ? .trailing : .leading, spacing: 4) {
                Text(turn.text)
                    .font(.body)
                    .foregroundStyle(learner ? Color.white : DS.textPrimary)
                    .multilineTextAlignment(pack.isRTL ? .trailing : .leading)
                    .environment(\.layoutDirection, pack.isRTL ? .rightToLeft : .leftToRight)
                if !learner {
                    Button {
                        TTSService.shared.speak(turn.text, language: pack.ttsLocale)
                    } label: {
                        Label("Anhören", systemImage: "speaker.wave.2.fill")
                            .font(.caption)
                    }
                    .foregroundStyle(DS.accent)
                }
            }
            .padding(.horizontal, DS.space.md)
            .padding(.vertical, DS.space.sm)
            .background(learner ? DS.accent : DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.lg))
            if !learner { Spacer(minLength: 48) }
        }
        .padding(.horizontal, DS.space.md)
    }

    private var composer: some View {
        VStack(spacing: DS.space.sm) {
            if let roleplay = selectedScenario, roleplay.steps.indices.contains(stepIndex) {
                HStack(alignment: .top, spacing: DS.space.xs) {
                    Image(systemName: "quote.bubble.fill")
                        .foregroundStyle(DS.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Deine Aufgabe")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(DS.accent)
                        Text(roleplay.steps[stepIndex].learnerGoal)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DS.textPrimary)
                    }
                    Spacer()
                    Text("\(stepIndex + 1)/\(roleplay.steps.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DS.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if speech.isRecording {
                Label("Ich höre zu … Tippe zum Stoppen", systemImage: "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.accent)
            }
            HStack(alignment: .bottom, spacing: DS.space.sm) {
                Button { toggleRecording() } label: {
                    Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(speech.isRecording ? DS.gradeWrong : DS.accent)
                        .clipShape(Circle())
                }
                .accessibilityLabel(speech.isRecording ? "Aufnahme stoppen" : "Antwort sprechen")
                .disabled(isThinking)

                TextField("Oder Antwort eingeben", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($isDraftFocused)
                    .lineLimit(1...4)
                    .padding(.horizontal, DS.space.sm)
                    .padding(.vertical, 12)
                    .background(DS.surface1)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))

                Button { submit() } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(canSend ? DS.accent : DS.textTertiary)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Antwort senden")
                .disabled(!canSend)
            }
        }
        .padding(DS.space.md)
        .background(.ultraThinMaterial)
    }

    private var completionFooter: some View {
        VStack(spacing: DS.space.sm) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(DS.gradePerfect)
            Text("Gespräch geschafft")
                .font(.headline)
                .foregroundStyle(DS.textPrimary)
            Text("\(independentTurns) von \(selectedScenario?.steps.count ?? 0) Antworten ohne Beispielhilfe formuliert")
                .font(.subheadline)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
            Button("Anderes Gespräch wählen") { resetConversation() }
                .buttonStyle(.borderedProminent)
                .tint(DS.accent)
        }
        .padding(DS.space.md)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private func toggleRecording() {
        if speech.isRecording {
            speech.stop()
            if canSend { submit() }
            return
        }
        isDraftFocused = false
        Task {
            guard await speech.requestAuthorization() else {
                errorMessage = "Mikrofon oder Spracherkennung ist nicht freigegeben. Du kannst deine Antwort weiterhin eintippen."
                return
            }
            do {
                speech.clearTranscription()
                try speech.start()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              !isThinking,
              let roleplay = selectedScenario,
              let progress = GuidedRoleplayEngine.progress(
                scenario: roleplay,
                stepIndex: stepIndex,
                learnerText: text
              )
        else { return }
        if speech.isRecording { speech.stop() }
        turns.append(.init(speaker: .learner, text: text))
        draft = ""
        isThinking = true
        switch progress.support {
        case .independent:
            independentTurns += 1
            coachingNote = nil
        case .close(let reference):
            coachingNote = "Nahe an einer möglichen Formulierung: \(reference)"
        case .model(let reference):
            coachingNote = "Eine mögliche Formulierung: \(reference)"
        }
        turns.append(.init(speaker: .coach, text: progress.partnerReply))
        TTSService.shared.speak(progress.partnerReply, language: pack.ttsLocale)
        stepIndex += 1
        isComplete = progress.isComplete
        isThinking = false
        if isComplete { CompletionFeedbackService.shared.playCompletion() }
    }

    private func begin(_ roleplay: GuidedRoleplay) {
        selectedScenario = roleplay
        stepIndex = 0
        independentTurns = 0
        coachingNote = nil
        isComplete = false
        turns = [.init(speaker: .coach, text: roleplay.openingText)]
        TTSService.shared.speak(roleplay.openingText, language: pack.ttsLocale)
    }

    private func resetConversation() {
        speech.stop()
        selectedScenario = nil
        turns = []
        draft = ""
        stepIndex = 0
        independentTurns = 0
        coachingNote = nil
        isComplete = false
    }
}
