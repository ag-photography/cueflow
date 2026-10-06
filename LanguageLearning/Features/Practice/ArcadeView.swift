import SwiftUI
import SwiftData
import AVFoundation

struct ArcadeView: View {
    let mode: ArcadeMode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var cards: [StudyCard]
    @Query private var settings: [AppSettings]
    @State private var plan: [VocabularyArcade.Board] = []
    @State private var pool: [ArcadeWord] = []
    @State private var tokens: [WordTile] = []
    @State private var selectedTiles: [Int] = []
    @State private var typedAnswer = ""
    @State private var checked = false
    @State private var correctAnswer = false
    @State private var swipeOffset: CGFloat = 0
    @FocusState private var answerFocused: Bool
    private var words: [ArcadeWord] { plan.flatMap(\.words) }
    @State private var rightOrder: [ArcadeWord] = []
    @State private var choices: [ArcadeWord] = []
    @State private var score = ArcadeScore()
    @State private var stage = 0
    @State private var promptIndex = 0
    @State private var selected: String?
    @State private var mismatch: String?
    @State private var responseID: String?
    @State private var heard = false
    @State private var revealed = false
    @State private var finished = false
    @State private var loaded = false
    @State private var session = UUID()
    @State private var failure: String?
    @State private var saved = false
    @State private var speechTask: Task<Void, Never>?
    @StateObject private var speech = SpeechRecognitionService()
    @State private var micTask: Task<Void, Never>?
    @State private var micBlocked = false
    @State private var micNote: String?
    @State private var typeInstead = false
    /// The learner asked to see the answer during a from-memory spoken step.
    @State private var peek = false
    /// Board words already said aloud this round (echo or recall).
    @State private var spokenIDs: Set<String> = []
    @State private var spokenWords = 0

    private var language: String { settings.first?.activeLanguageCode ?? "ru" }
    private var locale: String { LanguagePack.configuration(for: language)?.ttsLocale ?? "ru-RU" }
    private var game: ArcadeMode { plan.indices.contains(stage) ? plan[stage].mode : mode }
    private var board: [ArcadeWord] { plan.indices.contains(stage) ? plan[stage].words : [] }
    private var gameColor: Color { game == .sound ? DS.listeningColor : game == .swipe ? DS.sprintColor : game == .recall ? DS.accentText : DS.conversationColor }
    private var gameSymbol: String {
        switch game {
        case .mix, .snap: return "square.grid.2x2.fill"
        case .sound: return "waveform"
        case .swipe: return "arrow.left.arrow.right"
        case .builder: return "puzzlepiece.extension.fill"
        case .recall: return "brain.head.profile"
        }
    }
    private var prompt: ArcadeWord? { board.indices.contains(promptIndex) ? board[promptIndex] : nil }
    private var boardDone: Bool { !board.isEmpty && board.allSatisfy { score.resolved.contains($0.id) } }
    private var stages: Int { plan.count }
    private var canHear: Bool { AVSpeechSynthesisVoice(language: locale) != nil }
    /// Quiet mode (set per language in Üben) silences automatic read-aloud;
    /// the explicit "Anhören" buttons keep working.
    private var quiet: Bool { (try? settings.first?.readExperience().preference(for: language).quiet) ?? false }
    private var autoSpeak: Bool { canHear && !quiet }
    /// Spoken steps (see `asksToSpeak`) are skipped in quiet mode or when the
    /// microphone is unavailable; the games stay fully playable either way.
    private var speaking: Bool { !quiet && !micBlocked }
    private var listening: Bool { speech.isRecording }

