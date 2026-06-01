import SwiftUI
import SwiftData
import PDFKit
import UniformTypeIdentifiers

/// PDF → paste-import bridge. User picks a tutor PDF (text-based, like the
/// teacher's `Alex. 11.03.pdf`), we extract the text via PDFKit and parse
/// Cyrillic/Latin word boundaries to recover Russian/German pairs. Topic
/// name is auto-detected from the filename (e.g. `Lektion 11.03`). The
/// parsed lines are handed off to `PasteImportView` so the user still
/// validates before committing.
struct PDFImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingPicker = false
    @State private var parsedText: String = ""
    @State private var topic: String = ""
    @State private var fileName: String = ""
    @State private var parseError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("PDF auswählen", systemImage: "doc.text.magnifyingglass")
                    }
                    if !fileName.isEmpty {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
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
                    Text("Wähle eine Text-PDF von deinem Tutor. Russisch und Deutsch werden automatisch erkannt, das Datum aus dem Dateinamen wird als Thema vorgeschlagen.")
                }

                if !parsedText.isEmpty {
                    Section("Thema") {
                        TextField("Thema (z.B. Lektion 11.03)", text: $topic)
                    }
                    Section("Vorschau (\(lineCount) Zeilen)") {
                        TextEditor(text: $parsedText)
                            .font(.body.monospaced())
                            .frame(minHeight: 200)
                    }
                }
            }
            .navigationTitle("PDF Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    NavigationLink {
                        PasteImportView(initialText: combinedText, initialOrder: .deRu)
                    } label: {
                        Text("Weiter")
                    }
                    .disabled(parsedText.isEmpty)
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

    private var lineCount: Int {
        parsedText.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    /// Combine the parsed pairs with the topic suffix so the downstream
    /// PasteImportView sees one paste with consistent `DE = RU | Topic` lines.
    private var combinedText: String {
        guard !topic.trimmingCharacters(in: .whitespaces).isEmpty else { return parsedText }
        return parsedText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { raw -> String in
                let line = String(raw).trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty else { return "" }
                // Don't double-add if user already typed a `| Topic` per line.
                if line.contains("|") { return line }
                return "\(line) | \(topic)"
            }
            .joined(separator: "\n")
    }

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
            topic = PDFImportParser.topicFromFilename(fileName)
            parsedText = PDFImportParser.parsePairs(text)
            if parsedText.isEmpty {
                parseError = "Keine Russisch/Deutsch-Paare gefunden. Versuche, sie manuell zu kopieren."
            }
        case .failure(let error):
            parseError = "Fehler: \(error.localizedDescription)"
        }
    }
}

// MARK: - Parser

enum PDFImportParser {
    /// Parses raw PDF text into "DE = RU" lines, one per detected pair.
    /// Handles both layouts found in the user's tutor PDFs:
    ///   - mixed on one line:  "куда? wohin?"
    ///   - split across two:   "Я встречаюсь с друзьями\nIch treffe meine Freunde"
    /// Skips obvious headers ("Vokabeln zum Wiederholen"), bullet dashes,
    /// blank lines, and orphan German (German that has no preceding Russian).
    static func parsePairs(_ rawText: String) -> String {
        let lines = rawText
            .split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var entries: [(de: String, ru: String)] = []
        var pendingRussian: String? = nil

        for raw in lines {
            if raw.isEmpty { continue }
            let lower = raw.lowercased()
            if lower.contains("vokabeln") || lower.contains("wiederholen") { continue }

            // Strip bullet dash + spaces.
            var content = raw
            if content.hasPrefix("-") || content.hasPrefix("•") || content.hasPrefix("–") {
                content = String(content.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            if content.isEmpty { continue }

            let scripts = scriptsIn(content)

            if scripts.cyrillic && scripts.latin {
                // Single-line: split at the first Latin char after Cyrillic.
                if let split = splitMixed(content) {
                    entries.append((de: split.de, ru: split.ru))
                    pendingRussian = nil
                }
            } else if scripts.cyrillic {
                // Pure Russian: hold for the next line.
                pendingRussian = content
            } else if scripts.latin {
                // Pure German: pair with held Russian if any.
                if let ru = pendingRussian {
                    entries.append((de: content, ru: ru))
                    pendingRussian = nil
                }
                // Otherwise orphan — silently drop.
            }
        }

        return entries.map { "\($0.de) = \($0.ru)" }.joined(separator: "\n")
    }

    /// Parses a filename like "Alex. 11.03.pdf" into "Lektion 11.03". Falls
    /// back to the bare filename stem if no date is found.
    static func topicFromFilename(_ filename: String) -> String {
        let stem = (filename as NSString).deletingPathExtension
        if let range = stem.range(of: #"(\d{1,2}\.\d{1,2}(?:\.\d{2,4})?)"#, options: .regularExpression) {
            return "Lektion \(stem[range])"
        }
        return stem
    }

    // MARK: - Helpers

    /// What scripts are present in this string? Cyrillic is U+0400-U+04FF.
    /// Latin counts ASCII A-Z/a-z plus Latin-1 supplement (umlauts, ß).
    static func scriptsIn(_ s: String) -> (cyrillic: Bool, latin: Bool) {
        var cyr = false, lat = false
        for scalar in s.unicodeScalars {
            let v = scalar.value
            if (0x0400...0x04FF).contains(v) {
                cyr = true
            } else if (0x0041...0x005A).contains(v) ||
                      (0x0061...0x007A).contains(v) ||
                      (0x00C0...0x00FF).contains(v) {
                lat = true
            }
            if cyr && lat { break }
        }
        return (cyr, lat)
    }

    /// Splits a mixed-script line at the first Latin character that follows
    /// a Cyrillic character. Returns (ru, de) trimmed.
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
