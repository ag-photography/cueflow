import SwiftData
import SwiftUI

struct ListeningLabView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var phrases: [Phrase]
    @Query private var settings: [AppSettings]
    @State private var challenge: ListeningChallenge?
    @State private var options: [String] = []
    @State private var selected: String?
    @State private var completed = 0
    @State private var isShadowing = false
    @State private var hasShadowed = false
    @State private var shadowingTimeout: Task<Void, Never>?
    @StateObject private var speech = SpeechRecognitionService()

    private var languageCode: String { settings.first?.activeLanguageCode ?? "ru" }
    private var pack: LanguagePack {
        LanguagePack.configuration(for: languageCode) ?? .russian
    }
    private var eligible: [Phrase] {
        phrases.filter {
            $0.language?.code == languageCode
                && !$0.targetText.isEmpty
                && !$0.sourceText.isEmpty
                && (($0.topics?.contains(where: \.isActive) ?? false) || ($0.cards?.first?.state.isIntroduced ?? false))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.space.lg) {
                progressHeader
                Spacer(minLength: DS.space.sm)
                if let challenge {
                    if isShadowing {
                        shadowingCard(challenge)
                    } else {
                        listeningCard(challenge)
                    }
                } else {
                    ContentUnavailableView(
                        "Noch nicht genug Hörmaterial",
                        systemImage: "ear",
                        description: Text("Aktiviere eine Mission mit mindestens drei Ausdrücken.")
                    )
                }
                Spacer()
            }
            .padding(DS.space.md)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .background(DS.surface0.ignoresSafeArea())
            .navigationTitle("Hörstudio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .onAppear {
                speech.setLocale(pack.speechLocale)
                loadNext()
            }
            .onDisappear {
                shadowingTimeout?.cancel()
                speech.stop()
                ReferenceAudioService.shared.stop()
            }
        }
        .accessibilityIdentifier("listening-lab")
    }

    private var progressHeader: some View {
        HStack {
            Label("Hören → verstehen → nachsprechen", systemImage: "ear.and.waveform")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
            Spacer()
            Text("\(completed)/5")
                .font(.caption.monospacedDigit())
                .foregroundStyle(DS.textTertiary)
        }
    }

    private func listeningCard(_ challenge: ListeningChallenge) -> some View {
        VStack(spacing: DS.space.lg) {
            Text("Was bedeutet dieser Ausdruck?")
                .font(.title2.bold())
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.center)
            Button {
                play(challenge, slow: false)
            } label: {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 88, height: 88)
                    .background(DS.accent)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Ausdruck noch einmal anhören")

            VStack(spacing: DS.space.sm) {
                ForEach(options, id: \.self) { option in
                    Button {
                        guard selected == nil else { return }
                        selected = option
                        if option == challenge.correctMeaning {
                            CompletionFeedbackService.shared.playStepSuccess()
                        }
                    } label: {
                        HStack {
                            Text(option).multilineTextAlignment(.leading)
                            Spacer()
                            if selected != nil && option == challenge.correctMeaning {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.gradePerfect)
                            } else if selected == option {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(DS.gradeWrong)
                            }
                        }
                        .padding(DS.space.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.surface1)
                        .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
                    }
                    .buttonStyle(.plain)
                    .disabled(selected != nil)
                }
            }
            if selected != nil {
                Button("Jetzt nachsprechen") { isShadowing = true }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.accent)
            }
        }
        .onAppear { play(challenge, slow: false) }
    }

    private func shadowingCard(_ challenge: ListeningChallenge) -> some View {
        VStack(spacing: DS.space.lg) {
            Text("Sprich Rhythmus und Melodie nach")
                .font(.title2.bold())
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.center)
            Text(challenge.spokenText)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .environment(\.layoutDirection, pack.isRTL ? .rightToLeft : .leftToRight)
            HStack(spacing: DS.space.md) {
                Button { play(challenge, slow: true) } label: {
                    Label("Langsam", systemImage: "tortoise.fill")
                }
                .buttonStyle(.bordered)
                Button { toggleShadowing() } label: {
                    Label(speech.isRecording ? "Stoppen" : "Nachsprechen", systemImage: speech.isRecording ? "stop.fill" : "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(speech.isRecording ? DS.gradeWrong : DS.accent)
            }
            if hasShadowed {
                VStack(spacing: 4) {
                    Label("Nachgesprochen", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(DS.gradePerfect)
                    Text("Das war eine Rhythmusübung – keine Aussprachebewertung.")
                        .font(.caption)
                        .foregroundStyle(DS.textSecondary)
                        .multilineTextAlignment(.center)
                }
                Button(completed >= 4 ? "Hörstudio abschließen" : "Nächster Ausdruck") {
                    completed += 1
                    if completed >= 5 {
                        CompletionFeedbackService.shared.playCompletion()
                        dismiss()
                    } else {
                        loadNext()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.accent)
            }
        }
    }

    private func play(_ challenge: ListeningChallenge, slow: Bool) {
        ReferenceAudioService.shared.play(
            text: challenge.spokenText,
            locale: challenge.locale,
            audioFileName: eligible.first(where: {
                String(describing: $0.persistentModelID) == challenge.phraseID
            })?.audioFileName,
            slow: slow
        )
    }

    private func toggleShadowing() {
        if speech.isRecording {
            shadowingTimeout?.cancel()
            speech.stop()
            hasShadowed = true
            return
        }
        Task {
            ReferenceAudioService.shared.stop()
            guard await speech.requestAuthorization() else {
                // Shadowing remains useful without recording permission: the
                // learner can speak along and confirm completion themselves.
                hasShadowed = true
                return
            }
            do {
                speech.clearTranscription()
                try speech.start()
                shadowingTimeout?.cancel()
                shadowingTimeout = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(6))
                    guard !Task.isCancelled, speech.isRecording else { return }
                    speech.stop()
                    hasShadowed = true
                }
            } catch {
                hasShadowed = true
            }
        }
    }

    private func loadNext() {
        speech.stop()
        shadowingTimeout?.cancel()
        ReferenceAudioService.shared.stop()
        selected = nil
        isShadowing = false
        hasShadowed = false
        let pool = eligible
        guard pool.count >= 3 else {
            challenge = nil
            options = []
            return
        }
        let index = completed % pool.count
        let phrase = pool[index]
        let distractors = pool.enumerated()
            .filter { $0.offset != index }
            .map { $0.element.sourceText }
        challenge = ListeningPracticeBuilder.challenge(
            phraseID: String(describing: phrase.persistentModelID),
            spokenText: phrase.targetText,
            meaning: phrase.sourceText,
            languageCode: languageCode,
            locale: pack.ttsLocale,
            distractorMeanings: distractors
        )
        options = challenge?.options.shuffled() ?? []
    }
}
