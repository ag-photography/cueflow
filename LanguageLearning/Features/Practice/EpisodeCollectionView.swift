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
                    Text("Kleine Geschichten, echte Formulierungen") .font(.title2.bold())
                    Text("Wähle eine Szene, die zu deinem Unterricht oder Alltag passt. Die Vorschau ist noch nicht muttersprachlich geprüft; Arabisch verwendet Hocharabisch.")
                        .font(.subheadline).foregroundStyle(DS.textSecondary)
                    if let data = experience {
                        ForEach(EpisodeLibrary.all.filter { $0.language == language }) { episode in
                            Button { selection = episode } label: {
                                HStack(alignment: .top, spacing: DS.space.md) {
                                    Image(systemName: episode.symbol).font(.title2).foregroundStyle(DS.accent).frame(width: 36)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(episode.title).font(.headline).foregroundStyle(DS.textPrimary)
                                        Text(episode.outcome).font(.subheadline).foregroundStyle(DS.textSecondary)
                                        Text(status(episode, data: data)).font(.caption).foregroundStyle(DS.accent)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").foregroundStyle(DS.textSecondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                    .dsCard(elevation: 1, padding: DS.space.md)
                            }.buttonStyle(.plain).accessibilityIdentifier("episode-\(episode.id)")
                        }
                    } else { Text("Der Lernverlauf konnte nicht gelesen werden. Deine Daten werden nicht überschrieben.") }
                }.padding(DS.space.md).frame(maxWidth: DS.mainContentWidth).frame(maxWidth: .infinity)
            }
            .background(DS.pageBackground.ignoresSafeArea())
            .navigationTitle("Geschichten").navigationBarTitleDisplayMode(.inline)
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
