import SwiftUI
import SwiftData

struct EpisodeCollectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [AppSettings]
    @State private var selection: LearningEpisode?
    private var language: String { settings.first?.activeLanguageCode ?? "ru" }
    private var experience: LearningExperience? { try? settings.first?.readExperience() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space.md) {
                    Text("Eine kleine Welt. Deine Geschichten.").font(.system(.title2, design: .rounded, weight: .bold))
                    Text("Jede abgeschlossene Szene wird zu einer Postkarte. Alle Szenen sind frei wählbar – auch mit Hilfe sammelst du Erinnerungen.")
                        .font(.subheadline).foregroundStyle(DS.textSecondary)
                    if let data = experience {
                        let passport = StoryPassport(language: language, experience: data)
                        VStack(alignment: .leading, spacing: DS.space.sm) {
                            Text("\(passport.collectedCount) von \(passport.episodes.count) Postkarten").font(.headline)
                            ProgressView(value: Double(passport.collectedCount), total: Double(max(1, passport.episodes.count))).tint(DS.accent)
                            Text("\(passport.recalledCount) ohne Hilfe · \(passport.rememberedCount) nach mindestens 7 Tagen abgerufen")
                                .font(.caption).foregroundStyle(DS.textSecondary)
                        }.dsCard().accessibilityIdentifier("passport-progress")
                        ForEach(EpisodeLibrary.all.filter { $0.language == language }) { episode in
                            let stamp = passport.stamp(for: episode)
                            Button { selection = episode } label: {
                                VStack(alignment: .leading, spacing: DS.space.md) {
                                    StoryArtwork(episode: episode, celebrating: stamp.collected)
                                        .aspectRatio(320.0 / 150.0, contentMode: .fit).frame(maxHeight: 140)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(episode.title).font(.headline).foregroundStyle(DS.textPrimary)
                                        Text(episode.outcome).font(.subheadline).foregroundStyle(DS.textSecondary)
                                        Text(status(episode, data: data)).font(.caption).foregroundStyle(DS.accentText)
                                    }
                                    StoryStampRow(stamp: stamp)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                    .dsCard(elevation: 1, padding: DS.space.md)
                            }.buttonStyle(.plain).accessibilityIdentifier("episode-\(episode.id)")
                        }
                    } else { Text("Der Lernverlauf konnte nicht gelesen werden. Deine Daten werden nicht überschrieben.") }
                    Text("Entdeckt heißt abgeschlossen, nicht beherrscht. Abruf-Marken beziehen sich auf alle Kursantworten einer Runde, nicht auf freies Sprechen. Inhalte sind noch nicht muttersprachlich geprüft; Arabisch verwendet Hocharabisch.")
                        .font(.footnote).foregroundStyle(DS.textSecondary)
                }.padding(DS.space.md).frame(maxWidth: DS.mainContentWidth).frame(maxWidth: .infinity)
            }
            .background(DS.pageBackground.ignoresSafeArea())
            .navigationTitle("Geschichtenpass").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .fullScreenCover(item: $selection) { EpisodeView(episode: $0) }
        }
    }
    private func status(_ episode: LearningEpisode, data: LearningExperience) -> String {
        if data.runs.contains(where: { $0.episodeID == episode.id && $0.isOpen }) { return "Fortsetzen · dein Platz ist gespeichert" }
        if data.isCheckDue(episode) { return "Zeit für einen Abruf ohne Vorlage" }
        let retained = data.retainedCount(for: episode)
        if retained > 0 { return "\(retained) Antworten zeitversetzt abgerufen" }
        if data.completed(in: language).contains(episode.id) { return "Geübt · Langzeitabruf noch offen" }
        return "Neu · etwa 2 Minuten"
    }
}
