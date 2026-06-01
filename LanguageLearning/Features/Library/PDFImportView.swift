import SwiftUI
import SwiftData
import PDFKit
import UniformTypeIdentifiers

/// PDF → automatic topic-classified import. User picks a tutor PDF, the
/// view extracts the text via PDFKit, parses Cyrillic/Latin pairs, and
/// auto-classifies each pair into an existing topic (Familie, Wochentage,
/// Essen & Trinken, …). Preview is grouped by topic; commit creates any
/// missing topics, attaches phrases, and activates the touched topics so
/// the new vocabulary shows up in practice immediately.
struct PDFImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existingTopics: [Topic]
    @Query private var existingPhrases: [Phrase]
    @Query private var languages: [Language]

    @State private var showingPicker = false
    @State private var fileName: String = ""
    @State private var pairs: [ClassifiedPair] = []
    @State private var parseError: String?

    var body: some View {
        NavigationStack {
            Form {
                fileSection
                if !pairs.isEmpty {
                    previewSection
                }
            }
            .navigationTitle("PDF Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importieren") { commit() }
                        .disabled(pairs.isEmpty)
                        .fontWeight(.semibold)
                }
            }
            .fileImporter(
                isPresented: $showingPicker,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                handleFile(result)
            }
        }
    }

    // MARK: - Sections

    private var fileSection: some View {
        Section {
            Button {
                showingPicker = true
            } label: {
                Label("PDF auswählen", systemImage: "doc.text.magnifyingglass")
            }
            if !fileName.isEmpty {
                HStack {
                    Image(systemName: "doc.text").foregroundStyle(.secondary)
                    Text(fileName)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if let err = parseError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Datei")
        } footer: {
            Text("Wähle eine Text-PDF von deinem Tutor. Die Vokabeln werden automatisch dem passenden Thema zugeordnet (Familie, Verben, Essen & Trinken, …) und die Themen aktiviert.")
        }
    }

    private var previewSection: some View {
        let groups = Dictionary(grouping: pairs.indices, by: { pairs[$0].topic })
            .sorted { $0.value.count > $1.value.count }
        return ForEach(groups, id: \.key) { topicName, indices in
            Section {
                ForEach(indices, id: \.self) { i in
                    pairRow(i)
                }
            } header: {
                HStack {
                    Text(topicName)
                    Spacer()
                    Text("\(indices.count)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func pairRow(_ i: Int) -> some View {
        let pair = pairs[i]
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pair.de)
                    .font(.subheadline.weight(.medium))
                Text(pair.ru)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(PhraseClassifier.allTopicNames, id: \.self) { name in
                    Button(name) {
                        pairs[i].topic = name
                    }
                }
            } label: {
                Image(systemName: "tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - File pick & parse

    private func handleFile(_ result: Result<[URL], Error>) {
        parseError = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            guard let pdf = PDFDocument(url: url) else {
                parseError = "PDF konnte nicht geöffnet werden."
                return
            }
            let text = pdf.string ?? ""
            guard !text.isEmpty else {
                parseError = "Keinen Text in der PDF gefunden. Eventuell ist sie eingescannt (OCR nötig)."
                return
            }
            fileName = url.lastPathComponent
            let parsed = PDFImportParser.parsePairs(text)
            pairs = parsed.map { pair in
                ClassifiedPair(
                    de: pair.de,
                    ru: pair.ru,
                    topic: PhraseClassifier.classify(de: pair.de, ru: pair.ru)
                )
            }
            if pairs.isEmpty {
                parseError = "Keine Russisch/Deutsch-Paare gefunden."
            }
        case .failure(let error):
            parseError = "Fehler: \(error.localizedDescription)"
        }
    }

    // MARK: - Commit

    private func commit() {
        guard let language = languages.first(where: { $0.code == "ru" }) ?? languages.first else {
            dismiss(); return
        }

        // Topic cache: reuse existing topics by name, lazily create missing ones.
        var topicCache: [String: Topic] = Dictionary(uniqueKeysWithValues: existingTopics.map { ($0.name, $0) })
        // Phrase dedupe set so re-importing the same PDF doesn't double-add.
        var signatures = Set(existingPhrases.map { "\($0.sourceText)|||\($0.targetText)" })

        var touchedTopics: Set<PersistentIdentifier> = []

        for pair in pairs {
            let sig = "\(pair.de)|||\(pair.ru)"
            guard !signatures.contains(sig) else {
                // Still mark the topic as touched so it gets activated even
                // if the phrase already exists.
                if let topic = topicCache[pair.topic] {
                    touchedTopics.insert(topic.persistentModelID)
                }
                continue
            }
            signatures.insert(sig)

            let topic: Topic
            if let existing = topicCache[pair.topic] {
                topic = existing
            } else {
                topic = Topic(name: pair.topic, language: language, isActive: false)
                context.insert(topic)
                topicCache[pair.topic] = topic
            }
            touchedTopics.insert(topic.persistentModelID)

            let phrase = Phrase(
                sourceText: pair.de,
                targetText: pair.ru,
                language: language,
                topics: [topic]
            )
            context.insert(phrase)
            for direction in CardDirection.allCases {
                context.insert(StudyCard(phrase: phrase, direction: direction))
            }
        }

        // Activate every touched topic so the freshly imported vocab actually
        // surfaces in the practice queue.
        for topic in topicCache.values where touchedTopics.contains(topic.persistentModelID) {
            topic.isActive = true
        }

        try? context.save()
        dismiss()
    }
}

private struct ClassifiedPair: Identifiable {
    var id = UUID()
    var de: String
    var ru: String
    var topic: String
}

// MARK: - Parser (unchanged from build 17)

enum PDFImportParser {
    struct Pair { let de: String; let ru: String }

    static func parsePairs(_ rawText: String) -> [Pair] {
        let lines = rawText
            .split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var entries: [Pair] = []
        var pendingRussian: String? = nil

        for raw in lines {
            if raw.isEmpty { continue }
            let lower = raw.lowercased()
            if lower.contains("vokabeln") || lower.contains("wiederholen") { continue }

            var content = raw
            if content.hasPrefix("-") || content.hasPrefix("•") || content.hasPrefix("–") {
                content = String(content.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            if content.isEmpty { continue }

            let scripts = scriptsIn(content)

            if scripts.cyrillic && scripts.latin {
                if let split = splitMixed(content) {
                    entries.append(Pair(de: split.de, ru: split.ru))
                    pendingRussian = nil
                }
            } else if scripts.cyrillic {
                pendingRussian = content
            } else if scripts.latin {
                if let ru = pendingRussian {
                    entries.append(Pair(de: content, ru: ru))
                    pendingRussian = nil
                }
            }
        }
        return entries
    }

    static func scriptsIn(_ s: String) -> (cyrillic: Bool, latin: Bool) {
        var cyr = false, lat = false
        for scalar in s.unicodeScalars {
            let v = scalar.value
            if (0x0400...0x04FF).contains(v) { cyr = true }
            else if (0x0041...0x005A).contains(v) ||
                    (0x0061...0x007A).contains(v) ||
                    (0x00C0...0x00FF).contains(v) { lat = true }
            if cyr && lat { break }
        }
        return (cyr, lat)
    }

    static func splitMixed(_ s: String) -> (ru: String, de: String)? {
        var sawCyrillic = false
        for idx in s.indices {
            guard let scalar = s[idx].unicodeScalars.first else { continue }
            let v = scalar.value
            let isCyr = (0x0400...0x04FF).contains(v)
            let isLat = (0x0041...0x005A).contains(v) ||
                        (0x0061...0x007A).contains(v) ||
                        (0x00C0...0x00FF).contains(v)
            if isCyr { sawCyrillic = true }
            if sawCyrillic && isLat {
                let ru = String(s[..<idx]).trimmingCharacters(in: .whitespaces)
                let de = String(s[idx...]).trimmingCharacters(in: .whitespaces)
                if ru.isEmpty || de.isEmpty { return nil }
                return (ru, de)
            }
        }
        return nil
    }
}
