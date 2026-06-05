import SwiftUI
import SwiftData
import UIKit

/// "Sprint" — a 60-second fluency round. German prompts come fast; you SAY the
/// translation out loud; on-device speech recognition auto-advances the moment
/// it hears a close-enough match — hands-free, no tap between cards. The score
/// is pure output volume (cards cleared), gamified by speed, not accuracy.
///
/// Deliberately *outside* the FSRS schedule: Sprint is a warm-up / fluency game,
/// not spaced study, so it records no `Review` and changes no card's due date.
/// It only tracks a personal best (UserDefaults via `@AppStorage`). Low-stakes
/// by design — the point is to get your mouth moving, not to be graded. The
/// transcription is shown as a mirror, never a "wrong".
///
/// NOTE: the live microphone loop can only be exercised on a real device — the
/// simulator has no speech input. The UI states and the match logic
/// (`SprintMatcher`, unit-tested) are verifiable without a mic.
struct SprintView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Query private var cards: [StudyCard]
    @Query private var settings: [AppSettings]
    @Query private var languages: [Language]

    @StateObject private var speech = SpeechRecognitionService()
    @AppStorage("sprintBest") private var best: Int = 0

    @State private var phase: Phase = .intro
    @State private var pool: [Phrase] = []
    @State private var index = 0
    @State private var cleared = 0
    @State private var endDate = Date()
    @State private var now = Date()
    @State private var baseline = ""          // transcription prefix at card start
    @State private var bestAtRoundStart = 0   // to detect a new personal best
    @State private var speechDenied = false
    @State private var pulse = false

    private let duration: TimeInterval = 60
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    enum Phase { case intro, running, done }

    // MARK: - Derived

    private var activeCode: String { settings.first?.activeLanguageCode ?? "ru" }
    private var activeLanguage: Language? { languages.first { $0.code == activeCode } }
    private var currentPhrase: Phrase? {
        guard !pool.isEmpty else { return nil }
        return pool[index % pool.count]
    }
    private var remaining: TimeInterval { max(0, endDate.timeIntervalSince(now)) }
    private var progress: CGFloat { CGFloat(max(0, min(1, remaining / duration))) }
    private var spokenTail: String {
        speech.transcription.hasPrefix(baseline)
            ? String(speech.transcription.dropFirst(baseline.count))
            : speech.transcription
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            LinearGradient(colors: [DS.surface0, DS.surface2.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            switch phase {
            case .intro:   introView
            case .running: runningView
            case .done:    doneView
            }
        }
        .onAppear(perform: handleAppear)
        .onDisappear { speech.stop() }
        .onReceive(ticker) { t in
            guard phase == .running else { return }
            now = t
            if remaining <= 0 { endRound() }
        }
        .onChange(of: speech.transcription) { _, _ in
            guard phase == .running, let target = currentPhrase?.targetText else { return }
            if SprintMatcher.matches(spokenTail: spokenTail, target: target) {
                clearCurrent()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Backgrounding mid-sprint shouldn't keep the mic hot.
            if newPhase != .active, phase == .running { endRound() }
        }
    }

    // MARK: - Intro

    private var introView: some View {
        VStack(spacing: DS.space.lg) {
            HStack {
                closeButton
                Spacer()
            }
            Spacer()
            Image(systemName: "bolt.fill")
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(DS.accent)
                .frame(width: 104, height: 104)
                .background(DS.accentSoft)
                .clipShape(Circle())
            VStack(spacing: DS.space.sm) {
                Text("Sprint")
                    .font(.system(size: 40, weight: .bold, design: .serif))
                    .foregroundStyle(DS.textPrimary)
                Text("60 Sekunden. Sag die Übersetzung laut — so viele wie du schaffst. Es hört mit und springt von selbst weiter.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, DS.space.md)
            }
            if best > 0 {
                Label("Bestleistung: \(best)", systemImage: "trophy.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.gradeHesitant)
                    .padding(.horizontal, DS.space.md)
                    .padding(.vertical, DS.space.sm)
                    .background(DS.gradeHesitant.opacity(0.12))
                    .clipShape(Capsule())
            }
            Spacer()
            primaryButton(title: "Los geht's", systemImage: "play.fill") { startRound() }
            Text("Zählt nicht in deinen Lernplan — reine Sprechübung.")
                .font(.caption)
                .foregroundStyle(DS.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(DS.space.lg)
    }

    // MARK: - Running

    private var runningView: some View {
        VStack(spacing: DS.space.md) {
            timerBar
            HStack {
                clearedBadge
                Spacer()
                listeningIndicator
            }
            Spacer(minLength: 0)
            promptCard
            transcriptionMirror
            Spacer(minLength: 0)
            skipButton
        }
        .padding(DS.space.lg)
    }

    private var timerBar: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.surface1)
                    Capsule()
                        .fill(remaining <= 10 ? DS.gradeWrong : DS.accent)
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 8)
            HStack {
                Text("\(Int(ceil(remaining))) s")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(remaining <= 10 ? DS.gradeWrong : DS.textSecondary)
                Spacer()
                closeButton
            }
        }
    }

    private var clearedBadge: some View {
        HStack(spacing: 8) {
            Text("\(cleared)")
                .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(DS.accent)
                .contentTransition(.numericText())
            Text("gesagt")
                .font(.subheadline)
                .foregroundStyle(DS.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(cleared) gesagt")
    }

    @ViewBuilder
    private var listeningIndicator: some View {
        if speechDenied {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                Circle()
                    .fill(DS.gradePerfect)
                    .frame(width: 9, height: 9)
                    .scaleEffect(pulse && !reduceMotion ? 1.0 : 0.6)
                    .opacity(pulse || reduceMotion ? 1 : 0.5)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                Text("hört zu")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DS.textSecondary)
            }
            .accessibilityLabel("Mikrofon hört zu")
        }
    }

    private var promptCard: some View {
        let text = currentPhrase?.sourceText ?? "—"
        let base: CGFloat = text.count > 40 ? 24 : (text.count > 20 ? 32 : 42)
        return Text(text)
            .font(.system(size: base, weight: .bold, design: .serif))
            .multilineTextAlignment(.center)
            .foregroundStyle(DS.textPrimary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DS.space.lg)
            .padding(.vertical, DS.space.xxl)
            .dsFlashcardSurface()
            .id(index)   // fresh transition per card
            .transition(reduceMotion ? .opacity : .push(from: .trailing))
            .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.8), value: index)
    }

    @ViewBuilder
    private var transcriptionMirror: some View {
        if speechDenied {
            VStack(spacing: DS.space.sm) {
                Text("Sprint braucht das Mikrofon und die Spracherkennung.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DS.textSecondary)
                Button("In Einstellungen erlauben") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.accent)
            }
            .frame(minHeight: 44)
        } else {
            Text(spokenTail.isEmpty ? " " : spokenTail)
                .font(.title3)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, DS.space.md)
                .background(DS.surface1.opacity(spokenTail.isEmpty ? 0 : 1))
                .clipShape(Capsule())
                .accessibilityHidden(true)
        }
    }

    private var skipButton: some View {
        Button { skip() } label: {
            HStack(spacing: 6) {
                Text("Konnte ich nicht")
                Image(systemName: "arrow.right")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(DS.textSecondary)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(DS.surface1)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Überspringt diese Karte ohne Punkt")
    }

    // MARK: - Done

    private var doneView: some View {
        let isRecord = cleared > bestAtRoundStart && cleared > 0
        return VStack(spacing: DS.space.lg) {
            Spacer()
            if isRecord {
                Label("Neue Bestleistung!", systemImage: "trophy.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.space.md)
                    .padding(.vertical, DS.space.sm)
                    .background(Capsule().fill(DS.gradeHesitant))
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }
            Text("\(cleared)")
                .font(.system(size: 88, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(DS.accent)
            Text(doneMessage)
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, DS.space.lg)
            if !isRecord && best > 0 {
                Text("Bestleistung: \(best)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DS.textTertiary)
            }
            Spacer()
            primaryButton(title: "Nochmal", systemImage: "arrow.clockwise") { startRound() }
            Button("Fertig") { dismiss() }
                .font(.headline)
                .foregroundStyle(DS.textSecondary)
                .padding(.vertical, DS.space.sm)
        }
        .padding(DS.space.lg)
    }

    private var doneMessage: String {
        switch cleared {
        case 0:      return "Beim nächsten Mal. Einfach lossprechen — Tempo kommt von selbst."
        case 1...9:  return "Stimme ist warm. Gleich nochmal?"
        case 10...19: return "Schöner Redefluss."
        default:     return "Auf Flammen — das war flüssig."
        }
    }

    // MARK: - Shared chrome

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.callout.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 36, height: 36)
                .background(DS.surface1)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sprint schließen")
    }

    private func primaryButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Capsule().fill(DS.accent))
                .shadow(color: DS.accent.opacity(0.30), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Round lifecycle

    private func handleAppear() {
        if let locale = activeLanguage?.speechLocale { speech.setLocale(locale) }
    }

    private func startRound() {
        pool = buildPool()
        index = 0
        cleared = 0
        baseline = ""
        speechDenied = false
        bestAtRoundStart = best
        endDate = Date().addingTimeInterval(duration)
        now = Date()
        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.2)) { phase = .running }
        pulse = true
        beginListening()
    }

    private func beginListening() {
        speech.clearTranscription()
        Task {
            let authorized = await speech.requestAuthorization()
            guard authorized else {
                await MainActor.run { speechDenied = true }
                return
            }
            do { try speech.start() } catch {
                await MainActor.run { speechDenied = true }
            }
        }
    }

    private func clearCurrent() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8)) {
            cleared += 1
        }
        advance()
    }

    private func skip() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        advance()
    }

    /// Move to the next prompt and ignore everything said so far, so the next
    /// card matches only new speech.
    private func advance() {
        baseline = speech.transcription
        withAnimation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.8)) {
            index += 1
        }
    }

    private func endRound() {
        speech.stop()
        pulse = false
        if cleared > best { best = cleared }
        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) { phase = .done }
    }

    /// Unique phrases in the active language, preferring ones the user has
    /// already seen (a card past `.new`) so they can plausibly be said fast.
    /// Falls back to all active-language phrases if too few are "seen".
    private func buildPool() -> [Phrase] {
        var seen: [PersistentIdentifier: Phrase] = [:]
        var all: [PersistentIdentifier: Phrase] = [:]
        for card in cards {
            guard let phrase = card.phrase,
                  phrase.language?.code == activeCode,
                  !phrase.targetText.isEmpty else { continue }
            all[phrase.persistentModelID] = phrase
            if card.state != .new { seen[phrase.persistentModelID] = phrase }
        }
        let preferred = Array(seen.values)
        let source = preferred.count >= 8 ? preferred : Array(all.values)
        return source.shuffled()
    }
}
