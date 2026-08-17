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

Automated validation currently passes 75 tests on an iPhone 17 / iOS 26.5 simulator. Before a public release, the remaining gates are physical-device interruption and microphone testing, accessibility testing across the full device matrix, native-speaker review of Russian and Arabic content, and a measured external beta. These are release-validation tasks rather than unfinished core product architecture.

## Executive assessment

CueFlow has a strong and differentiated foundation: native SwiftUI, FSRS scheduling, private on-device speech and grading, an adult visual identity, and German-to-target-language production as its central learning direction.

The app currently feels less mature than the concept because the learning model, exercise modes, speech lifecycle, navigation, and content architecture do not yet form one dependable journey. The next releases should therefore prioritize correctness and coherence before adding more features or applying another visual reskin.

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

## Core issues to resolve

### 1. Exercise modes currently create independent learning histories

Each phrase receives a separate `StudyCard` for Üben, Wählen, Tippen, and Karten. Consequently, learning a phrase in one mode does not advance it in another, daily-new limits are fragmented, and progress counts are inflated.

**Target:** one scheduled memory per phrase or learning objective. Store exercise type on the attempt/review and let an exercise policy choose the appropriate presentation.

### 2. Arabic uses incompatible canonical representations

Arabic currently stores Latin transliteration as the graded target and Arabic script in the transliteration field, while ASR and TTS use an Arabic locale. Spoken recognition and grading can therefore compare different scripts, and TTS may receive Latin transliteration rather than Arabic.

**Target:** Arabic script is canonical. Transliteration is an optional scaffold. Normalization may accept configured aliases, but speech, TTS, display, and grading must agree on the canonical representation.

### 3. Practice is not a deterministic state machine

Delayed choice transitions, asynchronous grading, permission requests, and speech startup are not consistently cancelled or tied to the active card/session. A stale operation can update the UI or schedule after a mode, language, card, or screen change.

**Target:** a testable `PracticeSession` state machine with cancellable work, session/card identity guards, duplicate-submission protection, and explicit recovery states.

### 4. Persistence errors are hidden

Many writes silently discard errors, while store initialization failure terminates the app.

**Target:** atomic review/schedule updates, structured local diagnostics, visible retry paths, and a safe recovery/export experience when the store cannot open.

### 5. The tests miss the riskiest product behaviour

The domain tests cover grading, matching, scheduling, classification, and examples, but not the full practice lifecycle, speech permissions, backgrounding, language changes, settings dismissal, or migration.

**Target:** state-machine, integration, migration, accessibility, and UI tests complement the domain suite.

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

## Delivery plan

### Phase 0 — Product contract and baseline

**Duration:** 2–3 days

Define the primary user, session types, success measures, meaning of learned/mastered, and a complete screen/state inventory. Record baseline usability observations from physical-device sessions.

**Exit criterion:** every proposed feature can be evaluated against the speaking-first promise.

### Phase 1 — Correct the learning and language models

**Duration:** 1–2 weeks

- unify the schedule per phrase/learning objective;
- store exercise type as review metadata;
- migrate existing four-card histories without losing progress;
- make Arabic script canonical;
- introduce reusable language-pack configuration;
- pin FSRS;
- correct progress calculations.

**Exit criteria:** learning transfers across exercises; Arabic speech/display/grading agree; existing data migrates safely.

### Phase 2 — Make practice deterministic

**Duration:** 1–2 weeks

- extract the practice state machine;
- cancel stale grading, permission, delay, and speech work;
- guard transitions with session/card identity;
- prevent duplicate submission;
- make review and schedule persistence atomic;
- surface recoverable errors;
- add lifecycle and integration tests.

**Exit criterion:** rapid tapping, dismissal, backgrounding, and language changes cannot corrupt progress or show stale results.

### Phase 3 — Install native navigation

**Duration:** approximately 1 week

- create Heute, Bibliothek, and Fortschritt tabs;
- move Settings to a standard secondary entry;
- move Sprint to Heute;
- adapt navigation for iPad;
- preserve independent destination state.

**Exit criterion:** a new user identifies the primary action within three seconds.

### Phase 4 — Redesign the core session

**Duration:** approximately 2 weeks

- simplify active-session chrome;
- introduce automatic exercise selection;
- add tile construction;
- improve recording and processing states;
- add silence detection and immediate retry;
- compact feedback;
- make sentence reinforcement selective;
- add pause, resume, and safe exit.

**Exit criteria:** mature sessions are speaking-heavy, ordinary feedback does not require scrolling, and every error has an obvious recovery action.

### Phase 5 — Rebuild onboarding and first session

**Duration:** approximately 1 week

- replace explanation-heavy pages with benefit, language/purpose, first spoken success, and personalization;
- request permissions in context;
- guarantee valid starter content;
- enter a real short session directly.

**Exit criterion:** a new user speaks a phrase within 60 seconds.

### Phase 6 — Turn content into journeys

**Duration:** 1–2 weeks

- create practical topic missions and suggested progression;
- support tutor-lesson missions;
- separate learning from content management;
- add useful level, dialect/register, and content-quality metadata.

**Exit criterion:** users can answer “What should I learn next?” without managing activation switches.

### Phase 7 — Make progress and engagement meaningful

**Duration:** approximately 1 week

- redesign recap and Progress around productive recall and spoken output;
- implement truthful event-based combos and records;
- integrate Sprint discovery and recap;
- surface improving difficult phrases and topic capabilities.

**Exit criterion:** every progress statement is accurate, understandable, and tied to a learner capability.

### Phase 8 — Visual and platform polish

**Duration:** 1–2 weeks

- unify components and surfaces;
- refine typography, shadows, haptics, and restrained sound;
- complete light/dark, Dynamic Type, VoiceOver, contrast, RTL, iPad, and orientation review;
- introduce String Catalogs.

**Exit criterion:** all primary flows pass the defined iPhone/iPad and accessibility matrix.

### Phase 9 — Quality and external beta

**Duration:** 2–3 weeks

Add automated coverage for onboarding, session completion, permission denial, interruption, settings persistence, imports, migration, recovery, and Russian/Arabic representations. Run separate Russian and Arabic physical-device betas with native-speaker review.

**Release criteria:** no known progress-loss bugs; speech failure always has a useful fallback; the main session is understandable without explanation; users voluntarily complete repeated sessions; native speakers approve bundled content.

## Dependency order

```text
Product contract
→ learning and language models
→ deterministic session engine
→ navigation
→ core practice UX
→ onboarding
→ topic journeys
→ progress and engagement
→ visual/platform polish
→ beta validation
```

The first major milestone should be a flawless Russian journey from **Heute → spoken answer → useful correction → meaningful recap**. Arabic and additional languages should then plug into that proven flow through the language-pack architecture.
