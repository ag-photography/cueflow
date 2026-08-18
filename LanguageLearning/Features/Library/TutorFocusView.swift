import SwiftUI
import SwiftData

/// A short path from the current real-world lesson to the practice queue.
/// Tutor phrases are activated until the lesson focus is completed. A next
/// lesson date gives the scheduler a concrete daily preparation pace.
struct TutorFocusView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existingTopics: [Topic]
    @Query private var existingPhrases: [Phrase]
    @Query private var existingCards: [StudyCard]
    @Query private var languages: [Language]
    @Query private var settings: [AppSettings]

    @State private var topicName = ""
    @State private var rawText = ""
    @State private var order: LineOrder = .deRu
    @State private var nextLessonDate = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var saveErrorMessage: String?
    @State private var topicEditingDate: Topic?
    @State private var draftUsesLessonDate = true
    @State private var draftNextLessonDate = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now

    private var targetLanguage: Language? {
        let code = settings.first?.activeLanguageCode ?? "ru"
        return languages.first { $0.code == code } ?? languages.first
    }

    private var targetLabel: String { targetLanguage?.germanLabel ?? "Zielsprache" }

    private var tutorTopics: [Topic] {
        existingTopics.filter {
            $0.language?.code == targetLanguage?.code && $0.isTutorFocusActive
        }.sorted {
            ($0.tutorNextLessonAt ?? .distantFuture) < ($1.tutorNextLessonAt ?? .distantFuture)
        }
    }

    private var parsedLines: [ParsedLine] {
        rawText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { ParsedLine(index: $0.offset, raw: String($0.element), separator: "=", order: order) }
            .filter { !$0.raw.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var validLines: [ParsedLine] { parsedLines.filter(\.isValid) }

    var body: some View {
        NavigationStack {
            Form {
                if !tutorTopics.isEmpty {
                    Section {
                        ForEach(tutorTopics, id: \.persistentModelID) { topic in
                            existingFocusRow(topic)
                        }
                    } header: {
                        Text(tutorTopics.count == 1 ? "Laufende Unterrichtseinheit" : "Laufende Unterrichtseinheiten")
                    } footer: {
                        Text("Auch ältere Tutor-Importe bleiben hier steuerbar. Abschließen beendet nur den Fokus; der langfristige Wiederholungsplan bleibt erhalten.")
                    }
                }

                Section {
                    TextField("z. B. Jahreszeiten", text: $topicName)
                        .textInputAutocapitalization(.sentences)
                    DatePicker(
                        "Nächste Stunde",
                        selection: $nextLessonDate,
                        in: Calendar.current.startOfDay(for: .now)...,
                        displayedComponents: .date
                    )
                } header: {
                    Text("Neue oder bestehende Einheit")
                } footer: {
                    Text("CueFlow verteilt neue Ausdrücke so auf die verbleibenden Tage, dass du sie vor der nächsten Stunde mindestens einmal geübt hast.")
                }

                Section {
                    Picker("Reihenfolge", selection: $order) {
                        Text("Deutsch → \(targetLabel)").tag(LineOrder.deRu)
                        Text("\(targetLabel) → Deutsch").tag(LineOrder.ruDe)
                    }

                    ZStack(alignment: .topLeading) {
                        if rawText.isEmpty {
                            Text(exampleText)
                                .font(.body.monospaced())
                                .foregroundStyle(DS.textTertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $rawText)
                            .font(.body.monospaced())
                            .frame(minHeight: 170)
                            .scrollContentBackground(.hidden)
                    }
                } header: {
                    Text("Vokabeln einfügen")
                } footer: {
                    Text("Eine Vokabel oder Redewendung pro Zeile, getrennt mit =. Du kannst die Liste direkt aus den Notizen deines Tutors kopieren.")
                }

                if !parsedLines.isEmpty {
                    Section("Vorschau") {
                        Label(
                            "\(validLines.count) von \(parsedLines.count) Zeilen bereit",
                            systemImage: validLines.count == parsedLines.count ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(validLines.count == parsedLines.count ? DS.gradePerfect : DS.gradeHesitant)
                    }
                }

                Section {
                    Label("Tägliches Pensum passend zum nächsten Termin", systemImage: "calendar.badge.clock")
                    Label("Bleibt Teil deines langfristigen Lernplans", systemImage: "calendar.badge.clock")
                } header: {
                    Text("So wirkt der Tutor-Fokus")
                }
            }
            .navigationTitle("Tutor-Fokus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fokus erstellen") { commit() }
                        .disabled(trimmedTopicName.isEmpty || validLines.isEmpty)
                        .accessibilityIdentifier("tutor-focus-save")
                }
            }
            .alert("Tutor-Fokus konnte nicht gespeichert werden", isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "Bitte versuche es erneut.")
            }
            .sheet(item: $topicEditingDate) { topic in
                lessonDateEditor(topic)
            }
        }
    }

    private var trimmedTopicName: String {
        topicName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var exampleText: String {
        order == .deRu
            ? "Frühling = …\nSommer = …\nIm Herbst wird es kühler = …"
            : "… = Frühling\n… = Sommer\n… = Im Herbst wird es kühler"
    }

    @ViewBuilder
    private func existingFocusRow(_ topic: Topic) -> some View {
        let phraseIDs = Set((topic.phrases ?? []).map { String(describing: $0.persistentModelID) })
        let topicCards = existingCards.filter {
            guard let phrase = $0.phrase else { return false }
            return phraseIDs.contains(String(describing: phrase.persistentModelID))
        }
        let introduced = topicCards.count { $0.state.isIntroduced }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.name).font(.headline)
                    if let next = topic.tutorNextLessonAt {
                        Text("Nächste Stunde: \(next.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(DS.textSecondary)
                    } else {
                        Text("Laufend · Termin noch nicht gesetzt")
                            .font(.caption)
                            .foregroundStyle(DS.textSecondary)
                    }
                }
                Spacer()
                Text("\(introduced)/\(topicCards.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DS.textSecondary)
            }
            ProgressView(value: topicCards.isEmpty ? 0 : Double(introduced) / Double(topicCards.count))
                .tint(DS.accent)
            HStack {
                Button {
                    beginEditingDate(topic)
                } label: {
                    Label("Termin bearbeiten", systemImage: "calendar")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Abschließen", role: .destructive) { finish(topic) }
                    .buttonStyle(.bordered)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func beginEditingDate(_ topic: Topic) {
        draftUsesLessonDate = topic.tutorNextLessonAt != nil
        draftNextLessonDate = max(
            topic.tutorNextLessonAt ?? Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now,
            Calendar.current.startOfDay(for: .now)
        )
        topicEditingDate = topic
    }

    private func lessonDateEditor(_ topic: Topic) -> some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Nächste Stunde festlegen", isOn: $draftUsesLessonDate)
                    if draftUsesLessonDate {
                        DatePicker(
                            "Datum",
                            selection: $draftNextLessonDate,
                            in: Calendar.current.startOfDay(for: .now)...,
                            displayedComponents: .date
                        )
                    }
                } footer: {
                    Text("CueFlow berechnet das tägliche Pensum neu. Ohne Termin bleibt die Einheit aktiv und wird in einem sanften Sieben-Tage-Rhythmus vorbereitet.")
                }
            }
            .navigationTitle(topic.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { topicEditingDate = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        update(topic, nextLessonAt: draftUsesLessonDate ? draftNextLessonDate : nil)
                        topicEditingDate = nil
                    }
                    .accessibilityIdentifier("tutor-focus-date-save")
                }
            }
        }
    }

    private func update(_ topic: Topic, nextLessonAt: Date?) {
        topic.startTutorFocus(nextLessonAt: nextLessonAt)
        persistChanges()
    }

    private func finish(_ topic: Topic) {
        topic.finishTutorFocus()
        persistChanges()
    }

    private func persistChanges() {
        do {
            try context.save()
        } catch {
            context.rollback()
            saveErrorMessage = error.localizedDescription
        }
    }

    private func commit() {
        guard let language = targetLanguage else { return }
        let topic = existingTopics.first {
            $0.language?.code == language.code
                && $0.name.compare(trimmedTopicName, options: .caseInsensitive) == .orderedSame
        } ?? Topic(name: trimmedTopicName, language: language, isActive: true)

        if topic.modelContext == nil { context.insert(topic) }
        topic.startTutorFocus(nextLessonAt: nextLessonDate)

        var signatures = Set(existingPhrases.map {
            "\($0.language?.code ?? "")|\(Phrase.normalize($0.sourceText))|\(Phrase.normalize($0.targetText))"
        })
        let priorityEnd = topic.tutorFocusUntil

        for line in validLines {
            guard let source = line.source, let target = line.target else { continue }
            let signature = "\(language.code)|\(Phrase.normalize(source))|\(Phrase.normalize(target))"

            if let existing = existingPhrases.first(where: {
                "\($0.language?.code ?? "")|\(Phrase.normalize($0.sourceText))|\(Phrase.normalize($0.targetText))" == signature
            }) {
                if !(existing.topics ?? []).contains(where: { $0 === topic }) {
                    existing.topics = (existing.topics ?? []) + [topic]
                }
                existing.isPriority = true
                existing.priorityUntil = priorityEnd
                continue
            }
            guard signatures.insert(signature).inserted else { continue }

            let phrase = Phrase(sourceText: source, targetText: target, language: language, topics: [topic])
            phrase.contentSource = .tutorImport
            phrase.qualityStatus = .unreviewed
            phrase.isPriority = true
            phrase.priorityUntil = priorityEnd
            context.insert(phrase)
            context.insert(StudyCard(phrase: phrase))
        }

        do {
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            saveErrorMessage = error.localizedDescription
        }
    }
}
