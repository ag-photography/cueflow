import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Developer-facing diagnostics. Read-only summary of how often the auto-grader
/// got it right vs. how often the user had to override — the signal we'll use
/// at M6 to tune Tier-2 thresholds and decide whether the foundation-model
/// judge is paying its keep.
///
/// Also exposes a JSON export so the user can run the official Python
/// `fsrs-optimizer` offline once they hit ~500 reviews. swift-fsrs has no
/// in-app trainer.
struct TelemetryView: View {
    @Query(sort: \Review.timestamp, order: .reverse) private var reviews: [Review]
    @State private var exportURL: URL?
    @State private var exportError: String?

    var body: some View {
        Form {
            overviewSection
            tierSection
            divergenceSection
            recentSection
            exportSection
        }
        .navigationTitle("Diagnose")
    }

    // MARK: - Sections

    private var overviewSection: some View {
        Section("Übersicht") {
            row("Reviews insgesamt", "\(reviews.count)")
            row("Override-Quote", percentString(divergentCount, of: reviews.count))
            row("Mittlere Antwortzeit", responseTimeAvgString)
        }
    }

    private var tierSection: some View {
        Section {
            row("Tier 1 (exakt)", "\(tierCount(1))")
            row("Tier 2 (fuzzy)", "\(tierCount(2))")
            row("Tier 3 (KI)", "\(tierCount(3))")
        } header: {
            Text("Tier-Verteilung")
        } footer: {
            Text("Hoher Tier-2-Anteil mit vielen Overrides → Schwellen lockern. Hoher Tier-3-Anteil ohne Override-Reduktion → KI-Hilfe abschalten.")
                .font(.caption)
        }
    }

    private var divergenceSection: some View {
        Section {
            if divergenceBuckets.isEmpty {
                Text("Noch keine Overrides aufgezeichnet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(divergenceBuckets, id: \.label) { bucket in
                    HStack {
                        Text(bucket.label)
                        Spacer()
                        Text("\(bucket.count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        } header: {
            Text("Auto-Grade vs. Override")
        } footer: {
            Text("Pre → Post (Anzahl). „wrong → good\" sind Kandidaten für die Liste akzeptierter Alternativen.")
                .font(.caption)
        }
    }

    private var recentSection: some View {
        Section("Letzte 7 Tage") {
            row("Reviews", "\(recentReviewCount)")
            row("Neue Karten", "\(recentNewCount)")
        }
    }

    private var exportSection: some View {
        Section {
            Button {
                exportReviewsJSON()
            } label: {
                Label("Reviews als JSON exportieren", systemImage: "square.and.arrow.up")
            }
            .disabled(reviews.isEmpty)

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
            Text("Daten")
        } footer: {
            Text("Für die Offline-Optimierung der FSRS-Gewichte mit fsrs-optimizer (Python). Format: card_id, review_time, rating.")
                .font(.caption)
        }
    }

    // MARK: - Stats

    private var divergentCount: Int {
        reviews.filter { $0.rating != $0.autoGradeRating }.count
    }

    private func tierCount(_ tier: Int) -> Int {
        reviews.filter { $0.gradeTier == tier }.count
    }

    private var responseTimeAvgString: String {
        guard !reviews.isEmpty else { return "—" }
        let total = reviews.reduce(0) { $0 + $1.responseTimeMs }
        let avgMs = Double(total) / Double(reviews.count)
        return String(format: "%.1f s", avgMs / 1000)
    }

    private var divergenceBuckets: [DivergenceBucket] {
        let labels: [Int: String] = [1: "again", 2: "hard", 3: "good", 4: "easy"]
        var counts: [String: Int] = [:]
        for r in reviews where r.rating != r.autoGradeRating {
            let key = "\(labels[r.autoGradeRating] ?? "?") → \(labels[r.rating] ?? "?")"
            counts[key, default: 0] += 1
        }
        return counts
            .map { DivergenceBucket(label: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private var recentReviewCount: Int {
        let cutoff = Date.now.addingTimeInterval(-7 * 24 * 3600)
        return reviews.filter { $0.timestamp >= cutoff }.count
    }

    private var recentNewCount: Int {
        let cutoff = Date.now.addingTimeInterval(-7 * 24 * 3600)
        return reviews.filter { $0.timestamp >= cutoff && $0.wasNew }.count
    }

    // MARK: - Helpers

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func percentString(_ part: Int, of total: Int) -> String {
        guard total > 0 else { return "—" }
        let pct = Int((Double(part) / Double(total)) * 100)
        return "\(pct) %  (\(part)/\(total))"
    }

    // MARK: - Export

    private func exportReviewsJSON() {
        struct Row: Encodable {
            let card_id: String
            let review_time: Int    // seconds since epoch
            let rating: Int         // 1..4 (FSRS)
            let auto_rating: Int
            let response_ms: Int
            let mode: String
            let tier: Int
            let was_new: Bool
        }
        let rows: [Row] = reviews.map { r in
            // Use phrase target text as a stable card_id substitute.
            // The fsrs-optimizer just needs each card's reviews grouped together;
            // it doesn't care about the literal id format.
            let cardId = r.card?.phrase?.targetTextNormalized
                ?? r.card?.phrase?.targetText
                ?? "unknown"
            let direction = r.card?.direction.rawValue ?? r.modeRaw
            return Row(
                card_id: "\(cardId)|\(direction)",
                review_time: Int(r.timestamp.timeIntervalSince1970),
                rating: r.rating,
                auto_rating: r.autoGradeRating,
                response_ms: r.responseTimeMs,
                mode: r.modeRaw,
                tier: r.gradeTier,
                was_new: r.wasNew
            )
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(rows)
            let stamp = ISO8601DateFormatter().string(from: .now)
                .replacingOccurrences(of: ":", with: "-")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("cueflow-reviews-\(stamp).json")
            try data.write(to: url, options: .atomic)
            exportURL = url
            exportError = nil
        } catch {
            exportError = "Export fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}

private struct DivergenceBucket {
    let label: String
    let count: Int
}
