import SwiftUI
import SwiftData

/// A finite, resumable pilot lesson. Authored-model matching is deliberately
/// labelled as such: these drafts do not certify free conversation. Eligible
/// canonical retrievals update FSRS through EpisodeVocabulary, never the view.
struct EpisodeView: View {
    let episode: LearningEpisode
    var calibration = false
    var previewSessionID: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var settings: [AppSettings]
    @StateObject private var speech = SpeechRecognitionService()
    @State private var run: EpisodeRun?
    @State private var input = ""
    @State private var quiet = true
    @State private var error: String?
    @State private var permissionTask: Task<Void, Never>?
    @State private var permissionGeneration = UUID()
    @State private var submittedWithVoice = false
    @State private var activeSince: Date?
    @State private var nextEpisode: LearningEpisode?
    @State private var newLimitWarning: Int?
    @State private var allowExtraIntroductions = false

    private var pack: LanguagePack { LanguagePack.configuration(for: episode.language) ?? .russian }
    private var step: LearningEpisode.Step? {
        guard let run, episode.steps.indices.contains(run.stepIndex) else { return nil }
        return episode.steps[run.stepIndex]
    }
    private var result: EpisodeAttempt? { run?.attempts.first { $0.stepID == step?.id } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space.lg) {
                    if let error { Text(error).foregroundStyle(DS.gradeWrong).accessibilityIdentifier("episode-error") }
                    if let run {
                        scene(run)
                        if run.completedAt != nil { completion(run) }
                        else if let step { exercise(step, run: run) }
                    } else {
                        if error != nil { Button("Erneut versuchen") { load() } }
                        else { ProgressView().task { load() } }
                    }
                }
                .padding(DS.space.lg)
                .frame(maxWidth: DS.mainContentWidth)
                .frame(maxWidth: .infinity)
            }
            .background(DS.pageBackground.ignoresSafeArea())
            .navigationTitle("Mini-Geschichte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Pause") {
                        stopAudio()
                        if let run, run.isOpen, !save(run, event: "session_paused") { return }
                        dismiss()
                    }.accessibilityIdentifier("episode-close")
                }
            }
        }
        .onChange(of: speech.transcription) { _, text in
            if speech.isRecording { input = text; submittedWithVoice = true }
        }
        .onChange(of: speech.lastError) { _, message in
            if message != nil, let run, run.isOpen { _ = save(run, event: "recognition_failed") }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                stopAudio()
                if let run, run.isOpen { _ = save(run, event: "session_paused") }
                activeSince = nil
            } else if let run, run.isOpen {
                activeSince = .now
                _ = save(run, event: "session_resumed")
            }
        }
        .onChange(of: settings.first?.activeLanguageCode) { _, _ in stopAudio(); dismiss() }
        .onDisappear { stopAudio() }
        .fullScreenCover(item: $nextEpisode) { EpisodeView(episode: $0) }
        .alert("Dein Tageslimit für neue Ausdrücke", isPresented: Binding(get: { newLimitWarning != nil }, set: { if !$0 { newLimitWarning = nil } })) {
            Button("Für heute bei Wiederholungen bleiben", role: .cancel) { dismiss() }
            Button("Diese Geschichte trotzdem beginnen") { allowExtraIntroductions = true; newLimitWarning = nil; load() }
        } message: {
            Text("Diese Geschichte führt \(newLimitWarning ?? 0) neue Ausdrücke ein und würde dein Tageslimit überschreiten. Du entscheidest, ob du heute mehr lernen möchtest.")
        }
    }

    private func scene(_ run: EpisodeRun) -> some View {
        VStack(alignment: .leading, spacing: DS.space.md) {
            HStack {
                Label(episode.language == "ar" ? "Mit Lina · Hocharabisch" : "Mit Sascha · Russisch", systemImage: "person.crop.circle.fill")
                Spacer()
                Text("\(min(run.stepIndex + 1, episode.steps.count))/\(episode.steps.count)").monospacedDigit()
            }.font(.caption).foregroundStyle(DS.textSecondary)
            HStack(spacing: DS.space.lg) {
                Image(systemName: run.completedAt == nil ? episode.symbol : "checkmark.seal.fill")
                    .font(.system(size: 45)).foregroundStyle(DS.accent)
                    .frame(width: 90, height: 90)
                    .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: DS.radius.lg))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(episode.title).font(.title2.bold())
                    Text(run.completedAt == nil ? episode.hook : "Ihr habt die Szene zusammen abgeschlossen.")
                        .font(.subheadline).foregroundStyle(DS.textSecondary)
                }
            }
            ProgressView(value: Double(run.stepIndex), total: Double(episode.steps.count)).tint(DS.accent)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: run.stepIndex)
        }.padding(DS.space.md).background(DS.surface1, in: RoundedRectangle(cornerRadius: DS.radius.lg))
    }

    @ViewBuilder private func exercise(_ step: LearningEpisode.Step, run: EpisodeRun) -> some View {
        VStack(alignment: .leading, spacing: DS.space.md) {
            if step.kind == .model {
                Text(step.prompt).font(.headline)
                target(step.answer)
                Text(step.meaning).foregroundStyle(DS.textSecondary)
                Button { ReferenceAudioService.shared.play(text: step.answer, locale: pack.ttsLocale) } label: {
                    Label("Anhören", systemImage: "speaker.wave.2.fill")
                }.buttonStyle(.bordered).accessibilityIdentifier("episode-audio")
                Text("Lies die Formulierung. Gleich probierst du es ohne Vorlage.")
                    .font(.footnote).foregroundStyle(DS.textSecondary)
                nextButton("Merken und weiter")
            } else {
                Text(step.kind == .transfer ? "Jetzt bist du dran" : "Aus dem Gedächtnis")
                    .font(.caption.weight(.semibold)).foregroundStyle(DS.accent)
                Text(step.prompt).font(.title3.weight(.semibold))
                if let result {
                    Label(result.correct ? "Formulierung getroffen" : "Eine mögliche Formulierung", systemImage: result.correct ? "checkmark.circle.fill" : "lightbulb.fill")
                        .foregroundStyle(result.correct ? DS.gradePerfect : DS.textSecondary)
                    target(step.answer)
                    Text(episode.consequence(for: step, correct: result.correct))
                        .font(.subheadline)
                    Text(result.supported ? "Mit Unterstützung geübt. Das zählt als Übung, nicht als freier Abruf." : "Dein erster Versuch wurde gespeichert.")
                        .font(.footnote).foregroundStyle(DS.textSecondary)
                    nextButton("Weiter")
                } else {
                    Toggle("Leise üben", isOn: $quiet)
                        .onChange(of: quiet) { _, value in
                            stopAudio()
                            submittedWithVoice = false
                            savePreference(quiet: value)
                        }
                    if run.modelRevealed { target(step.answer) }
                    TextField("Deine Antwort", text: Binding(get: { input }, set: { input = $0; submittedWithVoice = false }), axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(2...5)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .environment(\.layoutDirection, pack.isRTL ? .rightToLeft : .leftToRight)
                        .accessibilityIdentifier("episode-answer")
                    if !quiet {
                        Button {
                            if speech.isRecording { speech.stop() } else { startRecording() }
                        } label: {
                            Label(speech.isRecording ? "Aufnahme stoppen" : "Antwort sprechen", systemImage: speech.isRecording ? "stop.fill" : "mic.fill")
                        }.buttonStyle(.bordered)
                        if let message = speech.lastError { Text(message).font(.footnote).foregroundStyle(DS.textSecondary) }
                    }
                    Button("Prüfen") { submit(step) }
                        .buttonStyle(.borderedProminent).tint(DS.accent)
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || permissionTask != nil)
                        .accessibilityIdentifier("episode-check")
                    Button("Formulierung zeigen") {
                        stopAudio()
                        var candidate = run
                        candidate.modelRevealed = true
                        _ = save(candidate, event: "support_used", step: step.id)
                    }.disabled(run.modelRevealed)
                    Button("Noch unsicher · gemeinsam weiter") {
                        stopAudio()
                        var candidate = run
                        candidate.attempts.append(.init(stepID: step.id, correct: false, supported: true, spoken: false, timestamp: .now))
                        _ = save(candidate, event: "answer_submitted", step: step.id)
                    }.font(.footnote)
                }
            }
        }
    }

    private func target(_ text: String) -> some View {
        Text(text).font(LearningTypography.display(.title2, languageCode: episode.language))
            .frame(maxWidth: .infinity, alignment: pack.isRTL ? .trailing : .leading)
            .padding().background(DS.surface1, in: RoundedRectangle(cornerRadius: DS.radius.md))
    }
    private func nextButton(_ title: String) -> some View {
        Button(title) { advance() }.buttonStyle(.borderedProminent).tint(DS.accent)
            .accessibilityIdentifier("episode-next")
    }
    private func completion(_ run: EpisodeRun) -> some View {
        VStack(alignment: .leading, spacing: DS.space.md) {
            Text(run.calibration == true ? "Startcheck geschafft" : "Geschichte geschafft").font(.title.bold())
            Text(episode.outcome)
            Text("\(run.independentCount) von \(run.attempts.count) Antworten ohne eingeblendete Hilfe getroffen.")
            Text(run.isDelayedCheck ? "Das war eine zeitversetzte Wiederholung, kein Nachweis für freies Sprechen. In einer Woche kannst du erneut prüfen." : "Ab morgen kannst du ohne Vorlage erneut prüfen, was hängen geblieben ist. Diese Vorschau vergleicht deine Antwort mit Kursformulierungen; andere richtige Antworten sind möglich.")
                .font(.footnote).foregroundStyle(DS.textSecondary)
            Button("Fertig") { dismiss() }.buttonStyle(.borderedProminent).tint(DS.accent)
                .accessibilityIdentifier("episode-finish")
            if let next = EpisodeLibrary.all.first(where: { $0.language == episode.language && $0.id != episode.id &&
                !((try? settings.first?.readExperience().completed(in: episode.language)) ?? []).contains($0.id) }) {
                Button("Noch eine Geschichte: \(next.title)") {
                    if save(run, event: "next_episode_selected") { nextEpisode = next }
                }.buttonStyle(.bordered).accessibilityIdentifier("episode-optional-next")
                Text("Eine neue Runde, nur wenn du möchtest. Für heute bist du fertig.").font(.caption).foregroundStyle(DS.textSecondary)
            }
        }
    }
    private func load() {
        do {
            guard episode.validationErrors.isEmpty else {
                error = "Diese Inhaltsversion kann nicht sicher gestartet werden. Bitte wähle eine andere Geschichte; dein Verlauf bleibt erhalten."
                return
            }
            guard let row = settings.first else { error = "Einstellungen werden noch geladen. Bitte versuche es erneut."; return }
            let data = try row.readExperience()
            quiet = data.preference(for: episode.language).quiet
            let existing = data.runs.last { $0.episodeID == episode.id && $0.contentVersion == episode.version && $0.isOpen }
            if existing == nil && !allowExtraIntroductions {
                let history = try context.fetch(FetchDescriptor<Review>()).filter { $0.card?.phrase?.language?.code == episode.language }
                let introducedToday = Set(history.filter { $0.wasNew && Calendar.current.isDateInToday($0.timestamp) }.compactMap { $0.card?.contentID }).count
                let introduced = Set(try context.fetch(FetchDescriptor<StudyCard>()).filter {
                    $0.phrase?.language?.code == episode.language && $0.hasBeenIntroduced
                }.compactMap { $0.phrase.map { EpisodeVocabulary.key(language: episode.language, answer: $0.targetText) } })
                let needed = Set(episode.steps.map { EpisodeVocabulary.key(language: episode.language, answer: $0.answer) }).subtracting(introduced).count
                if needed > max(0, row.dailyNewLimit - introducedToday) { newLimitWarning = needed; return }
            }
            if let existing, !existing.isValid(for: episode) {
                error = "Diese gespeicherte Geschichte kann nicht fortgesetzt werden. Dein Verlauf bleibt erhalten; bitte sichere ihn unter Einstellungen → Sicherung & Export."
                return
            }
            var candidate = existing ?? EpisodeRun(episodeID: episode.id, contentVersion: episode.version, language: episode.language)
            if existing == nil, let previewSessionID, !data.runs.contains(where: { $0.id == previewSessionID }) { candidate.id = previewSessionID }
            if existing == nil && calibration {
                candidate.calibration = true
                candidate.stepIndex = episode.steps.firstIndex { $0.kind != .model } ?? 0
            }
            if existing == nil && !calibration && data.isCheckDue(episode) {
                candidate.isDelayedCheck = true
                let lastExposure = max(data.runs.filter { $0.episodeID == episode.id }.map(\.updatedAt).max() ?? .distantPast,
                                       data.otherModeExposureAt?[episode.language] ?? .distantPast)
                candidate.exposureGapSeconds = Date.now.timeIntervalSince(lastExposure)
                candidate.stepIndex = episode.steps.firstIndex { $0.kind != .model } ?? 0
            }
            speech.setLocale(pack.speechLocale)
            activeSince = .now
            _ = save(candidate, event: existing == nil ? "session_started" : "session_resumed")
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult private func save(_ candidate: EpisodeRun, event: String, step: String? = nil) -> Bool {
        do {
            guard let row = settings.first else { return false }
            var data = try row.readExperience()
            var updated = candidate
            updated.updatedAt = .now
            updated.activeSeconds = (candidate.activeSeconds ?? 0) + min(60, max(0, activeSince.map { Date.now.timeIntervalSince($0) } ?? 0))
            if event == "answer_submitted", let stepID = step,
               let definition = episode.steps.first(where: { $0.id == stepID }),
               let attempt = candidate.attempts.first(where: { $0.stepID == stepID }) {
                try EpisodeVocabulary.record(episode: episode, run: updated, step: definition, attempt: attempt, context: context)
            }
            if episode.steps.indices.contains(candidate.stepIndex) {
                let definition = episode.steps[candidate.stepIndex]
                if definition.kind == .model || event == "support_used" {
                    try EpisodeVocabulary.record(episode: episode, run: updated, step: definition, attempt: nil, context: context)
                }
            }
            data.save(updated)
            data.event(event, run: updated, step: step)
            if event == "session_completed", updated.calibration == true {
                var preference = data.preference(for: episode.language)
                preference.calibrationAt = .now
                preference.calibrationCorrect = updated.independentCount
                data.preferences[episode.language] = preference
            }
            try row.writeExperience(data)
            try context.save()
            run = updated
            activeSince = scenePhase == .active ? .now : nil
            if event == "session_completed" {
                Task { await NotificationService.shared.refreshLearningReminder(settings: row, experience: data) }
            }
            error = nil
            return true
        } catch {
            context.rollback()
            self.error = "Fortschritt konnte nicht gespeichert werden: \(error.localizedDescription)"
            return false
        }
    }
    private func savePreference(quiet: Bool) {
        do {
            guard let row = settings.first else { return }
            var data = try row.readExperience()
            var preference = data.preference(for: episode.language)
            preference.quiet = quiet
            data.preferences[episode.language] = preference
            try row.writeExperience(data)
            try context.save()
        } catch { context.rollback(); self.error = error.localizedDescription }
    }
    private func submit(_ step: LearningEpisode.Step) {
        guard var candidate = run, result == nil else { return }
        speech.stop()
        let grade = GraderService().grade(expected: step.answer, actual: input, acceptedAlternatives: step.alternatives, responseTimeMs: 10_000)
        candidate.attempts.append(.init(stepID: step.id, correct: grade.autoGrade.suggestedRating >= 3,
                                       supported: candidate.modelRevealed, spoken: submittedWithVoice, timestamp: .now,
                                       spokenWordCount: submittedWithVoice ? input.split(whereSeparator: \.isWhitespace).count : 0))
        if save(candidate, event: "answer_submitted", step: step.id), grade.autoGrade.suggestedRating >= 3, !quiet {
            CompletionFeedbackService.shared.playStepSuccess()
        }
    }
    private func advance() {
        guard var candidate = run, let step, step.kind == .model || result != nil else { return }
        stopAudio()
        candidate.stepIndex = episode.nextIndex(after: candidate.stepIndex, attempt: result)
        candidate.modelRevealed = false
        if candidate.stepIndex == episode.steps.count { candidate.completedAt = .now }
        let nextID = episode.steps.indices.contains(candidate.stepIndex) ? episode.steps[candidate.stepIndex].id : step.id
        if save(candidate, event: candidate.completedAt == nil ? "step_presented" : "session_completed", step: nextID) {
            input = ""
            submittedWithVoice = false
            if candidate.completedAt != nil && !quiet { CompletionFeedbackService.shared.playCompletion() }
        }
    }
    private func startRecording() {
        ReferenceAudioService.shared.stop()
        let generation = UUID()
        permissionGeneration = generation
        permissionTask = Task { @MainActor in
            let allowed = await speech.requestAuthorization()
            guard !Task.isCancelled, permissionGeneration == generation else { return }
            defer { permissionTask = nil }
            guard allowed else { quiet = true; error = "Du kannst deine Antwort auch tippen."; return }
            do { try speech.start() } catch { quiet = true; self.error = error.localizedDescription }
        }
    }
    private func stopAudio() {
        permissionGeneration = UUID()
        permissionTask?.cancel()
        permissionTask = nil
        speech.stop()
        ReferenceAudioService.shared.stop()
    }
}
