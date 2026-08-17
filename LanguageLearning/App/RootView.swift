import SwiftUI
import SwiftData

/// Root gate: onboarding first, then the native primary navigation.
struct RootView: View {
    @Query private var settings: [AppSettings]

    private var hasOnboarded: Bool {
        settings.first?.hasCompletedOnboarding ?? false
    }

    var body: some View {
        Group {
            if hasOnboarded {
                MainTabView()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: hasOnboarded)
    }
}

private struct MainTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Heute", systemImage: "sun.max.fill") }

            LibraryView()
                .tabItem { Label("Bibliothek", systemImage: "books.vertical.fill") }

            ProfileView(showsDismissButton: false)
                .tabItem { Label("Fortschritt", systemImage: "chart.bar.fill") }
        }
    }
}

/// The calm launch destination: one recommended action, a visible Sprint, and
/// enough context to understand why today's session is useful.
private struct TodayView: View {
    @Query private var cards: [StudyCard]
    @Query private var reviews: [Review]
    @Query private var settings: [AppSettings]
    @Query(sort: \Topic.name) private var topics: [Topic]

    @AppStorage("sprintBest") private var sprintBest = 0
    @State private var showingPractice = false
    @State private var showingSprint = false
    @State private var showingSettings = false
    @State private var sessionTarget = 10

    private var activeLanguageCode: String { settings.first?.activeLanguageCode ?? "ru" }
    private var activeCards: [StudyCard] {
        cards.filter { $0.phrase?.language?.code == activeLanguageCode }
    }
    private var dueCount: Int {
        activeCards.filter { $0.state != .new && $0.dueDate <= .now }.count
    }
    private var availableNewCount: Int {
        activeCards.filter {
            $0.state == .new && (($0.phrase?.topics.contains(where: { $0.isActive }) ?? false)
                || ($0.phrase?.isPriorityActive ?? false))
        }.count
    }
    private var plannedNewCount: Int {
        min(availableNewCount, settings.first?.dailyNewLimit ?? 10)
    }
    private var estimatedMinutes: Int {
        max(2, Int(ceil(Double(max(1, min(sessionTarget, dueCount + plannedNewCount))) * 0.55)))
    }
    private var reviewsToday: Int {
        reviews.filter { Calendar.current.isDateInToday($0.timestamp) }.count
    }
    private var currentMission: Topic? {
        topics.first { $0.isActive && $0.language?.code == activeLanguageCode }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space.lg) {
                    greeting
                    recommendedSession
                    sprintCard
                    missionCard
                }
                .padding(DS.space.md)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(DS.surface0.ignoresSafeArea())
            .navigationTitle("Heute")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Einstellungen")
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .fullScreenCover(isPresented: $showingPractice) {
                PracticeView(sessionTarget: sessionTarget, isFocusedSession: true)
            }
            .fullScreenCover(isPresented: $showingSprint) { SprintView() }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greetingText)
                .font(.system(.largeTitle, design: .serif, weight: .bold))
                .foregroundStyle(DS.textPrimary)
            Text(reviewsToday == 0 ? "Bereit, etwas spontan abzurufen?" : "Heute schon \(reviewsToday) Antworten produziert.")
                .font(.subheadline)
                .foregroundStyle(DS.textSecondary)
        }
    }

    private var recommendedSession: some View {
        VStack(alignment: .leading, spacing: DS.space.md) {
            HStack {
                Label("Empfohlen", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.accent)
                Spacer()
                Menu {
                    sessionChoice("Schnellrunde", target: 5)
                    sessionChoice("Tägliche Einheit", target: 10)
                    sessionChoice("Intensiv üben", target: 20)
                } label: {
                    Label(sessionLabel, systemImage: "chevron.down")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DS.textSecondary)
                }
            }

            Text("Weiterlernen")
                .font(.title2.weight(.bold))
                .foregroundStyle(DS.textPrimary)
            Text("\(dueCount) Wiederholungen · \(plannedNewCount) neue Ausdrücke")
                .font(.subheadline)
                .foregroundStyle(DS.textSecondary)
            Label("Etwa \(estimatedMinutes) Minuten", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(DS.textTertiary)

            Button {
                showingPractice = true
            } label: {
                Label("Einheit starten", systemImage: "arrow.right.circle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(DS.accent)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
            }
            .buttonStyle(.plain)
        }
        .padding(DS.space.lg)
        .background(DS.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius.lg))
        .modifier(DS.Elevation(level: 2))
    }

    private var sprintCard: some View {
        Button { showingSprint = true } label: {
            HStack(spacing: DS.space.md) {
                Image(systemName: "bolt.fill")
                    .font(.title2)
                    .foregroundStyle(DS.accent)
                    .frame(width: 48, height: 48)
                    .background(DS.accentSoft)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("60-Sekunden-Sprint")
                        .font(.headline)
                        .foregroundStyle(DS.textPrimary)
                    Text(sprintBest > 0 ? "Bestleistung: \(sprintBest)" : "Schnell sprechen, ohne SRS-Druck")
                        .font(.caption)
                        .foregroundStyle(DS.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(DS.space.md)
            .background(DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var missionCard: some View {
        if let mission = currentMission {
            VStack(alignment: .leading, spacing: DS.space.sm) {
                Text("AKTUELLE MISSION")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(DS.textTertiary)
                Text(mission.name)
                    .font(.headline)
                    .foregroundStyle(DS.textPrimary)
                Text("\(mission.phrases.count) nützliche Ausdrücke · produktiv üben")
                    .font(.caption)
                    .foregroundStyle(DS.textSecondary)
            }
            .padding(DS.space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius.md))
        }
    }

    private func sessionChoice(_ label: String, target: Int) -> some View {
        Button { sessionTarget = target } label: {
            if sessionTarget == target {
                Label(label, systemImage: "checkmark")
            } else {
                Text(label)
            }
        }
    }

    private var sessionLabel: String {
        switch sessionTarget {
        case 5: return "Schnellrunde"
        case 20: return "Intensiv"
        default: return "Tägliche Einheit"
        }
    }

    private var greetingText: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Guten Morgen"
        case 12..<18: return "Guten Tag"
        default: return "Guten Abend"
        }
    }
}
