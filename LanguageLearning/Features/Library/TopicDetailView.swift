import SwiftUI
import SwiftData

/// Per-topic detail (build 22). Bridges Library and progress: prominent
/// activation toggle, learning summary (FSRS-state breakdown + progress bar),
/// and the topic's phrases. Each phrase has one shared learning schedule.
struct TopicDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var topic: Topic

    @State private var phraseInEditor: Phrase?
    @State private var showingEditor = false
    @State private var showingPractice = false
    @State private var saveErrorMessage: String?

    private var cards: [StudyCard] {
        (topic.phrases ?? []).flatMap { $0.cards ?? [] }
    }

    private var total: Int { cards.count }
    private var newCount: Int { cards.filter { $0.state == .new }.count }
    private var learningCount: Int { cards.filter { $0.state == .learning }.count }
    private var reviewingCount: Int { cards.filter { $0.state == .review }.count }
    private var practisedCount: Int { cards.filter { $0.state.isIntroduced }.count }
    private var relearningCount: Int { cards.filter { $0.state == .relearning }.count }
    private var dueNow: Int { cards.filter { $0.dueDate <= .now && $0.state != .new }.count }
    private var practisedFraction: Double {
        total > 0 ? Double(practisedCount) / Double(total) : 0
    }

    private var sortedPhrases: [Phrase] {
        (topic.phrases ?? []).sorted { $0.sourceText.localizedCompare($1.sourceText) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.space.lg) {
                activationCard
                if total > 0 {
                    learningProgressCard
                }
                phrasesCard
            }
            .padding(.horizontal, DS.space.md)
            .padding(.vertical, DS.space.md)
        }
        .background(DS.surface0)
        .navigationTitle(topic.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Thema bearbeiten")
            }
        }
        .sheet(item: $phraseInEditor) { PhraseEditorView(phrase: $0) }
        .sheet(isPresented: $showingEditor) { TopicEditorView(topic: topic) }
        .fullScreenCover(isPresented: $showingPractice) {
            PracticeView(
                sessionTarget: min(10, max(1, total)),
                isFocusedSession: true,
                scope: .topic(id: topic.persistentModelID)
            )
        }
        .alert("Thema konnte nicht aktualisiert werden", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "Bitte versuche es erneut.")
        }
    }

    // MARK: - Activation

    private var activationCard: some View {
        VStack(spacing: DS.space.sm) {
            Toggle(isOn: Binding(
                get: { topic.isActive },
                set: { setTopicActive($0) }
            )) {
                HStack(spacing: DS.space.sm) {
                    Image(systemName: topic.isActive ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(topic.isActive ? DS.accent : DS.textTertiary)
                    Text("Aktiv")
                        .font(.headline)
                        .foregroundStyle(DS.textPrimary)
                }
            }
            .tint(DS.accent)
            Text("Aktive Themen liefern neue Karten. Wiederholungen kommen weiter aus allen Themen.")
                .font(.caption)
                .foregroundStyle(DS.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if total > 0 {
                Button {
                    if !topic.isActive { setTopicActive(true) }
                    showingPractice = true
                } label: {
                    Label("Dieses Thema jetzt üben", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.accent)
                .accessibilityIdentifier("topic-practice-start")
            }
        }
        .padding(DS.space.md)
        .background(DS.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
    }

    private func setTopicActive(_ isActive: Bool) {
        topic.isActive = isActive
        do {
            try context.save()
            saveErrorMessage = nil
        } catch {
            context.rollback()
            saveErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Learning progress

    private var learningProgressCard: some View {
        VStack(alignment: .leading, spacing: DS.space.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int((practisedFraction * 100).rounded()))%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.accent)
                    .monospacedDigit()
                Text("schon geübt")
                    .font(.subheadline)
                    .foregroundStyle(DS.textSecondary)
                Spacer()
                if dueNow > 0 {
                    Label("\(dueNow) fällig", systemImage: "clock.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DS.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(DS.accentSoft)
                        .clipShape(Capsule())
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.surface2)
                    Capsule()
                        .fill(DS.accent)
                        .frame(width: geo.size.width * practisedFraction)
                }
            }
            .frame(height: 8)

            VStack(spacing: DS.space.sm) {
                stateBar(label: "Neu", count: newCount, color: DS.textTertiary)
                stateBar(label: "Im Lernen", count: learningCount, color: DS.gradeMinor)
                stateBar(label: "In Wiederholung", count: reviewingCount, color: DS.accent)
                if relearningCount > 0 {
                    stateBar(label: "Nachlernen", count: relearningCount, color: DS.gradeWrong)
                }
            }
            Text("\(practisedCount) von \(total) Phrasen mindestens einmal geübt")
                .font(.caption)
                .foregroundStyle(DS.textTertiary)
        }
        .padding(DS.space.md)
        .background(DS.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
    }

    private func stateBar(label: String, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline).foregroundStyle(DS.textPrimary)
                Spacer()
                Text("\(count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(DS.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.surface2)
                    Capsule()
                        .fill(color)
                        .frame(width: total > 0 ? geo.size.width * CGFloat(count) / CGFloat(total) : 0)
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Phrases

    private var phrasesCard: some View {
        VStack(alignment: .leading, spacing: DS.space.sm) {
            Text("Phrasen")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
            if sortedPhrases.isEmpty {
                Text("Noch keine Phrasen in diesem Thema.")
                    .font(.subheadline)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.vertical, DS.space.sm)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sortedPhrases.enumerated()), id: \.element.persistentModelID) { i, phrase in
                        Button {
                            phraseInEditor = phrase
                        } label: {
                            phraseRow(phrase)
                        }
                        .buttonStyle(.plain)
                        if i < sortedPhrases.count - 1 {
                            Divider().overlay(DS.surface2)
                        }
                    }
                }
            }
        }
        .padding(DS.space.md)
        .background(DS.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
    }

    private func phraseRow(_ phrase: Phrase) -> some View {
        HStack(spacing: DS.space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(phrase.sourceText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DS.textPrimary)
                Text(phrase.targetText)
                    .font(.subheadline)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if phrase.level != .unspecified { metadataChip(phrase.level.label) }
                    if phrase.phraseRegister != .neutral { metadataChip(phrase.phraseRegister.label) }
                    if !phrase.dialect.isEmpty { metadataChip(phrase.dialect) }
                    if phrase.qualityStatus == .nativeVerified {
                        Label("Geprüft", systemImage: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(DS.accent)
                    }
                }
            }
            Spacer(minLength: 0)
            if phrase.isPriorityActive {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(DS.gradeMinor)
                    .accessibilityLabel("Priorität")
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DS.textTertiary)
        }
        .padding(.vertical, DS.space.sm)
        .contentShape(Rectangle())
    }

    private func metadataChip(_ label: String) -> some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(DS.surface2)
            .clipShape(Capsule())
    }
}
