import SwiftUI
import SwiftData
import Charts

/// User-facing progress screen. Shows what the SRS schedule already knows
/// but isn't surfaced anywhere in the practice loop: streak, today's count,
/// total reviews, breakdown of cards by FSRS state, per-topic progress.
///
/// Purpose: give the user a felt sense of forward motion so the "I keep
/// seeing the same phrases" feeling has a counter-narrative.
struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var cards: [StudyCard]
    @Query(sort: \Review.timestamp, order: .reverse) private var reviews: [Review]
    @Query(sort: \Topic.name) private var topics: [Topic]
    @Query(sort: \Language.code) private var languages: [Language]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.space.lg) {
                    heroSection
                    todaySection
                    weeklyChart
                    if languages.count > 1 {
                        perLanguage
                    }
                    libraryBreakdown
                    topicProgress
                }
                .padding(.horizontal, DS.space.md)
                .padding(.bottom, DS.space.xl)
            }
            .background(DS.surface0)
            .navigationTitle("Fortschritt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var heroSection: some View {
        HStack(spacing: DS.space.md) {
            heroTile(
                value: "\(currentStreak)",
                label: streakLabel,
                icon: "flame.fill",
                color: .orange
            )
            heroTile(
                value: "\(reviewedToday)",
                label: "heute",
                icon: "checkmark.circle.fill",
                color: DS.gradePerfect
            )
            heroTile(
                value: "\(dueNow)",
                label: "fällig",
                icon: "clock.fill",
                color: DS.accent
            )
        }
    }

    private func heroTile(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(DS.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.space.md)
        .background(DS.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: DS.space.sm) {
            sectionHeader("Heute")
            VStack(spacing: 8) {
                statRow("Reviews", "\(reviewedToday)")
                statRow("Neue Karten", "\(newToday)")
                statRow("Genauigkeit", accuracyTodayString)
            }
            .padding(DS.space.md)
            .background(DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
        }
    }

    private var libraryBreakdown: some View {
        VStack(alignment: .leading, spacing: DS.space.sm) {
            sectionHeader("Deine Bibliothek")
            VStack(spacing: DS.space.sm) {
                stateBar(label: "Neu", count: newCount, total: cards.count, color: DS.textTertiary)
                stateBar(label: "Im Lernen", count: learningCount, total: cards.count, color: DS.gradeMinor)
                stateBar(label: "In Wiederholung", count: reviewCount, total: cards.count, color: DS.accent)
                stateBar(label: "Nachlernen", count: relearningCount, total: cards.count, color: DS.gradeWrong)
            }
            .padding(DS.space.md)
            .background(DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))

            HStack {
                Text("Gesamt: \(cards.count) Karten")
                Spacer()
                Text("\(reviews.count) Reviews insgesamt")
            }
            .font(.caption)
            .foregroundStyle(DS.textTertiary)
        }
    }

    private var topicProgress: some View {
        VStack(alignment: .leading, spacing: DS.space.sm) {
            sectionHeader("Themen")
            VStack(spacing: 6) {
                ForEach(topicsWithCards, id: \.id) { topic in
                    topicRow(topic: topic)
                }
                if topicsWithCards.isEmpty {
                    Text("Noch keine Themen mit Karten.")
                        .font(.subheadline)
                        .foregroundStyle(DS.textSecondary)
                }
            }
            .padding(DS.space.md)
            .background(DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
        }
    }

    // MARK: - 7-day chart

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: DS.space.sm) {
            sectionHeader("Letzte 7 Tage")
            Chart(weeklyData) { day in
                BarMark(
                    x: .value("Tag", day.date, unit: .day),
                    y: .value("Karten", day.count)
                )
                .foregroundStyle(day.count > 0 ? DS.accent : DS.surface2)
                .cornerRadius(4)
            }
            .frame(height: 140)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel().font(.caption2)
                }
            }
            .padding(DS.space.md)
            .background(DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
        }
    }

    private var perLanguage: some View {
        VStack(alignment: .leading, spacing: DS.space.sm) {
            sectionHeader("Pro Sprache")
            VStack(spacing: 8) {
                ForEach(languages, id: \.code) { lang in
                    let count = reviews.filter { $0.card?.phrase?.language?.code == lang.code }.count
                    if count > 0 {
                        statRow(lang.germanLabel, "\(count)")
                    }
                }
            }
            .padding(DS.space.md)
            .background(DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
        }
    }

    private var weeklyData: [DayStat] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<7).reversed().map { offset in
            let date = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let next = cal.date(byAdding: .day, value: 1, to: date) ?? date
            let count = reviews.filter { $0.timestamp >= date && $0.timestamp < next }.count
            return DayStat(date: date, count: count)
        }
    }

    // MARK: - Pieces

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(DS.textSecondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 4)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(DS.textPrimary)
            Spacer()
            Text(value).foregroundStyle(DS.textSecondary).monospacedDigit()
        }
        .font(.subheadline)
    }

    private func stateBar(label: String, count: Int, total: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text("\(count)").font(.subheadline.monospacedDigit()).foregroundStyle(DS.textSecondary)
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

    private func topicRow(topic: Topic) -> some View {
        let total = topic.phrases.count * CardDirection.allCases.count
        let learnedCount = cardsForTopic(topic).filter { $0.state == .review }.count
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                if topic.isActive {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(DS.accent)
                }
                Text(topic.name)
                    .font(.subheadline.weight(topic.isActive ? .semibold : .regular))
                Spacer()
                Text("\(learnedCount)/\(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DS.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.surface2)
                    Capsule()
                        .fill(DS.accent)
                        .frame(width: total > 0 ? geo.size.width * CGFloat(learnedCount) / CGFloat(total) : 0)
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Derived data

    private var newCount: Int { cards.filter { $0.state == .new }.count }
    private var learningCount: Int { cards.filter { $0.state == .learning }.count }
    private var reviewCount: Int { cards.filter { $0.state == .review }.count }
    private var relearningCount: Int { cards.filter { $0.state == .relearning }.count }
    private var dueNow: Int { cards.filter { $0.dueDate <= .now && $0.state != .new }.count }

    private var startOfToday: Date { Calendar.current.startOfDay(for: .now) }
    private var reviewsToday: [Review] { reviews.filter { $0.timestamp >= startOfToday } }
    private var reviewedToday: Int { reviewsToday.count }
    private var newToday: Int { reviewsToday.filter(\.wasNew).count }

    private var accuracyTodayString: String {
        guard !reviewsToday.isEmpty else { return "—" }
        let correct = reviewsToday.filter { $0.rating >= 3 }.count
        let pct = Int(Double(correct) / Double(reviewsToday.count) * 100)
        return "\(pct) %  (\(correct)/\(reviewsToday.count))"
    }

    private var currentStreak: Int {
        // Walk backwards from today: each consecutive calendar day with at
        // least one review counts. Stop at the first day with no review.
        // Today itself counts only if there's been a review today.
        let cal = Calendar.current
        var day = cal.startOfDay(for: .now)
        var streak = 0
        while true {
            let next = cal.date(byAdding: .day, value: 1, to: day) ?? day
            let count = reviews.contains { $0.timestamp >= day && $0.timestamp < next }
            if !count { break }
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return streak
    }

    private var streakLabel: String {
        switch currentStreak {
        case 0: return "noch keine Serie"
        case 1: return "Tag in Folge"
        default: return "Tage in Folge"
        }
    }

    private var topicsWithCards: [Topic] {
        topics
            .filter { !$0.phrases.isEmpty }
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive { return lhs.isActive && !rhs.isActive }
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }
    }

    private func cardsForTopic(_ topic: Topic) -> [StudyCard] {
        let phraseIDs = Set(topic.phrases.map(\.persistentModelID))
        return cards.filter {
            guard let phrase = $0.phrase else { return false }
            return phraseIDs.contains(phrase.persistentModelID)
        }
    }
}

private struct DayStat: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
}
