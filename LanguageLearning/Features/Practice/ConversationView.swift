import SwiftUI
import SwiftData

struct ConversationView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [AppSettings]
    @Query private var phrases: [Phrase]
    @Query(sort: \Topic.name) private var topics: [Topic]

    @StateObject private var speech = SpeechRecognitionService()
    @State private var turns: [ConversationTurn] = []
    @State private var draft = ""
    @State private var isThinking = false
    @State private var errorMessage: String?
    @FocusState private var isDraftFocused: Bool

    private var languageCode: String { settings.first?.activeLanguageCode ?? "ru" }
    private var pack: LanguagePack { LanguagePack.configuration(for: languageCode) ?? .russian }
    private var activeTopic: Topic? {
        topics.first { $0.isActive && $0.language?.code == languageCode }
    }
    private var scenario: String { activeTopic?.name ?? "Alltag und erste Begegnung" }
    private var vocabulary: [String] {
        let topicPhrases = activeTopic?.phrases ?? []
        let pool = topicPhrases.isEmpty
            ? phrases.filter { $0.language?.code == languageCode }
            : topicPhrases
        return Array(pool.prefix(40).map(\.targetText))
    }
    private var canSend: Bool {
        coachAvailable && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking
    }
    private var coachAvailable: Bool {
        if #available(iOS 26.0, *) { return ConversationCoach.isAvailable }
        return false
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                contextHeader
                Divider()
                conversation
                if coachAvailable { composer } else { unavailableFooter }
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
                if turns.isEmpty {
                    turns = [.init(
                        speaker: .coach,
                        text: openingLine
                    )]
                }
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

    private var unavailableFooter: some View {
        Label(
            "Gespräch benötigt Apple Intelligence auf einem unterstützten Gerät. Alle regulären Übungen bleiben verfügbar.",
            systemImage: "apple.intelligence"
        )
        .font(.footnote)
        .foregroundStyle(DS.textSecondary)
        .padding(DS.space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .combine)
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

    private var openingLine: String {
        switch languageCode {
        case "ar": return "مرحباً! كيف حالك اليوم؟"
        default: return "Привет! Как у тебя сегодня дела?"
        }
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
        guard !text.isEmpty, !isThinking else { return }
        if speech.isRecording { speech.stop() }
        let priorTurns = turns
        turns.append(.init(speaker: .learner, text: text))
        draft = ""
        isThinking = true

        Task {
            do {
                guard #available(iOS 26.0, *), ConversationCoach.isAvailable else {
                    throw ConversationCoachError.unavailable
                }
                let response = try await ConversationCoach().reply(
                    targetLanguage: pack.germanLabel,
                    scenario: scenario,
                    vocabulary: vocabulary,
                    turns: priorTurns,
                    learnerText: text
                )
                turns.append(.init(speaker: .coach, text: response))
                TTSService.shared.speak(response, language: pack.ttsLocale)
            } catch {
                errorMessage = error.localizedDescription
            }
            isThinking = false
        }
    }
}
