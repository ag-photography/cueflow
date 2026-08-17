# CueFlow Product, UI/UX, and Reliability Plan

**Status:** Core implementation complete; release validation in progress

**Scope:** Russian, Arabic, and a language-pack foundation for future target languages

**Product promise:** Help German-speaking adults retrieve and speak useful target-language expressions, rather than merely recognize translations.

## Implementation status — 17 August 2026

Implemented on `main`:

- one shared FSRS schedule per phrase, with preserved historical reviews;
- canonical Arabic script, RTL-aware presentation, and reusable language-pack configuration;
- guarded practice interactions, stale-work cancellation, atomic review persistence, and recoverable errors;
- native Heute, Bibliothek, and Fortschritt navigation with an adaptive focused session;
- automatic speaking-first exercise selection, productive word-tile fallback, pause/exit, and silence completion;
- four-beat onboarding with an in-context first spoken success;
- learner-facing missions separated from advanced content management;
- Sprint preparation/countdown, relevant learned-content pool, skipped-answer reveal, and honest recap;
- productive-output progress, capability-based session recap, and event-based—not random—milestones;
- truthful daily quests, scenario collections, capability paths, personal records, and measured comeback moments;
- tactile word-tile motion plus a restrained completion chime and success haptics;
- immediate settings persistence, recoverable content saves, confirmed destructive actions, and a German-source String Catalog;
- an in-memory safe-session fallback when the persistent store cannot open, replacing an ordinary launch crash with an explicit data-retention warning;
- dark-mode design tokens, RTL handling, Dynamic Type support, VoiceOver labels, Reduce Motion handling, and iPad content-width adaptation.

Automated validation currently passes 117 named unit/performance tests (127 executions) and eight end-to-end UI tests on an iPhone 17 / iOS 26.5 simulator, plus a clean iPad Pro 13-inch launch and visual check. The app target has a 14% CI regression floor and measured 14.51% line coverage in build 43; the domain-heavy test target measured 99.41%. Before a public release, the remaining gates are physical-device interruption and microphone testing, accessibility testing across the full device matrix, native-speaker review of Russian and Arabic content, and a measured external beta. These are release-validation tasks rather than unfinished core product architecture.

## Executive assessment

CueFlow has a strong and differentiated foundation: native SwiftUI, FSRS scheduling, private on-device speech and grading, an adult visual identity, and German-to-target-language production as its central learning direction.

The original audit found that the concept was stronger than the journey: learning histories, speech lifecycle, navigation, and content management did not yet form one dependable whole. The implementation on `main` now resolves those structural findings. Release work should therefore protect coherence and validate it with real devices, native speakers, and learners rather than resume undirected feature expansion.

The target experience is:

```text
Open CueFlow
→ see exactly what to do today
→ start with one tap
→ speak frequently
→ understand each correction immediately
→ finish with evidence of improved ability
```

## Product principles

1. **Production before recognition.** Mature material should increasingly require unaided German-to-target-language speech.
2. **One memory, varied exercises.** Exercise format is a presentation strategy, not a separate learning history.
3. **One obvious next action.** The learner should not have to configure the algorithm before practising.
4. **Feedback must be truthful.** Praise, combos, mastery, and records must correspond to measured events.
5. **Fast recovery.** Permission, recognition, persistence, and grading failures must always have a clear fallback.
6. **Calm, not inert.** Avoid manipulative gamification while using pace, progress, contextual variety, and meaningful completion to sustain engagement.
7. **Native by default.** Follow standard Apple navigation, accessibility, adaptive-layout, state-restoration, and error-recovery conventions.
8. **Language packs, not language conditionals.** Script, direction, speech locales, normalization, transliteration, and content policy belong in a reusable language definition.

## Primary success measures

The north-star measure is **successful unaided spoken recalls**.

Supporting measures:

- spoken words and minutes;
- phrases produced without scaffolding;
- response latency and fluency trend;
- difficult phrases that later become successful;
- session completion and voluntary repeat sessions;
- recognition correction and speech-fallback rates;
- progress or review loss incidents: target zero.

Activity counts and streaks are supporting signals, not the definition of learning.

## Original core issues and resolution

### 1. Independent learning histories — resolved

Each phrase receives a separate `StudyCard` for Üben, Wählen, Tippen, and Karten. Consequently, learning a phrase in one mode does not advance it in another, daily-new limits are fragmented, and progress counts are inflated.

**Resolution:** one canonical card is retained per phrase; legacy histories merge without losing reviews, and exercise type is stored on the review attempt.

### 2. Incompatible Arabic representations — resolved

