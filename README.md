# CueFlow

CueFlow is a privacy-first native iOS language coach for German speakers learning **Russian** or **Arabic**. Its core loop trains productive recall: see a German intent, retrieve the target-language expression, and say it aloud.

## Highlights

- adaptive FSRS-6 sessions that progress from recognition to tiles, unaided production, and speech;
- on-device Russian and Arabic speech recognition, speech synthesis, grading, and optional Apple Intelligence assistance;
- focused 3/7/15-minute sessions, difficult-this-week practice, a 60-second spoken Sprint, and guided Russian/Arabic role-plays on every supported device;
- honest speech-recognition evidence, slow reference playback, immediate retry, adaptive scaffolding, curriculum recommendations, and recurring learning-pattern insights;
- practical topic journeys, curated starters, tutor imports, phrase metadata, and an editorial/native-speaker review queue;
- progress centered on successful recalls, spoken output, recovery, and fluency—not hearts or streak anxiety;
- private CloudKit sync when available, reliable local fallback, complete JSON backup/restore, widgets, Siri/App Shortcuts, and MetricKit diagnostics;
- VoiceOver-aware, Dynamic Type, dark mode, Reduce Motion, RTL Arabic, and adaptive iPhone/iPad layout.

CueFlow has no account system, ads, behavioral tracking, server-side analytics, subscription, or practice gate. CloudKit uses the learner's Apple account and the app remains fully useful offline and without iCloud.

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

See [`PRODUCT_UX_REMEDIATION_PLAN.md`](PRODUCT_UX_REMEDIATION_PLAN.md) for the audit and architecture, [`ROADMAP.md`](ROADMAP.md) for current status, and [`RELEASE_READINESS.md`](RELEASE_READINESS.md) for the human release gates.

## License

All rights reserved unless a license is added later.
