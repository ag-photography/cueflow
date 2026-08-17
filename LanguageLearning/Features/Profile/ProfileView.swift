import SwiftUI
import SwiftData
import Charts

/// User-facing progress screen. Surfaces what the SRS schedule knows but the
/// practice loop doesn't show: streak, today's count, learning mix, weekly
/// rhythm, per-topic progress. Redesigned (build 28) around a streak hero and a
/// progress ring so it reads as a felt "dashboard", not a stats dump.
struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var cards: [StudyCard]
    @Query(sort: \Review.timestamp, order: .reverse) private var reviews: [Review]
    @Query(sort: \Topic.name) private var topics: [Topic]
    @Query(sort: \Language.code) private var languages: [Language]

    // Speaking-volume scoreboard — shared with Sprint via UserDefaults.
    @AppStorage("sprintBest") private var sprintBest: Int = 0
    @AppStorage("spokenWordsCount") private var spokenWordsCountStored: Int = 0
    @AppStorage("spokenWordsDayIndex") private var spokenWordsDayIndex: Int = 0

    var showsDismissButton = true

    private let flame = LinearGradient(
        colors: [Color(red: 0.97, green: 0.45, blue: 0.17), Color(red: 0.98, green: 0.66, blue: 0.22)],
        startPoint: .top, endPoint: .bottom
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.space.lg) {
                    speakingSection
                    miniStatsRow
                    topicProgress
                    weeklyChart
                    if languages.count > 1 {
                        perLanguage
                    }
                    learningProgressSection
                    streakHero
                }
                .padding(.horizontal, DS.space.md)
                .padding(.top, DS.space.sm)
                .padding(.bottom, DS.space.xl)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(
                LinearGradient(colors: [DS.surface0, DS.surface2.opacity(0.5)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
            .navigationTitle("Fortschritt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDismissButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fertig") { dismiss() }
                    }
                }
            }
        }
    }

    // MARK: - Streak hero

    private var streakHero: some View {
        VStack(spacing: DS.space.md) {
            HStack(spacing: DS.space.md) {
                ZStack {
                    Circle().fill(flame)
                        .shadow(color: Color(red: 0.97, green: 0.45, blue: 0.17).opacity(0.4), radius: 10, y: 4)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 68, height: 68)

                VStack(alignment: .leading, spacing: 0) {
                    Text("\(currentStreak)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.textPrimary)
                        .monospacedDigit()
                    Text(streakLabel)
                        .font(.subheadline)
                        .foregroundStyle(DS.textSecondary)
                }
                Spacer()
            }

            if let next = nextMilestone(after: currentStreak), currentStreak > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Nächstes Ziel")
                        Spacer()
                        Text("noch \(next - currentStreak) \(next - currentStreak == 1 ? "Tag" : "Tage") bis \(next)")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DS.textSecondary)
                    ProgressCapsule(fraction: Double(currentStreak) / Double(next),
                                    fill: AnyShapeStyle(flame))
                        .frame(height: 7)
                }
            } else if currentStreak == 0 {
                Text("Übe heute eine Runde, um die Serie zu starten.")
                    .font(.caption)
                    .foregroundStyle(DS.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DS.space.lg)
        .background(DS.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.lg))
        .modifier(DS.Elevation(level: 2))
    }

    private var miniStatsRow: some View {
        HStack(spacing: DS.space.md) {
            miniStat(value: phrasesProducedUnaided, label: "selbst abgerufen",
                     icon: "bubble.left.and.bubble.right.fill", color: DS.gradePerfect)
            miniStat(value: dueNow, label: "jetzt fällig",
                     icon: "clock.fill", color: DS.accent)
            miniStat(value: reviewedToday, label: "Antworten heute",
                     icon: "checkmark.circle.fill", color: DS.textSecondary)
        }
    }

    /// Distinct prompts recalled productively with a strong grade. Recognition
    /// flips and multiple-choice introductions do not count as unaided output.
    private var phrasesProducedUnaided: Int {
        Set(reviews.compactMap { review -> PersistentIdentifier? in
            guard review.gradeTier >= 3,
                  review.modeRaw == CardDirection.speakDeToRu.rawValue ||
                    review.modeRaw == CardDirection.typeDeToRu.rawValue
            else { return nil }
            return review.card?.phrase?.persistentModelID
        }).count
    }

    private func miniStat(value: Int, label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.footnote).foregroundStyle(color)
            Text("\(value)")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(DS.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(DS.textSecondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.space.md)
        .background(DS.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
    }

    // MARK: - Learning progress

    private var learningProgressSection: some View {
        VStack(alignment: .leading, spacing: DS.space.sm) {
            sectionHeader("Lernstand")
            HStack(spacing: DS.space.lg) {
                LearningProgressRing(
                    reviewing: reviewCount, learning: learningCount,
                    relearning: relearningCount, new: newCount
                )
                .frame(width: 124, height: 124)

                VStack(alignment: .leading, spacing: DS.space.sm) {
                    legendRow(color: DS.accent, label: "In Wiederholung", count: reviewCount)
                    legendRow(color: DS.gradeMinor, label: "Im Lernen", count: learningCount)
                    legendRow(color: DS.gradeWrong, label: "Nachlernen", count: relearningCount)
                    legendRow(color: DS.textTertiary.opacity(0.55), label: "Neu", count: newCount)
                }
                Spacer(minLength: 0)
            }
            .padding(DS.space.md)
            .frame(maxWidth: .infinity)
            .background(DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
        }
    }

    private func legendRow(color: Color, label: String, count: Int) -> some View {
        HStack(spacing: DS.space.sm) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label).font(.subheadline).foregroundStyle(DS.textPrimary)
            Spacer()
            Text("\(count)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(DS.textSecondary)
        }
    }

    // MARK: - 7-day chart

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: DS.space.sm) {
            sectionHeader("Letzte 7 Tage")
            Chart(weeklyData) { day in
                BarMark(
                    x: .value("Tag", day.date, unit: .day),
                    y: .value("Karten", day.count),
                    width: .fixed(20)
                )
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(
                    day.count > 0
                    ? LinearGradient(colors: [DS.accent, DS.accent.opacity(0.55)],
                                     startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [DS.surface2, DS.surface2], startPoint: .top, endPoint: .bottom)
                )
            }
            .frame(height: 150)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow)).font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(DS.textTertiary.opacity(0.2))
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

    private var topicProgress: some View {
        VStack(alignment: .leading, spacing: DS.space.sm) {
            sectionHeader("Themen")
            VStack(spacing: DS.space.md) {
                ForEach(topicsWithCards.prefix(8), id: \.id) { topic in
                    topicRow(topic: topic)
                }
                if topicsWithCards.isEmpty {
                    Text("Noch keine Themen mit Karten.")
                        .font(.subheadline)
                        .foregroundStyle(DS.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func topicRow(topic: Topic) -> some View {
        let total = topic.phrases.count
        let practisedCount = cardsForTopic(topic).filter { $0.state.isIntroduced }.count
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                if topic.isActive {
                    Circle().fill(DS.accent).frame(width: 6, height: 6)
                }
                Text(topic.name)
                    .font(.subheadline.weight(topic.isActive ? .semibold : .regular))
                    .foregroundStyle(DS.textPrimary)
                Spacer()
                Text("\(practisedCount)/\(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DS.textSecondary)
            }
            ProgressCapsule(fraction: total > 0 ? Double(practisedCount) / Double(total) : 0,
                            fill: AnyShapeStyle(DS.accent))
                .frame(height: 5)
        }
    }

    // MARK: - Speaking (the "speak a lot" scoreboard)

    private var speakingSection: some View {
        VStack(alignment: .leading, spacing: DS.space.sm) {
            sectionHeader("Sprechen")
            VStack(alignment: .leading, spacing: DS.space.md) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.space.sm) {
                        Image(systemName: "waveform")
                            .font(.title3)
                            .foregroundStyle(DS.accent)
                        Text("\(spokenWordsTodayTotal)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(DS.textPrimary)
                            .contentTransition(.numericText())
                        Text("Wörter")
                            .font(.headline)
                            .foregroundStyle(DS.textSecondary)
                        Spacer()
                    }
                    Text("heute laut gesprochen")
                        .font(.caption)
                        .foregroundStyle(DS.textSecondary)
                }
                Chart(spokenWeekly) { day in
                    BarMark(
                        x: .value("Tag", day.date, unit: .day),
                        y: .value("Wörter", day.count),
                        width: .fixed(20)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(
                        day.count > 0
                        ? LinearGradient(colors: [DS.gradePerfect, DS.gradePerfect.opacity(0.55)],
                                         startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [DS.surface2, DS.surface2], startPoint: .top, endPoint: .bottom)
                    )
                }
                .frame(height: 110)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow)).font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(DS.textTertiary.opacity(0.2))
                        AxisValueLabel().font(.caption2)
                    }
                }
                Divider().overlay(DS.surface2)
                HStack(spacing: DS.space.md) {
                    Label(sprintBest > 0 ? "Sprint-Best: \(sprintBest)" : "Sprint: noch keiner",
                          systemImage: "bolt.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DS.gradeHesitant)
                    Spacer()
                    if let f = fluencyLabel {
                        Label(f, systemImage: "gauge.with.dots.needle.67percent")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DS.textSecondary)
                            .accessibilityLabel("Sprechtempo \(f)")
                    }
                }
            }
            .padding(DS.space.md)
            .background(DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
        }
    }

    // MARK: - Speaking scoreboard data

    private var todayIndex: Int {
        Int(Calendar.current.startOfDay(for: .now).timeIntervalSinceReferenceDate / 86_400)
    }
    private var sprintWordsToday: Int {
        spokenWordsDayIndex == todayIndex ? spokenWordsCountStored : 0
    }

    /// Reviews where the user actually *spoke* — speak mode, and graded (tier ≥ 1).
    /// Tier 0 is the multiple-choice recognition step shown for new cards in
    /// "Üben", which isn't spoken output, so it's excluded.
    private var spokenReviews: [Review] {
        reviews.filter { $0.modeRaw == CardDirection.speakDeToRu.rawValue && $0.gradeTier >= 1 }
    }
    private func wordCount(_ s: String) -> Int {
        s.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
    }
    private var spokenWordsTodayPractice: Int {
        spokenReviews.filter { $0.timestamp >= startOfToday }.reduce(0) { $0 + wordCount($1.userAnswer) }
    }
    private var spokenWordsTodayTotal: Int { spokenWordsTodayPractice + sprintWordsToday }

    private var spokenWeekly: [DayStat] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<7).reversed().map { offset in
            let date = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let next = cal.date(byAdding: .day, value: 1, to: date) ?? date
            let w = spokenReviews
                .filter { $0.timestamp >= date && $0.timestamp < next }
                .reduce(0) { $0 + wordCount($1.userAnswer) }
            return DayStat(date: date, count: w)
        }
    }

    private func avgSec(_ rs: [Review]) -> Double? {
        let timed = rs.filter { $0.responseTimeMs > 0 }
        guard !timed.isEmpty else { return nil }
        return Double(timed.reduce(0) { $0 + $1.responseTimeMs }) / Double(timed.count) / 1000.0
    }
    /// Average spoken response time this week, with a ↓/↑ arrow vs. last week so
    /// the user can *feel* fluency improving — the intrinsic reward.
    private var fluencyLabel: String? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let weekAgo = cal.date(byAdding: .day, value: -6, to: today) ?? today
        let twoWeeksAgo = cal.date(byAdding: .day, value: -13, to: today) ?? today
        guard let thisWeek = avgSec(spokenReviews.filter { $0.timestamp >= weekAgo }) else { return nil }
        let lastWeek = avgSec(spokenReviews.filter { $0.timestamp >= twoWeeksAgo && $0.timestamp < weekAgo })
        if let prev = lastWeek, abs(prev - thisWeek) >= 0.1 {
            let arrow = thisWeek < prev ? "↓" : "↑"
            return String(format: "%@ %.1f s", arrow, thisWeek)
        }
        return String(format: "%.1f s", thisWeek)
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

    private func nextMilestone(after streak: Int) -> Int? {
        [3, 7, 14, 30, 100, 365].first { $0 > streak }
    }

    private var currentStreak: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: .now)
        var streak = 0
        while true {
            let next = cal.date(byAdding: .day, value: 1, to: day) ?? day
            let hit = reviews.contains { $0.timestamp >= day && $0.timestamp < next }
            if !hit { break }
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

// MARK: - Learning progress ring

/// Donut of the four FSRS states with the honestly named introduced percentage.
private struct LearningProgressRing: View {
    let reviewing: Int
    let learning: Int
    let relearning: Int
    let new: Int

    private var total: Int { max(1, reviewing + learning + relearning + new) }
    private var introducedPct: Int {
        Int((Double(reviewing + learning + relearning) / Double(total) * 100).rounded())
    }

    private var segments: [(start: Double, end: Double, color: Color)] {
        let ordered: [(Int, Color)] = [
            (reviewing, DS.accent),
            (learning, DS.gradeMinor),
            (relearning, DS.gradeWrong),
            (new, DS.textTertiary.opacity(0.5)),
        ]
        var acc = 0.0
        return ordered.compactMap { count, color in
            guard count > 0 else { return nil }
            let start = acc
            acc += Double(count) / Double(total)
            return (start, acc, color)
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(DS.surface2, lineWidth: 16)
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                Circle()
                    .trim(from: seg.start, to: seg.end)
                    .stroke(seg.color, style: StrokeStyle(lineWidth: 16, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text("\(introducedPct)%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.accent)
                    .monospacedDigit()
                Text("schon geübt")
                    .font(.caption2)
                    .foregroundStyle(DS.textSecondary)
            }
        }
    }
}

// MARK: - Progress capsule

/// Rounded progress track used by the streak hero and topic rows.
private struct ProgressCapsule: View {
    let fraction: Double
    let fill: AnyShapeStyle

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(DS.surface2)
                Capsule()
                    .fill(fill)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
    }
}

private struct DayStat: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
}
