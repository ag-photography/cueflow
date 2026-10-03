# CueFlow 1.0 — Release Readiness

This file separates work the repository can verify from work that requires a physical device, native speakers, an Apple account, or real learners.

## October story-preview gate

The new episode loop is a development preview. See [connected-learning status and limitations](LEARNING_EXPERIENCE_IMPLEMENTATION_SPEC.md#16-build-55-roadmap-implementation) and the [Build 56 visual gamification contract](LEARNING_EXPERIENCE_IMPLEMENTATION_SPEC.md#18-build-56--illustrated-story-loop-and-evidence-safe-gamification). Earlier checked gates below describe prior builds and must not be read as fresh certification of these new features. Before public rollout, review RU/AR content, microphone/audio behavior, migration on physical stores, and simultaneous-device journal edits. Build 55 adds independent immutable journal fragments and merge tests; this removes the single-field overwrite design for run history, but does not certify real CloudKit concurrency or simultaneous scheduling of the same card.

Local episode events record IDs and timestamps, not answers or recordings. The app keeps raw events for 90 days (pruned on the next event write/merge), offers deletion and explicit aggregate export, and sends none to an analytics server. Include this local-learning-journal behavior in the final privacy text.

Card-attempt checkpoints are **private learning data**, distinct from analytics events: they preserve submitted text and the original attempt before a grade is confirmed. They follow the existing private learning-store/iCloud/backup behavior. Aggregate pilot exports contain no answer text, recordings, or per-phrase identities. Event deletion does not delete learning history; its reset timestamp prevents old event fragments from resurrecting on merge.

Build 54 local validation, 3 October 2026: complete quality gate passed, 184 unit/domain tests and 15 UI tests, 49.82% app line coverage on iPhone 17 / iOS 26.5 simulator. Includes frozen-V1 migration, backup round trip/idempotence/malformed-journal preflight, typed Russian recall, Arabic accessibility-size layout, quiet resume/completion, and landscape/tab checks. This is not physical-device or content-quality sign-off, and no TestFlight upload has been performed.

### Build 55 final verification — 3 October 2026

The final complete quality gate passed with exit 0: **66 XCTest unit tests + 137 Swift Testing tests + 16 UI tests = 219 checks**, zero failures, **51.94% app-target line coverage**. Environment: iPhone 17 simulator, iOS 26.5, Xcode 27. Result bundle: `/tmp/cueflow-build55-final-verified.xcresult` (temporary local artifact, not committed).

Repeat with a fresh result path:

```sh
COLLECT_TEST_DIAGNOSTICS=never \
DESTINATION='platform=iOS Simulator,name=iPhone 17,OS=26.5' \
RESULT_BUNDLE=/tmp/cueflow-build55-repeat.xcresult \
./ci_scripts/run_quality_gate.sh
```

The diagnostics override disables verbose simulator-system collection, which stalled result packaging in an earlier run; test logs, screenshots and coverage remain available. The script defaults to serial tests and normal on-failure diagnostics otherwise. The final run includes canonical phrase reuse, once-per-run FSRS scheduling, supported follow-up, bounded/resumable plans, private attempt checkpoints, V2-to-V3 disk migration, independent fragment merge/reset, retained learning days after analytics deletion, tutor weekdays/deadlines, conservative exposure, timing comparability, branch validation, and optional calibration UI coverage.

Arabic story layout at the largest accessibility text size and quiet supported completion were visually inspected from the preceding isolated passing run; the final changes were nonvisual reminder-cancellation and day-ledger safeguards. Simulator checks do not certify physical audio, VoiceOver, large-store performance, real CloudKit concurrency, native content quality, or improved learner retention. No push or TestFlight upload was performed for Build 55.

### Build 56 final verification — 3 October 2026

Complete quality gate passed with exit 0: **66 XCTest unit tests + 146 Swift Testing tests + 17 UI tests = 229 checks**, zero failures, **52.07% app-target line coverage**. Environment: iPhone 17 simulator / iOS 26.5 runtime / Xcode 27. Result bundle: `/tmp/cueflow-build56-releasecheck.xcresult`. Repeat with a fresh result path using the Build 55 command above.

New coverage includes cosmetic reward deduplication, supported versus unaided answers, known seven-day intervals, calibration exclusion, content-version/language isolation, backup reconstruction, and the shared journal-capable schema for all storage modes. UI verification includes the illustrated hero/passport in genuine light and dark appearances, supported completion incrementing the collection without earning recall markers, typed Russian, Arabic at the largest accessibility size, landscape, resume, and the existing tutor/navigation journeys.

Final light/dark screenshots, the collection, supported completion and Arabic large-text layout were exported and reviewed across the verification runs. Final attachments are under `/tmp/cueflow-build56-final-visuals/`; these are temporary local artifacts. The recovery banner in screenshots is intentional: UI tests use a fresh in-memory store, not a user's real learning history.

Verification found and fixed a 14-point collection-link target (now 44 points), an ineffective appearance launch argument (now an isolated DEBUG-only harness override), and the CloudKit factory's stale V2 schema selection (now shared V3). One intermediate run had startup-readiness failures under host load and another caught the missed collection tap. The final harness waits explicitly up to 45 seconds for fresh-library preparation; tab-transition assertions still use their original three-second limit. This is not a physical-device cold-launch performance benchmark.

Calculated brand text/card contrast is approximately 5.91:1 in light mode and 7.70:1 in dark mode; white on the primary teal button is 6.04:1. These specific token checks are not a whole-app accessibility certification. Physical VoiceOver/audio/Reduce Motion testing, real CloudKit migration/concurrency, native content review and prospective learner validation remain required. No claim of improved retention or addictiveness is established by the UI tests. Build 56 has not been pushed or uploaded to TestFlight.

## App Store positioning

**Name:** CueFlow  
**Subtitle:** Russisch & Arabisch sprechen  
**Primary category:** Education  
**Secondary category:** Productivity  

**Promotional text**

Lerne nützliche Ausdrücke so, wie du sie im Gespräch brauchst: vom deutschen Gedanken zur gesprochenen russischen oder arabischen Antwort.

**Short description**

CueFlow ist ein privater Sprachtrainer für deutsche Muttersprachler:innen. Statt nur Übersetzungen wiederzuerkennen, rufst du russische und arabische Ausdrücke selbst ab, sprichst sie laut und setzt sie in kurzen Alltagssituationen ein.

**Full description draft**

CueFlow trainiert die Richtung, die beim Sprechen zählt: Du siehst, was du auf Deutsch ausdrücken möchtest, erinnerst dich an die russische oder arabische Formulierung und sagst sie selbst.

Kurze, adaptive Einheiten kombinieren Auswahlaufgaben, Wortbausteine, Tippen und Sprechen. Mit zunehmender Sicherheit verschwinden die Hilfen. Schwierige Ausdrücke kehren gezielt zurück, während der FSRS-Lernplan deine Wiederholungen sinnvoll verteilt.

Für mehr Sprechpraxis gibt es einen 60-Sekunden-Sprint und kurze Rollenspiele mit deinen aktuellen Ausdrücken. Praktische Missionen wie Begrüßung, Café oder Unterwegs helfen dir, Sätze zu lernen, die du sofort verwenden kannst.

CueFlow enthält Starter-Inhalte für Russisch und Arabisch. Eigene Phrasen, Tutor-Unterlagen und Themen kannst du ergänzen und in einer Qualitätsprüfung verwalten.

Dein Fortschritt zeigt echte Lernsignale: erfolgreiche Abrufe, gesprochene Wörter, flüssigere Antworten und Ausdrücke, die nach Fehlern wieder sicher werden. Es gibt keine Herzen, Energiegrenzen, Ranglisten oder Streak-Drohungen.

Deine Lerndaten bleiben bei dir. Spracherkennung, Bewertung und optionale KI-Unterstützung laufen auf dem Gerät. CueFlow verwendet kein Werbe-Tracking und keine serverseitige Verhaltensanalyse. iCloud-Synchronisierung ist optional; vollständige Sicherungen lassen sich exportieren und wiederherstellen.

## Keywords

`Russisch lernen, Arabisch lernen, sprechen, Vokabeltrainer, Aussprache, Karteikarten, FSRS, Sprachtrainer, offline`

## Screenshot story

Capture from the exact release candidate with realistic but non-personal sample data. Keep text readable without compositing claims the screen does not substantiate.

1. **Heute:** “Heute wirklich sprechen” — recommended session and productive goals.
2. **Speaking prompt:** “Vom deutschen Gedanken zur eigenen Antwort.”
3. **Useful correction:** “Sofort verstehen, was noch fehlt.”
4. **Real-world missions:** “Ausdrücke für Café, Reise und Alltag.”
5. **Sprint:** “60 Sekunden Sprechfluss.”
6. **Conversation:** “Kurze Rollenspiele mit deinem Wortschatz.”
7. **Progress:** “Sieh, was du selbst abrufen kannst.”
8. **Arabic:** “Arabische Schrift, RTL und Lautschrift.”
9. **Privacy/backup:** “Auf dem Gerät. Sicherbar. Ohne Tracking.”

Required captures should follow the currently requested App Store Connect device classes rather than relying on hard-coded historical dimensions. At minimum, capture the largest required iPhone class and iPad class; let App Store Connect scale only where Apple permits it.

## Privacy policy draft

Publish this text at a stable HTTPS URL and replace the bracketed contact address before submission.

### Datenschutz bei CueFlow

CueFlow erhebt keine personenbezogenen Daten für Werbung, Tracking oder serverseitige Analyse. Es gibt kein CueFlow-Konto und keinen CueFlow-Server.

Lerninhalte, Lernfortschritt und Einstellungen werden mit SwiftData auf dem Gerät gespeichert. Wenn iCloud verfügbar und für CueFlow aktiviert ist, kann Apple CloudKit diese Daten über die private iCloud-Datenbank des verwendeten Apple-Accounts zwischen Geräten synchronisieren. Für die Verarbeitung durch Apple gelten die Datenschutzbestimmungen und iCloud-Einstellungen von Apple.

Spracherkennung wird nur nach ausdrücklicher Freigabe verwendet. CueFlow verlangt die Verarbeitung auf dem Gerät; ist das benötigte lokale Sprachmodell nicht verfügbar, wird nicht automatisch auf einen CueFlow- oder Drittanbieter-Server ausgewichen. Die optionale Apple-Intelligence-Unterstützung ist nur auf kompatiblen Geräten verfügbar und verwendet Apples System-Framework.

CueFlow verwendet MetricKit, um von iOS bereitgestellte technische Diagnoseberichte lokal zu empfangen. Ein Problembericht wird nur durch eine bewusste Freigabeaktion des Nutzers geteilt und enthält keine Phrasen, Antworten oder Lerninhalte.

Benachrichtigungen sind optional und werden lokal geplant. Vollständige Sicherungen werden nur auf ausdrückliche Aktion exportiert. CueFlow enthält keine Werbung, keine Drittanbieter-Analytics und kein Cross-App-Tracking.

Fragen zum Datenschutz: [SUPPORT-EMAIL]

## Automated gates

- [x] project generation succeeds from `project.yml`;
- [x] app and widget compile on the iOS 26.5 simulator SDK;
- [x] unit tests cover core domain and persistence behavior;
- [x] UI smoke tests cover the primary session, tabs, large accessibility text, Arabic configuration, guided role-play entry, landscape reachability, capability path, and listening studio;
- [x] the unit/performance suite covers 117 named tests / 127 executions, including 20,000-event progression analysis, and CI enforces a 14% app-target coverage floor;
- [x] clean iPad Pro 13-inch startup and adaptive sidebar layout are visually checked with native multitasking/orientation declarations;
- [x] clean startup and additive model migration are smoke-tested over existing simulator data;
- [x] privacy manifest, microphone and speech usage descriptions, URL scheme, App Group, iCloud, and widget entitlements exist;
- [x] complete versioned backup and merge restore exist;
- [x] startup falls back safely when iCloud or persistent storage is unavailable.

## Physical-device matrix

Run every row on the release archive, recording device, OS, result, and issue link.

| Area | Required checks |
|---|---|
| Russian speech | permission allow/deny, offline model present/missing, partial result, silence, retry, background interruption |
| Arabic speech | same lifecycle, canonical Arabic output, RTL, transliteration, dialect limitations communicated |
| Audio | silent switch, speaker, wired/Bluetooth route, incoming call, TTS after recording, completion chime toggle |
| Persistence | force quit during practice, low storage, offline launch, iCloud sign-out, second-device merge, backup round trip |
| Accessibility | VoiceOver order/actions, XXL text, Bold Text, Increase Contrast, Reduce Motion, Switch Control, landscape/iPad keyboard |
| Widgets | small/medium/Lock Screen, stale timeline, language switch, deep link, zero-due state |
| Performance | cold launch, seeded-library scrolling, memory during long session, MetricKit delivery after crash/hang simulation |

## Content and beta gates

- [ ] native Russian review of every bundled A1 item, example sentence, register, stress/transliteration, and TTS pronunciation;
- [ ] native Arabic review of every bundled A1 item, script, transliteration, register, dialect labeling, accepted alternatives, and TTS pronunciation;
- [ ] 5–15 external beta learners complete onboarding and at least three sessions;
- [ ] observe permission-fallback comprehension, session completion, voluntary repeat, difficult-item recovery, and conversation usefulness;
- [ ] resolve every crash, data-loss, inaccessible-primary-action, or misleading-feedback issue;
- [ ] support email monitored and privacy-policy URL published;
- [ ] App Store privacy nutrition labels answered consistently with the binary and policy;
- [ ] final screenshots, age rating, content rights, export compliance, review notes, and demo instructions completed in App Store Connect.

## Review notes draft

CueFlow does not require an account. On first launch, select Russian or Arabic and complete or skip the guided speaking step. Microphone and speech permissions are requested only when a speaking action begins; all other practice remains usable if permission is denied. Guided conversations and the listening studio work without Apple Intelligence; optional Apple Intelligence grading degrades gracefully when unavailable. The app contains no purchases or gated practice.
