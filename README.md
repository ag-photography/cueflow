# CueFlow

A privacy-first, on-device language-learning app for German speakers learning **Russian** (and **Arabic**). Built with SwiftUI + SwiftData, scheduled with FSRS-6, graded entirely on-device. No accounts, no server, no tracking — install and use.

> **Status:** v1.0 build 38 — Phase A complete, on TestFlight (personal). See [`ROADMAP.md`](ROADMAP.md) for the path to App Store.

---

## What it does

- **Speaking-first practice** — a smart-mixed "Üben" loop that varies the exercise by card maturity: new cards → multiple-choice recognition, mature cards → *speak the answer aloud* (on-device ASR), no keyboard. Explicit "Tippen" (typing) and "Karten" (flip) modes too.
- **Sprint** — a 60-second hands-free fluency round: German prompts come fast, you say the translation aloud, on-device speech recognition auto-advances on a close-enough match. Scored on volume, outside the spaced-repetition schedule.
- **Spaced repetition** — [FSRS-6](https://github.com/open-spaced-repetition/swift-fsrs) scheduling.
- **On-device grading** — three tiers: exact/fuzzy matching, a normalization-aware grader, and an opt-in Apple Foundation Models judge (iOS 26).
- **On-device speech** — TTS (with `ru-RU` / `ar-SA` voices) and ASR (`SFSpeechRecognizer`).
- **Content included** — curated Russian + Arabic A1 starters and ~1700 OpenRussian.org A2/B1/B2 phrases, all bundled. Plus tutor-PDF import with semantic auto-classification.
- **Reflection, not manipulation** — streaks, milestones, and a "Sprechen" scoreboard (words spoken, fluency trend) — but **no** streak-panic, hearts/lives, leaderboards, or mascots. The audience is adults with real goals.

## Design principles

- **Free.** No IAP, no subscription.
- **Self-contained & private.** No accounts, no analytics, no telemetry-to-server. SwiftData local store; sync via CloudKit/iCloud (Apple end-to-end encrypted).
- **On-device only.** Grading, speech, and scheduling all run locally.
- **German UI** for v1 (English deferred). Content is language-agnostic — the target language is derived from settings, never hardcoded.

## Tech stack

| | |
|---|---|
| UI | SwiftUI |
| Persistence | SwiftData (+ CloudKit, planned) |
| Scheduling | FSRS-6 (`swift-fsrs`) |
| Speech | `AVSpeechSynthesizer` (TTS), `SFSpeechRecognizer` (ASR) |
| Optional grading | Apple Foundation Models (`LanguageModelSession`, iOS 26) |
| Deployment target | iOS 18.0 |
| Project generation | [XcodeGen](https://github.com/yonaskolb/XcodeGen) |

## Build & run

The `.xcodeproj` is **not committed** — it's generated from [`project.yml`](project.yml) (the source of truth). Generate it, then build:

```sh
brew install xcodegen      # once
xcodegen generate          # creates LanguageLearning.xcodeproj
open LanguageLearning.xcodeproj
```

Or from the command line:

```sh
xcodegen generate
xcodebuild -scheme LanguageLearning \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Tests

Domain logic (grading, FSRS scheduler policy, import classifier, Sprint matcher) is unit-tested in [`LanguageLearningTests`](LanguageLearningTests). Run with ⌘U in Xcode or:

```sh
xcodebuild test -scheme LanguageLearning \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Project layout

```
LanguageLearning/
  App/            App entry, RootView, design system
  Domain/         Grading, scheduling, exercises, classification (no UI)
  Features/       SwiftUI screens (Practice, Library, Profile, Onboarding)
  Persistence/    SwiftData models, schema, seed data
  Services/       Speech (TTS/ASR), notifications
  Resources/      Bundled vocab
LanguageLearningTests/   Domain unit tests
ci_scripts/              Xcode Cloud post-clone hook (runs xcodegen)
project.yml              XcodeGen project definition (source of truth)
ROADMAP.md               Build history + path to launch
```

## License

No license yet — all rights reserved by default until one is added.
