# CueFlow TestFlight Runbook

The repository is configured for bundle ID `com.alex.cueflow`, widget extension `com.alex.cueflow.widgets`, automatic signing, private iCloud/CloudKit, App Group widget data, speech permissions, and non-exempt-encryption declaration `false`.

## Before every upload

1. Update `CFBundleVersion` for both app and widget in [`project.yml`](project.yml).
2. Run `xcodegen generate`.
3. Run the unit and UI suites on the pinned simulator runtime.
4. Test Russian and Arabic speech, audio routing, interruption recovery, backup/restore, iCloud fallback, and widget deep linking on physical devices.
5. Confirm [`RELEASE_READINESS.md`](RELEASE_READINESS.md) has no unresolved launch-blocking gate.
6. Commit the generated-source changes, but not the generated `.xcodeproj` if it remains ignored.

## Archive and upload

1. Open `LanguageLearning.xcodeproj` and select **Any iOS Device (arm64)**.
2. Choose **Product → Archive**.
3. In Organizer choose **Distribute App → TestFlight & App Store → Distribute**.
4. Keep automatic signing enabled and upload symbols.
5. Wait for App Store Connect processing, then inspect every processing warning before assigning testers.

CloudKit containers, App Groups, and widget capabilities must exist for the selected Apple Developer team and match the committed entitlements. Never remove a capability merely to make an archive pass; resolve the actual signing/container configuration.

## Internal smoke

On a clean install and an upgrade over the previous TestFlight build:

- finish and skip onboarding;
- start/exit/complete a session in Russian and Arabic;
- deny speech permission and confirm non-speaking fallback;
- run Sprint, difficult practice, and conversation availability/fallback;
- create/import/edit/review content;
- export, alter data, and restore a backup;
- launch offline and with iCloud signed out;
- verify all widget families and the practice deep link;
- force quit during an active exercise and confirm no duplicate review or data loss;
- send a problem report and verify it contains no learning content.

## External beta

Use 5–15 German-speaking Russian/Arabic learners with different skill levels and devices. Beta review information must include a monitored email, published privacy URL, description, and notes explaining that no account is required and Apple Intelligence features are device-gated.

Collect qualitative feedback rather than adding behavioral tracking. Ask testers specifically:

- Did the first session make the speaking-first promise obvious?
- Was any correction confusing or unfair?
- Could they recover from microphone, speech, or model failure?
- Which real-world phrase was immediately useful?
- Did they voluntarily start another session, Sprint, difficult round, or conversation—and why?

Block public submission for any reproducible crash, data loss, inaccessible primary action, misleading grading, broken Arabic representation, or permission dead end.
