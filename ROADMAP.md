# CueFlow — Release Roadmap

The [October learning experience specification](LEARNING_EXPERIENCE_IMPLEMENTATION_SPEC.md) contains the next proposed implementation phases and newly confirmed defects. The shipped-feature inventory below does not imply those defects are resolved.

**Updated:** 3 October 2026

**Current train:** 1.0, build 56 development preview (not uploaded)

Build 56 adds an illustrated Today → story → completion loop, a shared story passport, distinct participation/unaided/delayed-recall markers, scene palettes and a quieter home hierarchy. Research rationale, reward rules and evaluation boundaries are documented in [the visual gamification contract](LEARNING_EXPERIENCE_IMPLEMENTATION_SPEC.md#18-build-56--illustrated-story-loop-and-evidence-safe-gamification). Engagement improvements remain hypotheses to test with learners.

Build 55 connects stories to canonical vocabulary/FSRS, persists bounded card plans and unconfirmed attempts, adds independent journal records, optional calibration, selected study days, tutor shortfalls, evidence-led Progress, permanent earned badges, contextual reminders, and an opt-in local comparison. See the [current acceptance ledger](LEARNING_EXPERIENCE_IMPLEMENTATION_SPEC.md#16-build-55-roadmap-implementation) for exact boundaries; this is not a claim that every research/release criterion is complete.
**Product:** a private, native iOS speaking-first language coach for German speakers learning Russian or Arabic.

## Product promise

CueFlow trains the direction that recognition-heavy apps often neglect:

```text
German intent → retrieve the target-language expression → say it aloud → use it in context
```

The scheduler owns one memory per phrase. Recognition, tiles, typing, speaking, Sprint, difficult-practice, and conversation are presentations of that memory—not separate progress silos.

## Implemented on `main`

### Learning and content

- FSRS-6 scheduling, pinned to an exact dependency revision;
- speaking-first adaptive sessions with choice, tiles, typing, speech, reveal, retry, and fallback states;
- a reading pass at computed *i+1*: sentences are scored against the phrases this learner has actually stabilised (FSRS stability ≥ 7 days) and only those with at most one unfamiliar content word are shown, so the comprehensibility threshold is a per-learner computation rather than an editorial guess;
- dictation in the listening studio alongside meaning-recognition, still unscored;
- new bundled cards are introduced by CEFR band and corpus frequency instead of insertion order, while learner-added and tutor content keeps its newest-first priority;
- chronic leeches (five or more lifetime lapses) join difficult-practice even when they were quiet this week, and are surfaced for rewording rather than suspended;
- suppletive and stem-changing forms enumerated for the shipped corpus (`IrregularForms`), which takes gap-fill coverage of the Russian sentences to 99.9 % and lets a stabilised headword resolve its irregular forms while reading;
- a "Lücken" gap-fill mode derived from the bundled example sentences: the learner supplies the surface form the sentence requires, the headword is shown only when it differs from the answer, and the item is refused outright when the form cannot be located confidently (stem changes, vowel alternations, Arabic non-concatenative morphology) rather than guessed;
- Russian and Arabic language packs with canonical Arabic script, RTL presentation, locale-specific TTS/ASR, and optional transliteration;
- 60-second spoken Sprint, difficult-this-week practice, 3/7/15-minute session defaults, and universal guided Russian/Arabic role-play that does not require Apple Intelligence;
- evidence-based speech feedback using recognized words, confidence, and hesitation signals, with slow playback and one conservative immediate retry—explicitly not presented as phoneme scoring;
- an unscored five-item listening/shadowing studio, recorded-reference fallback architecture, Arabic enhanced-voice selection, and separate step/completion sound signatures;
- adaptive scaffolding after repeated difficulty, curriculum prerequisites and recommendations, and learner-facing structural error-pattern insights;
- a capability-path map, evidence-based unlocks, three weekly missions, and five collectible milestones tied to productive recall rather than arbitrary points;
- six Russian and six Arabic guided situations; shopping, hotel, and pharmacy are longer draft scenarios, and shopping contains authored answer branches;
- bundled A1 Russian and Arabic content, bundled OpenRussian material, tutor PDF import, paste/manual entry, topic journeys, and scenario collections;
- phrase-level CEFR, register, dialect, provenance, editorial/native-review status, structural content linting, and an explicit review queue;
- compact corrections, optional detail, contextual example sentences, and capability-based session recaps.

### Motivation without dark patterns

- productive-output goals, spoken-word totals, fluency trend, difficult-item recovery, personal bests, event-based milestones, and calm comeback moments;
- a restrained completion chime and haptic feedback that respect the sound toggle, Reduce Motion, and the device's interaction context;
- weekly reflection based on real activity, plus an opt-in daily reminder;
- no hearts, energy gates, streak-loss threats, public leaderboards, or random rewards disconnected from learning.

### Native platform quality

- SwiftUI/SwiftData app with native three-tab navigation, one shared page canvas, toolbar placement, adaptive content width, spacing rhythm, and continuous card geometry;
- shared main-screen section hierarchy, a compact secondary-activity launcher, actionable progress recommendations, and exact rescheduling for ongoing tutor lessons;
- language-aware learning-card typography with modern rounded Cyrillic and native Arabic shaping, while reserving serif display type for editorial headings;
- immediate tab selection with revisioned, background-precomputed progress dashboards, retained chart state, and on-demand phrase search;
- every primary and pushed screen reads a precomputed snapshot rather than deriving from live queries in `body`, and the practice loop resolves tutor priority once per pass instead of once per card;
- language-scoped Fortschritt figures and a Bibliothek management filter that follows the active language;
- a first-class Tutor Focus with multiple concurrent lessons, next-lesson dates, automatic daily preparation pacing, explicit completion, migration of existing tutor imports, and immediate topic-scoped practice;
- account-aware asynchronous SwiftData startup, private CloudKit sync when available, local fallback, and an in-memory recovery session if persistent storage cannot open;
- versioned full JSON backup and idempotent restore, including settings, topics, phrases, schedule, and review history;
- Home Screen and Lock Screen widgets with due count and `cueflow://practice` deep link, plus Siri/App Shortcuts for practice and conversations;
- MetricKit diagnostics with a privacy-filtered in-app problem report;
- String Catalog, dark mode, Dynamic Type, RTL, VoiceOver labels, Reduce Motion behavior, scene restoration, iPad sidebar adaptation, multitasking, and all supported orientations;
- deterministic launch overrides and an XCTest UI smoke suite that waits for the primary screen before scrolling it, so a slow store open no longer reads as a failure.
- executable quality-gate and non-overwriting archive scripts, with a 14% app-target coverage regression floor.

## Release gates

These require a person, Apple account, or physical hardware and must not be simulated or claimed as complete in code:

1. Test microphone, interruptions, Bluetooth routes, Arabic and Russian offline speech models, haptics, and sound on at least two physical iPhones.
2. Run VoiceOver, Switch Control, Bold Text, Reduce Motion, Increase Contrast, and the largest accessibility text sizes on device.
3. Have Russian and Arabic native speakers review the bundled starter packs; record decisions through the in-app content-quality workflow.
4. Publish the privacy policy at a stable public URL and supply a monitored support email.
5. Capture final App Store screenshots from the submitted build and complete external TestFlight with 5–15 representative learners.
6. Review MetricKit reports and learner feedback, fix launch blockers, then submit the exact tested archive.

The detailed device matrix, store copy, privacy draft, and screenshot plan are in [`RELEASE_READINESS.md`](RELEASE_READINESS.md).

## Post-1.0 candidates

Only prioritize these after beta evidence:

- morphology (case and aspect) as a first-class content type;
- general-purpose Russian lemmatisation, if content ever stops being a closed corpus. `NLTagger` returns no lemmas for Russian or Arabic and a Snowball-style stemmer resolved only 7 of 16 stem-changing pairs, so anything beyond the shipped vocabulary would need a real inflection dictionary;
- learner-authored conversation scenarios and true phoneme-level pronunciation feedback;
- English UI and additional language packs;
- Apple Watch;
- audio recorded by native speakers for the highest-use phrases;
- OCR for image-only tutor documents;
- adaptive FSRS weight refitting from an explicitly exported, privacy-preserving dataset.

## Operating principles

1. Successful unaided spoken recall is the north-star outcome.
2. Generated content never silently becomes trusted curriculum or scheduling evidence.
3. Every permission, speech, persistence, and model failure has a useful fallback.
4. Motivation reflects real learning evidence; practice is never withheld.
5. Language behavior belongs in a language pack, not scattered conditionals.
6. Cloud sync is Apple-account-managed convenience, never a prerequisite for use.
7. A release is complete only after automated checks, physical-device checks, content review, and external beta.
