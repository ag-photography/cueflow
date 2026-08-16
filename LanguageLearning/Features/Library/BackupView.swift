import SwiftUI
import SwiftData

/// Full-data export as JSON — phrases, topics, reviews, settings. Gives the
/// user a manual safety net against unintended data loss (e.g. accidental
/// uninstall during a TestFlight upgrade).
///
/// TestFlight over-installs preserve SwiftData automatically; this export
/// exists as belt-and-braces, not because updates wipe data.
struct BackupView: View {
    @Environment(\.modelContext) private var context
    @Query private var phrases: [Phrase]
    @Query private var topics: [Topic]
    @Query private var reviews: [Review]
    @Query private var settings: [AppSettings]

    @State private var exportURL: URL?
    @State private var exportError: String?

    var body: some View {
        Form {
            Section("Stand") {
                row("Phrasen", "\(phrases.count)")
                row("Themen", "\(topics.count)")
                row("Reviews", "\(reviews.count)")
            }

            Section {
                Button {
                    exportAll()
                } label: {
                    Label("Vollständige Sicherung erstellen", systemImage: "square.and.arrow.up")
                }

                if let url = exportURL {
                    ShareLink(item: url) {
                        Label("Datei teilen", systemImage: "paperplane")
                    }
                }

                if let err = exportError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Sicherung")
            } footer: {
                Text("Exportiert alle Phrasen, Themen, Reviews und Einstellungen als JSON. Speichere die Datei in iCloud Drive oder per AirDrop. TestFlight-Updates erhalten deine Daten automatisch – dies ist nur eine zusätzliche Absicherung.")
            }
        }
        .navigationTitle("Sicherung")
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func exportAll() {
        struct TopicOut: Encodable {
            let name: String
            let isActive: Bool
            let parent: String?
        }
        struct PhraseOut: Encodable {
            let sourceText: String
            let targetText: String
            let transliteration: String?
            let notes: String?
            let topics: [String]
            let acceptedAlternatives: [String]
            let createdAt: Double
        }
        struct ReviewOut: Encodable {
            let cardId: String          // stable phrase target key
            let timestamp: Double
            let rating: Int
            let autoGradeRating: Int
            let userAnswer: String
            let mode: String
            let responseTimeMs: Int
            let gradeTier: Int
            let wasNew: Bool
        }
        struct Payload: Encodable {
            let exportedAt: Double
            let appVersion: String
            let topics: [TopicOut]
            let phrases: [PhraseOut]
            let reviews: [ReviewOut]
            let settings: [String: String]
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        let payload = Payload(
            exportedAt: Date.now.timeIntervalSince1970,
            appVersion: "\(appVersion) (\(build))",
            topics: topics.map {
                TopicOut(name: $0.name, isActive: $0.isActive, parent: $0.parent?.name)
            },
            phrases: phrases.map { p in
                PhraseOut(
                    sourceText: p.sourceText,
                    targetText: p.targetText,
                    transliteration: p.transliteration,
                    notes: p.notes,
                    topics: p.topics.map(\.name),
                    acceptedAlternatives: p.acceptedAlternatives,
                    createdAt: p.createdAt.timeIntervalSince1970
                )
            },
            reviews: reviews.map { r in
                let phraseKey = r.card?.phrase?.targetTextNormalized
                    ?? r.card?.phrase?.targetText
                    ?? "unknown"
                return ReviewOut(
                    cardId: phraseKey,
                    timestamp: r.timestamp.timeIntervalSince1970,
                    rating: r.rating,
                    autoGradeRating: r.autoGradeRating,
                    userAnswer: r.userAnswer,
                    mode: r.modeRaw,
                    responseTimeMs: r.responseTimeMs,
                    gradeTier: r.gradeTier,
                    wasNew: r.wasNew
                )
            },
            settings: settings.first.map { s in
                [
                    "dailyNewLimit": "\(s.dailyNewLimit)",
                    "activeLanguageCode": s.activeLanguageCode,
                    "transliterationVisible": s.transliterationVisible.map(String.init(describing:)) ?? "nil",
                    "useAIGradingAssist": "\(s.useAIGradingAssist)"
                ]
            } ?? [:]
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            let stamp = ISO8601DateFormatter().string(from: .now)
                .replacingOccurrences(of: ":", with: "-")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("cueflow-backup-\(stamp).json")
            try data.write(to: url, options: .atomic)
            exportURL = url
            exportError = nil
        } catch {
            exportError = "Export fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
