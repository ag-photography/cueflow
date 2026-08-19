import SwiftData
import SwiftUI

/// The reading pass: connected sentences chosen to sit just past what the
/// learner has already stabilised.
///
/// Input, not assessment. Nothing here records a review or moves a schedule —
/// the point is volume of understandable text, which the app otherwise never
/// provided. Translations stay hidden until asked for so the first pass is a
/// genuine attempt at meaning.
struct ReadingView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var phrases: [Phrase]
    @Query private var settings: [AppSettings]

    @State private var passages: [ReadingPassage] = []
    @State private var revealed: Set<ContentID> = []
    @State private var isLoading = true

    private let tts = TTSService.shared

    private var languageCode: String { settings.first?.activeLanguageCode ?? "ru" }
    private var pack: LanguagePack { LanguagePack.configuration(for: languageCode) ?? .russian }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if passages.isEmpty {
                    ContentUnavailableView(
                        "Noch nicht genug gefestigt",
                        systemImage: "book",
                        description: Text("Sobald einige Ausdrücke eine Woche sitzen, erscheinen hier Sätze, die du fast vollständig verstehst.")
                    )
                } else {
                    content
                }
            }
            .background(DS.pageBackground.ignoresSafeArea())
            .navigationTitle("Lesen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
        .task(id: languageCode) { await load() }
        .onDisappear { tts.stop() }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.space.md) {
                header
                ForEach(passages) { passage in
                    passageCard(passage)
                }
            }
            .padding(.horizontal, DS.space.md)
            .padding(.top, DS.space.sm)
            .padding(.bottom, DS.space.xxl)
            .frame(maxWidth: DS.mainContentWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Fast alles bekannt")
                .font(.title3.weight(.bold))
                .foregroundStyle(DS.textPrimary)
            Text("Diese Sätze bestehen aus Wörtern, die bei dir sitzen — höchstens eines ist neu. Erst selbst lesen, dann die Übersetzung aufdecken.")
                .font(.subheadline)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func passageCard(_ passage: ReadingPassage) -> some View {
        VStack(alignment: .leading, spacing: DS.space.sm) {
            Text(passage.sentence)
                .font(LearningTypography.display(.title3, weight: .semibold, languageCode: languageCode))
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: pack.isRTL ? .trailing : .leading)

            if let new = passage.unknownWords.first {
                Label("Neu: \(new)", systemImage: "sparkle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DS.accent)
            }

            if revealed.contains(passage.id) {
                if let translation = passage.translation {
                    Text(translation)
                        .font(.subheadline)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let reading = passage.transliteration, reading != passage.sentence {
                    Text(reading)
                        .font(.footnote)
                        .foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: DS.space.md) {
                Button {
                    tts.speak(passage.sentence, language: pack.ttsLocale, times: 1)
                } label: {
                    Label("Hören", systemImage: "speaker.wave.2.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.accent)
                .accessibilityLabel("Satz vorlesen")

                Button {
                    if revealed.contains(passage.id) {
                        revealed.remove(passage.id)
                    } else {
                        revealed.insert(passage.id)
                    }
                } label: {
                    Label(
                        revealed.contains(passage.id) ? "Verbergen" : "Übersetzung",
                        systemImage: revealed.contains(passage.id) ? "eye.slash" : "eye"
                    )
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.textSecondary)

                Spacer()

                Text("\(passage.knownWordCount)/\(passage.totalWordCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(DS.textTertiary)
                    .accessibilityLabel("\(passage.knownWordCount) von \(passage.totalWordCount) Wörtern bekannt")
            }
        }
        .dsCard(elevation: 1, padding: DS.space.md)
    }

    @MainActor
    private func load() async {
        // Off the first frame: this walks every phrase's cards.
        await Task.yield()
        passages = ReadingSelector.passages(phrases: phrases, languageCode: languageCode)
        isLoading = false
    }
}
