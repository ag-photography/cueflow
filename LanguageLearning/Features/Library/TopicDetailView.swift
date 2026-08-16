import SwiftUI
import SwiftData

/// Per-topic detail (build 22). Bridges Library and progress: prominent
/// activation toggle, mastery summary (FSRS-state breakdown + progress bar),
/// and the topic's phrases. Each phrase has one shared learning schedule;
/// "gemeistert" currently means that schedule is in FSRS `.review` state.
struct TopicDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var topic: Topic

    @State private var phraseInEditor: Phrase?
    @State private var showingEditor = false

    private var cards: [StudyCard] {
        topic.phrases.flatMap(\.cards)
    }

    private var total: Int { cards.count }
    private var newCount: Int { cards.filter { $0.state == .new }.count }
    private var learningCount: Int { cards.filter { $0.state == .learning }.count }
    private var masteredCount: Int { cards.filter { $0.state == .review }.count }
    private var relearningCount: Int { cards.filter { $0.state == .relearning }.count }
    private var dueNow: Int { cards.filter { $0.dueDate <= .now && $0.state != .new }.count }
    private var masteryFraction: Double {
        total > 0 ? Double(masteredCount) / Double(total) : 0
    }

    private var sortedPhrases: [Phrase] {
        topic.phrases.sorted { $0.sourceText.localizedCompare($1.sourceText) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.space.lg) {
                activationCard
                if total > 0 {
                    masteryCard
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
    }

    // MARK: - Activation

    private var activationCard: some View {
        VStack(spacing: DS.space.sm) {
            Toggle(isOn: Binding(
                get: { topic.isActive },
                set: { topic.isActive = $0; try? context.save() }
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
        }
        .padding(DS.space.md)
        .background(DS.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
    }

    // MARK: - Mastery

    private var masteryCard: some View {
        VStack(alignment: .leading, spacing: DS.space.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int((masteryFraction * 100).rounded()))%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.accent)
                    .monospacedDigit()
                Text("gemeistert")
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
                        .frame(width: geo.size.width * masteryFraction)
                }
            }
            .frame(height: 8)

            VStack(spacing: DS.space.sm) {
                stateBar(label: "Neu", count: newCount, color: DS.textTertiary)
                stateBar(label: "Im Lernen", count: learningCount, color: DS.gradeMinor)
                stateBar(label: "Gemeistert", count: masteredCount, color: DS.accent)
                if relearningCount > 0 {
                    stateBar(label: "Nachlernen", count: relearningCount, color: DS.gradeWrong)
                }
            }
            Text("\(masteredCount) von \(total) Karten · \(topic.phrases.count) Phrasen")
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
}
