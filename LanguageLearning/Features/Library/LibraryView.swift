import SwiftUI
import SwiftData

/// Library: Topics + Phrases CRUD, paste-import, settings. Active topics drive
/// new-card source for the scheduler.
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Topic.name) private var topics: [Topic]
    @Query(sort: \Phrase.createdAt, order: .reverse) private var phrases: [Phrase]

    @State private var showingPasteImport = false
    @State private var showingPDFImport = false
    @State private var showingSettings = false
    @State private var phraseInEditor: Phrase?
    @State private var creatingPhrase = false
    @State private var topicInEditor: Topic?
    @State private var creatingTopic = false

    var body: some View {
        NavigationStack {
            List {
                topicsSection
                phrasesSection
            }
            .navigationTitle("Bibliothek")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            creatingPhrase = true
                        } label: {
                            Label("Phrase hinzufügen", systemImage: "plus.bubble")
                        }
                        Button {
                            creatingTopic = true
                        } label: {
                            Label("Thema hinzufügen", systemImage: "tag")
                        }
                        Button {
                            showingPasteImport = true
                        } label: {
                            Label("Stapel-Import", systemImage: "square.and.arrow.down.on.square")
                        }
                        Button {
                            showingPDFImport = true
                        } label: {
                            Label("PDF importieren", systemImage: "doc.text.magnifyingglass")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingPasteImport) { PasteImportView() }
            .sheet(isPresented: $showingPDFImport) { PDFImportView() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $creatingPhrase) { PhraseEditorView(phrase: nil) }
            .sheet(item: $phraseInEditor) { phrase in PhraseEditorView(phrase: phrase) }
            .sheet(isPresented: $creatingTopic) { TopicEditorView(topic: nil) }
            .sheet(item: $topicInEditor) { topic in TopicEditorView(topic: topic) }
        }
    }

    private var topicsSection: some View {
        Section("Themen") {
            if topics.isEmpty {
                Text("Noch keine Themen.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(topics) { topic in
                    Button {
                        topicInEditor = topic
                    } label: {
                        HStack {
                            Text(topic.name)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            if topic.isActive {
                                Text("Aktiv")
                                    .font(.caption)
                                    .foregroundStyle(.tint)
                            }
                            Text("\(topic.phrases.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(topics[index]) }
                    try? context.save()
                }
            }
        }
    }

    private var phrasesSection: some View {
        Section("Phrasen (\(phrases.count))") {
            if phrases.isEmpty {
                Text("Füge 5 Phrasen hinzu, um zu starten.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(phrases) { phrase in
                    Button {
                        phraseInEditor = phrase
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(phrase.sourceText)
                                .foregroundStyle(Color.primary)
                            Text(phrase.targetText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if !phrase.topics.isEmpty {
                                HStack(spacing: 4) {
                                    ForEach(phrase.topics) { topic in
                                        Text(topic.name)
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.15))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(phrases[index]) }
                    try? context.save()
                }
            }
        }
    }
}
