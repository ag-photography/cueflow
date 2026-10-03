# CueFlow

CueFlow is a privacy-first native iOS language coach for German speakers learning **Russian** or **Arabic**. Its core loop trains productive recall: see a German intent, retrieve the target-language expression, and say it aloud.

## Highlights

- adaptive FSRS-6 sessions that progress from recognition to tiles, unaided production, and speech;
- a preview collection of six Russian and three Modern Standard Arabic mini-stories, with saved position, optional quiet typing, and next-day/later recall checks;
- a reading pass that selects bundled sentences at *i+1* from the learner's own FSRS state — at most one unfamiliar word — plus dictation in the listening studio;
- a gap-fill ("Lücken") mode built from the bundled example sentences, which asks for the inflected form a sentence actually needs rather than the dictionary form the flashcard taught;
- on-device Russian and Arabic speech recognition, speech synthesis, grading, and optional Apple Intelligence assistance;
- focused 3/7/15-minute sessions, difficult-this-week practice, a 60-second spoken Sprint, and guided Russian/Arabic role-plays on every supported device;
- honest speech-recognition evidence, slow reference playback, immediate retry, adaptive scaffolding, curriculum recommendations, and recurring learning-pattern insights;
- an evidence-based capability path with unlocks, weekly missions, collectible milestones, and no artificial currency or practice gates;
- a five-item listening and shadowing studio with normal/slow playback, bounded recording, and explicit non-diagnostic feedback;
- six Russian and six Arabic guided situations, including longer shopping, hotel, and pharmacy drafts with authored response branches;
- practical topic journeys, curated starters, tutor imports, phrase metadata, and an editorial/native-speaker review queue;
- persistent Tutor Focus for current or past lessons, per-deadline introduction pacing, and reserved slots inside bounded practice rounds;
- progress centered on successful recalls, spoken output, recovery, and fluency—not hearts or streak anxiety;
- private CloudKit sync when available, reliable local fallback, complete JSON backup/restore, widgets, Siri/App Shortcuts, and MetricKit diagnostics;
- VoiceOver-aware, Dynamic Type, dark mode, Reduce Motion, RTL Arabic, and adaptive iPhone/iPad layout.

CueFlow has no account system, ads, third-party tracking, server-side analytics, subscription, or practice gate. Story lifecycle events are stored locally (90-day raw-event retention); aggregate sharing is explicit. CloudKit uses the learner's Apple account and the app remains useful offline and without iCloud.

The October story loop is a **development preview**, not proof of better retention or free-speaking proficiency. Build 55 connects stories to canonical vocabulary and its FSRS schedule, preserves card-round/attempt checkpoints, and saves independent journal fragments. Optional calibration, study-day pacing, delayed-recall examples, and a local opt-in comparison are available. Build 56 adds native illustrated scenes and a story passport: participation collects a postcard, while unaided and seven-day retrieval have separate evidence-based markers. No streak-loss penalties or practice locks are introduced. Content review, physical-device checks, multi-device behavior, and remaining acceptance work are tracked in [the implementation specification](LEARNING_EXPERIENCE_IMPLEMENTATION_SPEC.md#16-build-55-roadmap-implementation).

## Stack

| Area | Technology |
|---|---|
| UI | SwiftUI |
| Persistence | SwiftData with optional private CloudKit |
| Scheduling | FSRS-6 (`swift-fsrs`, exact pinned revision) |
| Speech | `SFSpeechRecognizer`, `AVSpeechSynthesizer` |
| Optional AI | Apple Foundation Models on supported iOS 26 devices |
| Diagnostics | MetricKit, locally summarized |
| Widgets | WidgetKit with App Group snapshot |
| Deployment target | iOS 18.0 |
| Project generation | XcodeGen |

## Build

The generated `.xcodeproj` is intentionally not committed. [`project.yml`](project.yml) is the source of truth.

```sh
brew install xcodegen
xcodegen generate
xcodebuild build -scheme LanguageLearning \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

## Test

The scheme contains unit and UI test targets and gathers coverage:

```sh
xcodebuild test -scheme LanguageLearning \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

The simulator suite covers domain, persistence, migrations, backup, launch recovery, engagement selection, notification summaries, widget snapshots, primary navigation, large text, and Arabic configuration. Microphone quality, audio routes, offline speech models, haptics, and interruption handling still require physical-device validation.

Run the complete local quality gate, including the current app-coverage regression floor, with `ci_scripts/run_quality_gate.sh`. `ci_scripts/create_release_archive.sh` creates a non-overwriting signed archive when the Apple signing environment is available.

## Structure

```text
LanguageLearning/
  App/             startup, navigation, design system
  Domain/          grading, scheduling, exercises, engagement, conversation
  Features/        onboarding, today, practice, library, progress, settings
  Persistence/     SwiftData models, bootstrap, seed data, backup
  Services/        speech, audio, notifications, sync status, widgets, diagnostics
  Shared/          app/widget shared value types
CueFlowWidgets/    WidgetKit extension
LanguageLearningTests/
LanguageLearningUITests/
```

See [`LEARNING_EXPERIENCE_IMPLEMENTATION_SPEC.md`](LEARNING_EXPERIENCE_IMPLEMENTATION_SPEC.md) for the October learning/engagement audit and developer-ready backlog. [`PRODUCT_UX_REMEDIATION_PLAN.md`](PRODUCT_UX_REMEDIATION_PLAN.md) preserves the earlier audit and architecture, [`ROADMAP.md`](ROADMAP.md) tracks shipped work, and [`RELEASE_READINESS.md`](RELEASE_READINESS.md) lists the human release gates.

## License

All rights reserved unless a license is added later.