Arabic currently stores Latin transliteration as the graded target and Arabic script in the transliteration field, while ASR and TTS use an Arabic locale. Spoken recognition and grading can therefore compare different scripts, and TTS may receive Latin transliteration rather than Arabic.

**Resolution:** Arabic script is canonical, transliteration is an optional scaffold, and display, speech, TTS, grading, import, and backup share the same representation.

### 3. Non-deterministic practice lifecycle — resolved

Delayed choice transitions, asynchronous grading, permission requests, and speech startup are not consistently cancelled or tied to the active card/session. A stale operation can update the UI or schedule after a mode, language, card, or screen change.

**Resolution:** interaction tokens, cancellable tasks, card/session identity checks, guarded persistence, duplicate-submission protection, and explicit fallbacks govern the active session.

### 4. Hidden persistence errors — resolved

Many writes silently discard errors, while store initialization failure terminates the app.

**Resolution:** review/schedule updates save together, write failures surface, diagnostics remain local, startup is asynchronous, and store failure opens an explicit safe session with export/restore paths.

### 5. Missing high-risk automated coverage — substantially resolved

The domain tests cover grading, matching, scheduling, classification, and examples, but not the full practice lifecycle, speech permissions, backgrounding, language changes, settings dismissal, or migration.

**Resolution:** domain, persistence, migration, backup, startup, engagement, widget snapshot, and UI smoke tests now complement one another. Physical microphone, audio-route, interruption, and assistive-technology validation remains a human release gate.

### 6. Builds must remain reproducible

FSRS previously followed its `main` branch. It is now pinned to the exact validated revision `a4ebe3a1d167fea63b75770cddf781bb78a9f768`.

**Ongoing rule:** update the exact revision intentionally and rerun the complete scheduling and migration suite.

## Target information architecture

Use a native `TabView` with three primary destinations:

1. **Heute** — recommended session, quick Sprint, current mission, concise progress.
2. **Bibliothek** — learner-facing topic journeys and access to content management.
3. **Fortschritt** — productive-recall, speaking, fluency, and consistency evidence.

Settings belongs behind a standard toolbar/profile entry. On iPad, the structure adapts to a sidebar or `NavigationSplitView` while preserving tab state.

### Heute

The default screen answers three questions immediately:

- What should I do?
- How long will it take?
- Why is this the right practice now?

Example:

```text
Guten Abend
12 Wiederholungen · 5 neue Ausdrücke
Etwa 7 Minuten

[ Weiterlernen ]

60-Sekunden-Sprint · Bestleistung 14
Aktuelle Mission · Im Café
```

## Target learning progression

The learner experiences increasing independence rather than choosing scheduling silos:

```text
Hear and understand
→ choose the meaning
→ arrange target-language tiles
→ produce from a German cue
→ speak without support
→ use the phrase in a short exchange
```

The scheduler selects the memory. A separate exercise policy selects the interaction based on maturity, recent errors, environment, speech availability, and session variety.

Dedicated typing, cards, and Sprint drills may remain available, but all reinforce the same underlying memory.

## Target practice experience

### Session entry

Offer understandable durations rather than only a fixed card count:

- Schnellrunde — approximately 3 minutes;
- Tägliche Einheit — approximately 7 minutes;
- Intensiv üben — approximately 15 minutes.

### Active-session chrome

Show only:

- close or pause;
- progress such as “4 von 12”;
- an optional audio/session menu.

Remove global utilities and the four-way mode selector from the active exercise.

### Prompt

Use a small instruction, a large German cue, one interaction area, one primary action, and one low-emphasis escape action. Topic labels appear only when they provide useful context.

### Speech interaction

The state must be unambiguous:

```text
ready
→ requesting permission
→ listening
→ processing
→ result
→ retry or continue
```

Preferred behaviour:

- one tap to begin;
- visible listening level;
- automatic completion after silence;
- visible Stop fallback;
- immediate retry;
- automatic non-speaking fallback when unavailable or denied.

### Feedback

Default feedback is compact and actionable:

```text
Fast
Я хотел бы кофе.
хотела → хотел

[ Noch einmal sagen ] [ Weiter ]
```

Detailed character analysis remains optional. Recognition correction should be described explicitly, for example “Spracherkennung korrigieren,” rather than as a generic claim of being right.

A mistake should normally receive one immediate retry and then be resurfaced later in the session.

### Contextual reinforcement

“Sag es im Satz” remains valuable but is used selectively:

- after an important new expression;
- after a meaningful error;
- at the end of a topic mission;
- when context adds more value than another isolated repetition.

It should not routinely double the number of screens for every young card.

### Session recap

Show capability and output, not only accuracy:

```text
Heute gesprochen
18 Antworten · 74 Wörter

Neu abrufbar
„Ich hätte gern …“
„Wie komme ich zum …?“

Noch unsicher
2 Ausdrücke kommen morgen wieder
```

## Onboarding redesign

Keep onboarding to four concise beats:

1. **Promise:** explain spontaneous retrieval and speaking.
2. **Language and purpose:** choose target language and motivation.
3. **First success:** hear and say one useful phrase immediately.
4. **Personalize today:** choose a starter topic and session duration, then begin a real session.

Request microphone permission only at the first speaking action, immediately after explaining the benefit. Skip actions must be contextual and must never leave the learner with no active content.

The first screen should sell the positive benefit rather than focus on the absence of mascots or “Schnickschnack.”

## Sprint redesign

Sprint becomes a visible card on Heute rather than an icon-only header action.

Required changes:

- prepare authorization and recognition before starting the timer;
- show a short countdown;
- stop or exit cleanly when speech is unavailable;
- keep the pool within learned/currently relevant content;
- briefly reveal and pronounce skipped answers;
- recap hesitant and skipped phrases;
- keep Sprint outside FSRS while sharing speaking-output metrics.

## Library and topic journeys

Separate learner-facing progression from advanced content administration.

### Learn

Show practical missions such as:

- Begrüßung;
- Im Café;
- Unterwegs;
- Familie;
- Small talk;
- Tutor lesson: 14 August.

Each mission communicates the outcome, estimated effort, productive mastery, and a clear practice action.

### Manage content

Place imports, manual phrase editing, bulk activation, topic editing, and diagnostics in a secondary management area. Confirm destructive actions when they affect meaningful user-created content.

## Progress redesign

Recommended hierarchy:

1. spoken output today and this week;
2. phrases produced unaided;
3. current conversational capabilities;
4. difficult expressions improving;
5. practice consistency;
6. technical SRS counts, where useful.

Do not label FSRS `review` state as “mastered.” Streak remains available but no longer dominates the screen.

All celebrations must be event-based: an actual consecutive-recall run, real personal best, completed mission, improved response time, or first successful spoken sentence. Remove random claims such as “Drei am Stück” when no such sequence was measured.

## Visual and Apple-platform quality bar

- Preserve the cream/teal identity and use serif typography selectively for prompts and meaningful moments.
- Reduce oversized display type where it pushes functional content below the fold.
- Prefer spacing, restrained material, and subtle separation over heavy glow and shadow.
- Unify Practice, Library, Settings, and Progress under one surface/component system.
- Add text labels where icon meaning is not immediately obvious.
- Meet contrast requirements for secondary text on cream surfaces.
- Never use color as the only feedback channel.
- Save settings immediately or provide explicit Save/Cancel behaviour; swipe dismissal must not silently discard changes.
- Support iPad with adaptive composition rather than a stretched portrait layout.
- Add String Catalogs before further UI-language expansion.
- Test true Arabic RTL and mixed German/Arabic layout once Arabic script is canonical.
- Test Dynamic Type at accessibility sizes without relying primarily on growth caps.
- Preserve VoiceOver order, clear labels, Reduce Motion, and minimum touch targets.

## Delivery status

| Phase | Outcome | Status |
|---|---|---|
| 0. Product contract | speaking-first promise, success measures, screen/state inventory | Complete |
| 1. Learning/language model | shared memories, migration, canonical Arabic, language packs, pinned FSRS | Complete |
| 2. Deterministic practice | guarded async lifecycle, atomic reviews, visible recovery | Complete |
| 3. Native navigation | Heute, Bibliothek, Fortschritt, secondary Settings, adaptive width | Complete |
| 4. Core session | automatic exercise policy, tiles, speech states, fallback, retry, recap | Complete |
| 5. Onboarding | concise promise, contextual speech success, personalization | Complete |
| 6. Content journeys | missions, scenarios, imports, metadata, content-quality review | Complete |
| 7. Meaningful engagement | productive progress, Sprint, difficult practice, recap, records | Complete |
| 8. Platform polish | coherent design system, sound/haptics, RTL, String Catalog, widget, diagnostics | Complete in code; device matrix pending |
| 9. Quality and beta | automation, physical-device audit, native review, external beta | Automation complete; human gates pending |

## Release dependency order

```text
Current main branch
→ complete physical-device matrix
→ Russian and Arabic native-speaker review
→ external TestFlight observations
→ fix release blockers and rerun regression
→ capture final store assets from the tested archive
→ App Store submission
```

The detailed remaining work is operational, not speculative. It lives in [`RELEASE_READINESS.md`](RELEASE_READINESS.md); no repository plan should mark those human checks complete without evidence.
