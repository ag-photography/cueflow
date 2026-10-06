import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupView: View {
    @Environment(\.modelContext) private var context
    @Query private var settings: [AppSettings]

    @State private var exportURL: URL?
    @State private var message: String?
    @State private var showingImporter = false
    // Counts come from `fetchCount` (a SELECT COUNT) — this screen used to
    // materialise the entire store just to print three numbers.
    @State private var counts: (phrases: Int, topics: Int, reviews: Int) = (0, 0, 0)

    var body: some View {
        Form {
            Section("Stand") {
                row("Ausdrücke", "\(counts.phrases)")
                row("Themen", "\(counts.topics)")
                row("Reviews", "\(counts.reviews)")
            }

            Section {
                Button(action: exportAll) {
                    Label("Vollständige Sicherung erstellen", systemImage: "square.and.arrow.up")
                }
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Datei teilen", systemImage: "paperplane")
                    }
                }
                Button {
                    showingImporter = true
                } label: {
                    Label("Sicherung wiederherstellen", systemImage: "square.and.arrow.down")
                }
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.hasPrefix("Fehler") ? DS.gradeWrong : DS.textSecondary)
                }
            } header: {
                Text("Sicherung & Wiederherstellung")
            } footer: {
                Text("Die JSON-Datei enthält Sprachen, Themen, Ausdrücke, Lernpläne, Reviews und Einstellungen. Wiederherstellen führt Daten sicher zusammen und erzeugt keine doppelten Reviews.")
            }
        }
        .navigationTitle("Sicherung")
        .task { refreshCounts() }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: importBackup
        )
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func refreshCounts() {
        counts = (
            (try? context.fetchCount(FetchDescriptor<Phrase>())) ?? 0,
            (try? context.fetchCount(FetchDescriptor<Topic>())) ?? 0,
            (try? context.fetchCount(FetchDescriptor<Review>())) ?? 0
        )
    }

    private func exportAll() {
        do {
            let info = Bundle.main.infoDictionary
            let version = info?["CFBundleShortVersionString"] as? String ?? "?"
            let build = info?["CFBundleVersion"] as? String ?? "?"
            // The whole graph is only needed at this moment.
            let languages = (try? context.fetch(FetchDescriptor<Language>())) ?? []
            let topics = (try? context.fetch(FetchDescriptor<Topic>())) ?? []
            let phrases = (try? context.fetch(FetchDescriptor<Phrase>())) ?? []
            let backup = BackupService.makeBackup(
                languages: languages,
                topics: topics,
                phrases: phrases,
                settings: settings.first,
                appVersion: "\(version) (\(build))"
            )
            let data = try BackupService.encode(backup)
            let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("cueflow-backup-\(stamp).json")
            try data.write(to: url, options: .atomic)
            exportURL = url
            message = "Sicherung erstellt."
        } catch {
            message = "Fehler: \(error.localizedDescription)"
        }
    }

    private func importBackup(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let backup = try BackupService.decode(
                data,
                legacyLanguageCode: settings.first?.activeLanguageCode ?? "ru"
            )
            let summary = try BackupService.restore(backup, into: context)
            refreshCounts()
            message = "Wiederhergestellt: \(summary.phrasesAdded) neue Ausdrücke, \(summary.phrasesMerged) zusammengeführt, \(summary.reviewsAdded) Reviews."
        } catch {
            message = "Fehler: \(error.localizedDescription)"
        }
    }
}