    /// A spoken step only where speaking means recall or shadowing, never
    /// reading aloud what is on screen: Sound Hunt (repeat what you heard),
    /// Phrase Builder (say the sentence without the tiles) and Recall after
    /// help or a miss. Snap and Swipe stay recognition games.
    private func asksToSpeak(_ word: ArcadeWord) -> Bool {
        guard speaking, !spokenIDs.contains(word.id) else { return false }
        switch game {
        case .sound, .builder: return true
        case .recall: return checked && !correctAnswer
        case .mix, .snap, .swipe: return false
        }
    }
    /// Until spoken (or peeked), the written answer stays hidden.
    private func hidesAnswer(_ word: ArcadeWord) -> Bool {
        (game == .sound || game == .builder) && asksToSpeak(word) && !peek
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    if !loaded { ProgressView() }
                    else if plan.isEmpty {
                        ContentUnavailableView(mode == .builder ? "Kurze Sätze gesucht" : "Noch zu wenig verschiedene Wörter", systemImage: "square.grid.2x2",
                            description: Text(mode == .builder ? "Phrase Builder braucht Ausdrücke mit 2 bis 8 Wörtern. Aktiviere ein passendes Thema oder importiere Unterrichtssätze." : "Aktiviere in der Bibliothek ein Thema mit verschiedenen Bedeutungen und Übersetzungen. Für Zuordnungsspiele brauchst du mindestens vier Paare."))
                        Button("Zurück") { dismiss() }.buttonStyle(.borderedProminent)
                    } else if finished { result }
                    else {
                        progress
                        if let micNote { Text(micNote).font(.caption).foregroundStyle(DS.textSecondary).multilineTextAlignment(.center) }
                        if mode == .mix && !plan.contains(where: { $0.mode == .builder }) {
                            Text("Heute ohne Phrase Builder: Dafür brauchst du aktive Ausdrücke mit 2 bis 8 Wörtern.")
                                .font(.caption).foregroundStyle(DS.textSecondary)
                        }
                        switch game {
                        case .sound: soundBoard
                        case .swipe: swipeBoard
                        case .builder: builderBoard
                        case .recall: recallBoard
                        case .mix, .snap: snapBoard
                        }
                        if boardDone && game == .snap {
                            Button(stage + 1 == stages ? "Runde abschließen" : "Weiter: \(plan[stage + 1].mode.title)") { advanceBoard() }
                                .buttonStyle(ArcadeActionStyle()).accessibilityIdentifier("arcade-next-board")
                        }
                    }
                }.padding(20).frame(maxWidth: DS.mainContentWidth).frame(maxWidth: .infinity)
                    .id("arcade-top")
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: stage) { _, _ in proxy.scrollTo("arcade-top", anchor: .top) }
            .onChange(of: promptIndex) { _, _ in proxy.scrollTo("arcade-top", anchor: .top) }
            .onChange(of: finished) { _, _ in proxy.scrollTo("arcade-top", anchor: .top) }
            }
            .background(DS.pageBackground.ignoresSafeArea())
            .navigationTitle(mode.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }.accessibilityIdentifier("arcade-close")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Tastatur schließen") { answerFocused = false }
                }
            }
        }
        .task { if !loaded { load() } }
        .modifier(ExposureBoundary(mode: "arcade", sessionID: session))
        .onDisappear { stopAudio() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { stopAudio() } }
        .onChange(of: language) { _, _ in stopAudio(); dismiss() }
        .onChange(of: speech.transcription) { _, transcript in heardSpeech(transcript) }
        .task(id: mismatch) {
            guard mismatch != nil else { return }
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            mismatch = nil; selected = nil
        }
    }

    private var progress: some View {
        VStack(spacing: 10) {
            HStack {
                Label(game.title.uppercased(), systemImage: gameSymbol)
                    .font(.caption.weight(.heavy)).tracking(1).foregroundStyle(gameColor)
                Spacer()
                Text("\(score.resolved.count) / \(words.count)").font(.headline.monospacedDigit())
            }
            ProgressView(value: Double(score.resolved.count), total: Double(max(1, words.count))).tint(DS.playMint)
                .accessibilityLabel("\(score.resolved.count) von \(words.count) Aufgaben geschafft")
            HStack {
                Text("Board \(stage + 1) von \(stages)").foregroundStyle(DS.textSecondary)
                Spacer()
                if score.streak >= 2 { Label("\(score.streak) in Folge!", systemImage: "bolt.fill").foregroundStyle(DS.sprintColor) }
            }.font(.caption.bold())
        }
    }

    private var snapBoard: some View {
        VStack(spacing: 16) {
            Text(boardDone ? "Board frei. Stark!" : "Was gehört zusammen?")
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text("Tippe ein deutsches Wort und seine Übersetzung an. Oder zieh es auf das passende Feld.")
                .font(.subheadline).foregroundStyle(DS.textSecondary).multilineTextAlignment(.center)
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    ForEach(board) { word in
                        tile(word, target: false)
                            .draggable(word.id)
                    }
                }
                VStack(spacing: 12) {
                    ForEach(rightOrder) { word in
                        tile(word, target: true)
                            .dropDestination(for: String.self) { items, _ in
                                guard let id = items.first, board.contains(where: { $0.id == id }), !score.resolved.contains(id), !score.resolved.contains(word.id), mismatch == nil else { return false }
                                selected = id; match(word); return true
                            }
                    }
                }
            }
            Text(mismatch != nil ? "Noch nicht das Paar. Probier’s nochmal." : boardDone ? "Alle Paare gefunden." : selected != nil ? "Jetzt die passende Übersetzung." : "Vier Paare. Du hast alle Zeit der Welt.")
                .font(.subheadline.weight(.semibold)).foregroundStyle(DS.textSecondary)
                .accessibilityIdentifier("arcade-feedback")
        }
    }

    private func tile(_ word: ArcadeWord, target: Bool) -> some View {
        let done = score.resolved.contains(word.id)
        let active = !target && selected == word.id
        let color = done ? DS.playMint : mismatch == word.id ? DS.sprintColor : DS.conversationColor
        return Button {
            guard mismatch == nil else { return }
            if target { match(word) } else { selected = selected == word.id ? nil : word.id }
        } label: {
            VStack(spacing: 6) {
                if done { Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.playMint) }
                Text(done ? "Gefunden" : target ? word.target : word.source)
                    .font(.system(.body, design: target && language == "ar" ? .default : .rounded, weight: .semibold))
                    .environment(\.layoutDirection, target && language == "ar" ? .rightToLeft : .leftToRight)
                    .foregroundStyle(done ? DS.textSecondary : DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 70).padding(12)
                .background(color.opacity(active ? 0.25 : done ? 0.05 : 0.1), in: RoundedRectangle(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(color.opacity(active ? 1 : 0.3), lineWidth: active ? 3 : 1) }
                .scaleEffect(done && !reduceMotion ? 0.94 : 1)
                .animation(reduceMotion ? nil : .spring(duration: 0.25), value: done)
        }.buttonStyle(PracticePressStyle()).disabled(done)
            .accessibilityLabel("\(target ? word.target : word.source)\(done ? ", gefunden" : "")")
            .accessibilityAddTraits(active ? .isSelected : [])
            .accessibilityIdentifier("arcade-\(target ? "target" : "source")-\(word.id)")
    }

    @ViewBuilder private var soundBoard: some View {
        if let word = prompt {
            VStack(spacing: 16) {
                Text("Hör genau hin.").font(.system(.title2, design: .rounded, weight: .bold))
                Text("Welche Bedeutung hörst du?").foregroundStyle(DS.textSecondary)
                Button { play(word) } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "speaker.wave.2.fill").font(.system(size: 42, weight: .bold))
                        Text(heard ? "Nochmal hören" : "Wort anhören").font(.headline)
                    }.frame(maxWidth: .infinity).padding(28)
                        .foregroundStyle(DS.listeningColor)
                        .background(DS.listeningColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 24))
                }.buttonStyle(PracticePressStyle()).disabled(!canHear).accessibilityIdentifier("arcade-listen")
                if !canHear { Text("Für diese Sprache ist keine Systemstimme verfügbar. Du kannst das Wort stattdessen ansehen.").font(.caption).foregroundStyle(DS.textSecondary) }
                if responseID == nil {
                    Button("Wort zeigen") { revealed = true; heard = true; score.answer(id: word.id, correct: false) }
                        .foregroundStyle(DS.accentText).frame(minHeight: 44)
                }
                if revealed || responseID != nil {
                    if revealed || !hidesAnswer(word) {
                        Text(word.target).font(.title2.bold()).foregroundStyle(DS.listeningColor)
                    }
                    if responseID != nil { Text(word.source).font(.headline) }
                }
                ForEach(choices) { option in
                    Button { chooseMeaning(option, correct: word) } label: {
                        HStack {
                            Text(option.source).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            if responseID != nil && option.id == word.id { Image(systemName: "checkmark.circle.fill") }
                        }.font(.headline).foregroundStyle(DS.textPrimary)
                            .padding(18).frame(maxWidth: .infinity, minHeight: 56)
                            .background(responseID != nil && option.id == word.id ? DS.playMint.opacity(0.18) : DS.surface1, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(PracticePressStyle()).disabled(!heard || responseID != nil)
                        .accessibilityIdentifier("arcade-choice-\(option.id)")
                }
                if let answer = responseID {
                    Text(answer == word.id && !revealed ? "Ja! Richtig gehört." : "Das gehört zusammen. Hör es dir gern nochmal an.")
                        .font(.subheadline.bold()).foregroundStyle(DS.accentText)
                    if asksToSpeak(word) || spokenIDs.contains(word.id) { sayIt(word) }
                    nextButton(word, identifier: "arcade-sound-next")
                }
            }
        }
    }

    @ViewBuilder private var swipeBoard: some View {
        if let word = prompt {
            VStack(spacing: 20) {
                Text("Wisch zum richtigen Wort.").font(.system(.title2, design: .rounded, weight: .bold))
                Text("Links oder rechts? Du kannst auch die Antwort antippen.")
                    .font(.subheadline).foregroundStyle(DS.textSecondary).multilineTextAlignment(.center)
                Text(word.target)
                    .font(LearningTypography.display(.largeTitle, languageCode: language))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 150).padding(20)
                    .background(DS.sprintColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 26))
                    .offset(x: reduceMotion ? 0 : swipeOffset)
                    .rotationEffect(.degrees(reduceMotion ? 0 : Double(swipeOffset / 16)))
                    .gesture(DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            guard responseID == nil else { return }
                            swipeOffset = min(80, max(-80, value.translation.width))
                        }
                        .onEnded { value in
                            defer { withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) { swipeOffset = 0 } }
                            guard responseID == nil, choices.count == 2,
                                  abs(value.translation.width) > 55,
                                  abs(value.translation.width) > abs(value.translation.height) else { return }
                            chooseSwipe(choices[value.translation.width < 0 ? 0 : 1], word: word)
                        })
                    .accessibilityIdentifier("arcade-swipe-card")
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                        Button { chooseSwipe(choice, word: word) } label: {
                            VStack(spacing: 8) {
                                Image(systemName: index == 0 ? "arrow.left" : "arrow.right")
                                Text(choice.source).fixedSize(horizontal: false, vertical: true)
                                if responseID != nil && choice.id == word.id { Image(systemName: "checkmark.circle.fill") }
                            }.font(.headline).foregroundStyle(DS.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 80).padding(12)
                                .background(responseID != nil && choice.id == word.id ? DS.playMint.opacity(0.18) : DS.surface1, in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(PracticePressStyle()).disabled(responseID != nil)
                            .accessibilityLabel("\(index == 0 ? "Links" : "Rechts"): \(choice.source)")
                            .accessibilityIdentifier("arcade-swipe-\(index)")
                    }
                }.environment(\.layoutDirection, .leftToRight)
                if responseID != nil { answerFeedback(word) }
            }
        }
    }

    @ViewBuilder private var builderBoard: some View {
        if let word = prompt {
            VStack(spacing: 18) {
                Text("Bau den Satz.").font(.system(.title2, design: .rounded, weight: .bold))
                Text(word.source).font(.title3.bold()).multilineTextAlignment(.center)
                if !(checked && hidesAnswer(word)) {
                Text("Tippe die Wörter in der passenden Reihenfolge. Im Satz kannst du sie wieder entfernen.")
                    .font(.subheadline).foregroundStyle(DS.textSecondary).multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 12) {
                    if selectedTiles.isEmpty {
                        Text("Dein Satz entsteht hier …").foregroundStyle(DS.textSecondary).frame(minHeight: 64)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], alignment: .leading, spacing: 10) {
                            ForEach(selectedTiles, id: \.self) { id in
                                if let tile = tokens.first(where: { $0.id == id }) {
                                    Button { selectedTiles.removeAll { $0 == id } } label: {
                                        Text(tile.text).font(.headline).padding(12)
                                            .frame(maxWidth: .infinity, minHeight: 48)
                                            .background(DS.conversationColor.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                                    }.buttonStyle(.plain).disabled(checked)
                                        .accessibilityLabel("\(tile.text) entfernen")
                                        .accessibilityIdentifier("arcade-built-\(id)")
                                }
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, minHeight: 90, alignment: .leading).padding(16)
                    .background(DS.surface1, in: RoundedRectangle(cornerRadius: 20))
                    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(DS.conversationColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])) }
                    .environment(\.layoutDirection, language == "ar" ? .rightToLeft : .leftToRight)
                    .dropDestination(for: String.self) { items, _ in
                        guard !checked, let raw = items.first, let id = Int(raw), tokens.contains(where: { $0.id == id }), !selectedTiles.contains(id) else { return false }
                        selectedTiles.append(id); return true
                    }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                    ForEach(tokens) { tile in
                        Button { selectTile(tile.id) } label: {
                            Text(tile.text).font(.headline).padding(12)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .foregroundStyle(selectedTiles.contains(tile.id) ? DS.textSecondary : DS.textPrimary)
                                .background(DS.conversationColor.opacity(selectedTiles.contains(tile.id) ? 0.04 : 0.16), in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(PracticePressStyle()).disabled(checked || selectedTiles.contains(tile.id))
                            .draggable(String(tile.id))
                            .accessibilityIdentifier("arcade-token-\(tile.id)")
                    }
                }.environment(\.layoutDirection, language == "ar" ? .rightToLeft : .leftToRight)
                }
                if checked { answerFeedback(word) }
                else {
                    Button("Satz prüfen") {
                        checkProduction(TileConstruction.answer(selectedIDs: selectedTiles, from: tokens), word: word)
                    }.buttonStyle(ArcadeActionStyle())
                        .disabled(!TileConstruction.isComplete(selectedIDs: selectedTiles, tiles: tokens))
                        .accessibilityIdentifier("arcade-builder-check")
                    Button("Gemeinsam lösen") { revealAnswer(word) }.frame(minHeight: 44).foregroundStyle(DS.accentText)
                        .accessibilityIdentifier("arcade-reveal")
                }
            }
        }
    }

    @ViewBuilder private var recallBoard: some View {
        if let word = prompt {
            VStack(spacing: 18) {
                Text("Jetzt aus dem Kopf.").font(.system(.title2, design: .rounded, weight: .bold))
                Text(word.source).font(.title.bold()).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 100).padding(20)
                    .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: 24))
                if speaking && !typeInstead && !checked {
                    Text(language == "ar" ? "Sag es auf Arabisch." : "Sag es auf Russisch.")
                        .font(.subheadline).foregroundStyle(DS.textSecondary)
                    micControls(done: false)
                    Button("Lieber tippen") { stopListening(); typeInstead = true }
                        .frame(minHeight: 44).foregroundStyle(DS.accentText)
                        .accessibilityIdentifier("arcade-recall-type")
                    Button("Noch unsicher · Antwort zeigen") { stopListening(); revealAnswer(word) }
                        .frame(minHeight: 44).foregroundStyle(DS.accentText).accessibilityIdentifier("arcade-reveal")
                } else {
                recallTyping(word)
                }
            }
        }
    }

    @ViewBuilder private func recallTyping(_ word: ArcadeWord) -> some View {
                if !checked {
                Text(language == "ar" ? "Tippe auf Arabisch. Die Tastatur wechselst du über die Globus-Taste." : "Tippe auf Russisch. Die Tastatur wechselst du über die Globus-Taste.")
                    .font(.subheadline).foregroundStyle(DS.textSecondary)
                }
                if !checked || !typedAnswer.isEmpty {
                TextField("Deine Antwort", text: $typedAnswer, axis: .vertical)
                    .font(.title2).lineLimit(2...5).padding(16)
                    .background(DS.surface1, in: RoundedRectangle(cornerRadius: 16))
                    .environment(\.layoutDirection, language == "ar" ? .rightToLeft : .leftToRight)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .focused($answerFocused).disabled(checked)
                    .accessibilityIdentifier("arcade-recall-input")
                }
                if checked { answerFeedback(word) }
                else {
                    Button("Antwort prüfen") { checkProduction(typedAnswer, word: word) }
                        .buttonStyle(ArcadeActionStyle()).disabled(typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("arcade-recall-check")
                    Button("Noch unsicher · Antwort zeigen") { revealAnswer(word) }
                        .frame(minHeight: 44).foregroundStyle(DS.accentText).accessibilityIdentifier("arcade-reveal")
                }
    }

    private func answerFeedback(_ word: ArcadeWord) -> some View {
        VStack(spacing: 12) {
            Label(correctAnswer && !revealed ? "Yes! Getroffen!" : "Unsere Kursantwort", systemImage: correctAnswer && !revealed ? "checkmark.circle.fill" : "lightbulb.fill")
                .font(.headline).foregroundStyle(DS.accentText)
            if !hidesAnswer(word) {
                Text(word.target).font(LearningTypography.display(.title2, languageCode: language))
                    .multilineTextAlignment(.center).foregroundStyle(DS.textPrimary)
            }
            // Phrase Builder already shows the German cue as its heading.
            if game != .builder { Text(word.source).font(.subheadline).foregroundStyle(DS.textSecondary) }
            if revealed { Text("Mit Hilfe geübt – zählt nicht als erster Treffer.").font(.caption).foregroundStyle(DS.textSecondary) }
            else if !correctAnswer && game == .recall {
                Text("Verglichen mit der Kursantwort und gespeicherten Alternativen. Weitere Formulierungen können ebenfalls richtig sein.")
                    .font(.caption).foregroundStyle(DS.textSecondary)
            }
            if !hidesAnswer(word) {
                Button { play(word) } label: { Label("Anhören", systemImage: "speaker.wave.2.fill") }
                    .disabled(!canHear).foregroundStyle(DS.accentText).frame(minHeight: 44)
            }
            if asksToSpeak(word) || spokenIDs.contains(word.id) { sayIt(word) }
            nextButton(word, identifier: "arcade-answer-next")
        }.padding(16).background(gameColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
    }

    /// The spoken step: recall or shadowing, then a "Laut gesagt" receipt.
    private func sayIt(_ word: ArcadeWord) -> some View {
        let said = spokenIDs.contains(word.id)
        return VStack(spacing: 10) {
            if said {
                Label("Laut gesagt", systemImage: "checkmark.circle.fill")
                    .font(.headline).foregroundStyle(DS.playMint)
                    .accessibilityIdentifier("arcade-said")
            } else {
                Text(sayItPrompt)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(DS.textPrimary)
                    .multilineTextAlignment(.center)
                micControls(done: false)
                if hidesAnswer(word) {
                    Button(game == .sound ? "Schreibweise zeigen" : "Satz zeigen") { peek = true }
                        .frame(minHeight: 44).foregroundStyle(DS.accentText)
                        .accessibilityIdentifier("arcade-peek")
                }
            }
        }.frame(maxWidth: .infinity)
    }

    private var sayItPrompt: String {
        switch game {
        case .sound: return "Sprich nach, was du gehört hast."
        case .builder: return peek ? "Jetzt sag den ganzen Satz laut." : "Jetzt ohne Vorlage: sag den Satz laut."
        default: return "Sag es einmal richtig laut."
        }
    }

    /// Mic button with live transcript. Listening ends by itself on a match.
    @ViewBuilder private func micControls(done: Bool) -> some View {
        if !done {
            Button { listening ? stopListening() : listen() } label: {
                Label(listening ? "Ich höre zu … Stopp" : "Sprechen", systemImage: listening ? "stop.circle.fill" : "mic.fill")
                    .font(.headline.bold()).foregroundStyle(listening ? DS.textPrimary : DS.playInk)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(listening ? DS.sprintColor.opacity(0.25) : DS.playMint, in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(PracticePressStyle()).accessibilityIdentifier("arcade-speak")
            if listening || !speech.transcription.isEmpty {
                Text(speech.transcription.isEmpty ? "…" : "„\(speech.transcription)“")
                    .font(.subheadline).foregroundStyle(DS.textSecondary).multilineTextAlignment(.center)
                    .environment(\.layoutDirection, language == "ar" ? .rightToLeft : .leftToRight)
            }
        }
    }

    /// "Weiter" is the main action once the word was said aloud; before that
    /// it stays available but quiet, so speaking is the obvious next step.
    private func nextButton(_ word: ArcadeWord, identifier: String) -> some View {
        let spoken = !asksToSpeak(word)
        return nextButton(spoken ? "Weiter" : "Ohne Sprechen weiter", primary: spoken, identifier: identifier) { advancePrompt() }
    }

    @ViewBuilder private func nextButton(_ title: String, primary: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        if primary {
            Button(title, action: action).buttonStyle(ArcadeActionStyle()).accessibilityIdentifier(identifier)
        } else {
            Button(title, action: action).frame(minHeight: 44).foregroundStyle(DS.textSecondary)
                .accessibilityIdentifier(identifier)
        }
    }

    private func selectTile(_ id: Int) {
        guard !checked, !selectedTiles.contains(id), tokens.contains(where: { $0.id == id }) else { return }
        selectedTiles.append(id)
    }
    private func chooseSwipe(_ choice: ArcadeWord, word: ArcadeWord) {
        guard responseID == nil else { return }
        heard = true; correctAnswer = choice.id == word.id
        chooseMeaning(choice, correct: word)
    }
    private func checkProduction(_ answer: String, word: ArcadeWord) {
        guard !checked else { return }
        answerFocused = false; checked = true
        correctAnswer = VocabularyArcade.accepts(answer, for: word)
        responseID = correctAnswer ? word.id : "incorrect"
        score.answer(id: word.id, correct: correctAnswer)
        if correctAnswer { CompletionFeedbackService.shared.playStepSuccess() }
        // Playing it now would hand over the sentence the learner is about to say.
        if !hidesAnswer(word) { speakAutomatically(word) }
    }
    private func revealAnswer(_ word: ArcadeWord) {
        guard !checked else { return }
        answerFocused = false; revealed = true; checked = true; correctAnswer = false
        responseID = "supported"
        score.answer(id: word.id, correct: false)
        if !hidesAnswer(word) { speakAutomatically(word, delay: .zero) }
    }

    private var result: some View {
        VStack(spacing: 20) {
            CompletionCelebration(title: "Yes! Runde geschafft!", detail: "\(words.count) Aufgaben geschafft.", symbol: "square.grid.2x2.fill")
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) { resultStats }
            } else {
                HStack(spacing: 20) { resultStats }
            }
            Text("Dein Spiele-Ergebnis bleibt von der regulären Wiederholung getrennt. Deine Wiederholungstermine bleiben erhalten.")
                .font(.caption).foregroundStyle(DS.textSecondary).multilineTextAlignment(.center)
            if let failure {
                Text(failure).font(.caption).foregroundStyle(DS.sprintColor)
                Button("Ergebnis erneut speichern") { saveResult() }
            }
            Button("Noch eine Runde") { restart() }.buttonStyle(ArcadeActionStyle()).accessibilityIdentifier("arcade-replay")
            Button("Für heute fertig") { dismiss() }.frame(minHeight: 44).foregroundStyle(DS.accentText)
                .accessibilityIdentifier("arcade-finish")
        }
    }

    @ViewBuilder private var resultStats: some View {
        stat("\(score.firstTry)/\(words.count)", "Beim ersten Versuch")
        stat("\(score.bestStreak)", "Beste Serie")
        if spokenWords > 0 { stat("\(spokenWords)", "Wörter laut gesagt") }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack { Text(value).font(.largeTitle.bold()).foregroundStyle(DS.accentText); Text(label).font(.caption).foregroundStyle(DS.textSecondary) }
            .frame(maxWidth: .infinity).padding().background(DS.surface1, in: RoundedRectangle(cornerRadius: 18))
    }

    private func load() {
        // Due words first, then current tutor material, then other active topics.
        let eligible = cards.filter { $0.phrase?.language?.code == language && ($0.phrase?.topics ?? []).contains(where: \.isActive) }
        func rank(_ card: StudyCard) -> Int {
            if card.hasBeenIntroduced && card.dueDate <= .now { return 0 }
            if (card.phrase?.topics ?? []).contains(where: \.isTutorFocusActive) { return 1 }
            return card.hasBeenIntroduced ? 2 : 3
        }
        var identities: [PersistentIdentifier: String] = [:]
        let candidates = eligible.shuffled().sorted { rank($0) < rank($1) }.compactMap { card -> ArcadeWord? in
            guard let phrase = card.phrase else { return nil }
            let id = identities[phrase.persistentModelID] ?? UUID().uuidString
            identities[phrase.persistentModelID] = id
            return ArcadeWord(id: id, source: phrase.sourceText,
                              target: phrase.targetText, alternatives: phrase.acceptedAlternatives)
        }
        pool = VocabularyArcade.unique(candidates, limit: 64)
        plan = VocabularyArcade.plan(from: candidates, mode: mode)
        prepareBoard(); loaded = true
    }

    private func prepareBoard() {
        selected = nil; mismatch = nil; promptIndex = 0
        rightOrder = board.shuffled(); preparePrompt()
    }
    private func preparePrompt() {
        responseID = nil; heard = false; revealed = false; peek = false
        checked = false; correctAnswer = false; selectedTiles = []; typedAnswer = ""; swipeOffset = 0
        speech.clearTranscription()
        guard let word = prompt else { choices = []; tokens = []; return }
        choices = VocabularyArcade.options(for: word, from: pool, count: game == .swipe ? 2 : 4)
        tokens = TileConstruction.tokens(for: word.target).shuffled()
        if tokens.count > 1 && tokens.map(\.id) == Array(0..<tokens.count) { tokens.reverse() }
        // Sound Hunt starts by listening, so play the word without a tap.
        if game == .sound { speakAutomatically(word, delay: .milliseconds(450)) }
    }
    private func match(_ word: ArcadeWord) {
        guard let id = selected, !score.resolved.contains(word.id), !score.resolved.contains(id), mismatch == nil else { return }
        let correct = id == word.id
        score.answer(id: id, correct: correct)
        if correct {
            selected = nil
            CompletionFeedbackService.shared.playStepSuccess()
            speakAutomatically(word)
        } else { mismatch = word.id }
    }
    private func play(_ word: ArcadeWord) {
        speechTask?.cancel()
        heard = true
        ReferenceAudioService.shared.play(text: word.target, locale: locale)
    }
    /// Reads the target word aloud once the success chime has had its moment,
    /// so every match or answer is also heard — no extra tap needed.
    private func speakAutomatically(_ word: ArcadeWord, delay: Duration = .milliseconds(220)) {
        guard autoSpeak else { return }
        speechTask?.cancel()
        speechTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            play(word)
        }
    }
    private func stopAudio() {
        speechTask?.cancel()
        speechTask = nil
        ReferenceAudioService.shared.stop()
        stopListening()
    }

    private func listen() {
        speechTask?.cancel()
        ReferenceAudioService.shared.stop()
        micNote = nil
        micTask?.cancel()
        micTask = Task { @MainActor in
            let allowed = await speech.requestAuthorization()
            guard !Task.isCancelled else { return }
            guard allowed else {
                micBlocked = true
                micNote = "Ohne Mikrofon geht’s auch – das Sprechen überspringen wir dann."
                return
            }
            if let pack = LanguagePack.configuration(for: language) { speech.setLocale(pack.speechLocale) }
            speech.clearTranscription()
            do { try speech.start() } catch {
                micBlocked = true
                micNote = "Spracherkennung gerade nicht verfügbar. Du kannst ohne Sprechen weiterspielen."
            }
        }
    }

    private func stopListening() {
        micTask?.cancel(); micTask = nil
        if speech.isRecording { speech.stop() }
    }

    private func heardSpeech(_ transcript: String) {
        guard listening, !transcript.isEmpty else { return }
        guard let word = prompt, !spokenIDs.contains(word.id), VocabularyArcade.heard(transcript, for: word) else { return }
        stopListening()
        creditSpoken(word)
        if game == .recall && !checked {
            // Said it from memory: the same credit as a correct typed answer.
            checked = true; correctAnswer = true; responseID = word.id
            score.answer(id: word.id, correct: true)
        }
        CompletionFeedbackService.shared.playStepSuccess()
        if game == .builder { speakAutomatically(word, delay: .milliseconds(400)) }
    }

    private func creditSpoken(_ word: ArcadeWord) {
        guard spokenIDs.insert(word.id).inserted else { return }
        spokenWords += SpokenWordTally.record(word.target)
    }
    private func chooseMeaning(_ option: ArcadeWord, correct word: ArcadeWord) {
        guard heard, responseID == nil else { return }
        stopAudio()
        responseID = option.id
        score.answer(id: word.id, correct: option.id == word.id)
        if option.id == word.id { CompletionFeedbackService.shared.playStepSuccess() }
        speakAutomatically(word)
    }
    private func advancePrompt() {
        guard let word = prompt, responseID != nil else { return }
        stopAudio()
        answerFocused = false
        // A corrected answer completes the activity, never becomes first-try credit.
        score.answer(id: word.id, correct: true)
        if promptIndex + 1 < board.count { promptIndex += 1; preparePrompt() } else { advanceBoard() }
    }
    private func advanceBoard() {
        guard boardDone else { return }
        if stage + 1 < stages { stage += 1; prepareBoard() }
        else { finished = true; saveResult(); CompletionFeedbackService.shared.playCompletion() }
    }
    private func saveResult() {
        guard !saved else { return }
        guard !settings.isEmpty else { failure = "Einstellungen nicht verfügbar. Bitte erneut versuchen."; return }
        do {
            try LearningActivityRecorder.record("arcade_completed", language: language, session: session,
                step: mode.rawValue, support: mode == .recall || mode == .mix ? "arcadePractice" : "recognition", context: context)
            saved = true; failure = nil
        } catch { context.rollback(); failure = "Ergebnis nicht gespeichert. Du kannst es erneut versuchen." }
    }
    private func restart() {
        stopAudio()
        session = UUID(); score = ArcadeScore(); stage = 0; finished = false; saved = false; failure = nil
        spokenIDs = []; spokenWords = 0
        load()
    }
}

private struct ArcadeActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline.bold()).foregroundStyle(DS.playInk)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(DS.playMint, in: RoundedRectangle(cornerRadius: 18))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
