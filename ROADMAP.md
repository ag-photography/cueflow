# CueFlow — Release Roadmap

**Updated:** 17 August 2026

**Current train:** 1.0, build 47
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

- SwiftUI/SwiftData app with native three-tab navigation and adaptive content width;
- immediate tab selection with revisioned, background-precomputed progress dashboards, retained chart state, and on-demand phrase search;
- a first-class Tutor Focus with multiple concurrent lessons, next-lesson dates, automatic daily preparation pacing, explicit completion, migration of existing tutor imports, and immediate topic-scoped practice;
- account-aware asynchronous SwiftData startup, private CloudKit sync when available, local fallback, and an in-memory recovery session if persistent storage cannot open;
- versioned full JSON backup and idempotent restore, including settings, topics, phrases, schedule, and review history;
- Home Screen and Lock Screen widgets with due count and `cueflow://practice` deep link, plus Siri/App Shortcuts for practice and conversations;
- MetricKit diagnostics with a privacy-filtered in-app problem report;
- String Catalog, dark mode, Dynamic Type, RTL, VoiceOver labels, Reduce Motion behavior, scene restoration, iPad sidebar adaptation, multitasking, and all supported orientations;
- deterministic launch overrides and an XCTest UI smoke suite.
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
