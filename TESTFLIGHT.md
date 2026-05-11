# TestFlight Deployment Runbook

Steps the codebase can't do for you — Apple-account-bound. Do these once, then archive + upload from Xcode whenever you ship a new build.

## What's already done

- `project.yml` carries `CFBundleShortVersionString: "1.0"`, `CFBundleVersion: "1"`, `ITSAppUsesNonExemptEncryption: false` (skips encryption export-compliance prompt).
- `LanguageLearning/PrivacyInfo.xcprivacy` declares no tracking, no collected data, and `UserDefaults` access with reason `CA92.1` (third-party SDK requirement, but covers SwiftData/UserDefaults usage too).
- Mic + Speech usage strings set in `project.yml`.
- 1024×1024 app icon at `LanguageLearning/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` (no alpha channel — App Store rejects icons with alpha).
- Release builds clean for simulator (verified). Bundle ID: `com.alex.cueflow`. Display name: CueFlow.

## One-time Apple-side setup

1. **Apple Developer Program** — https://developer.apple.com/programs/ — €99/year. Personal account is fine.
2. **Team ID** — once enrolled, Xcode → Settings → Accounts → add your Apple ID. Then in `project.yml` replace the empty `DEVELOPMENT_TEAM: ""` with your 10-character Team ID, or leave it empty and set it in Xcode's Signing & Capabilities tab (Automatic signing will pick it up).
3. **App Store Connect record** — https://appstoreconnect.apple.com → My Apps → "+" → New App.
   - Platform: iOS
   - Name: `CueFlow` (must be unique on the store; rename if taken)
   - Primary language: German
   - Bundle ID: select `com.alex.cueflow` (Xcode auto-creates the App ID on first archive; or pre-create at https://developer.apple.com/account/resources/identifiers/list)
   - SKU: anything unique to you, e.g. `CUEFLOW-001`
4. **Encryption export compliance** — already declared `ITSAppUsesNonExemptEncryption: false` in plist, so no annual self-classification needed.

## Archive + upload (every build)

In Xcode (open `LanguageLearning.xcodeproj`):

1. Bump `CFBundleVersion` in `project.yml` (must increase every TestFlight upload — 1 → 2 → 3…). Run `xcodegen generate` after editing.
2. Top bar destination: **Any iOS Device (arm64)**. Not a simulator.
3. **Product → Archive**. Takes a couple of minutes.
4. Organizer window opens automatically. Select the archive → **Distribute App** → **TestFlight & App Store** → **Distribute** → **Automatically manage signing** → **Upload**.
5. Apple processes the build (5–30 minutes). You'll get an email when it's ready, or one bouncing it for missing metadata.

Common processing-stage rejections you'll see if anything is off:
- Missing icon → already handled.
- Privacy manifest missing → already handled.
- ITSAppUsesNonExemptEncryption missing → already handled.
- App Sandbox / Hardened Runtime / entitlements complaints → not applicable to iOS apps; ignore.

## TestFlight setup (first build only)

In App Store Connect → your app → **TestFlight** tab:

1. Once the build appears under iOS Builds, click it → fill in the **export-compliance answer** if prompted (No, since we declared `false`).
2. **Test Information** (left sidebar):
   - Beta App Description: one paragraph
   - Email + privacy URL (a placeholder GitHub Pages or Notion link is fine while it's just you)
   - Marketing URL: optional
3. **Internal Testing** group → "+" → add yourself by Apple ID. Internal testers don't need a beta review; the build is available within ~5 minutes of upload.
4. On your iPhone: install **TestFlight** app from the App Store → it shows the build → install.

External testers (anyone outside your App Store Connect team) require a Beta App Review — Apple takes 24–48h on the first build, usually instant on subsequent versions of the same build train. Not needed for personal use.

## When something fails

- **"No account for team" / signing error during Archive** — Xcode → Settings → Accounts → make sure your Apple ID has the team listed. Then in the project's Signing & Capabilities tab, ensure "Automatically manage signing" is on and the team is selected.
- **"App Store Connect Operation Error: Invalid Bundle"** — check the icon: must be 1024×1024 with no alpha. Already verified with `sips -g hasAlpha`.
- **"This bundle is invalid. The Info.plist file is missing the required key: CFBundleIcons"** — only happens if Assets.car wasn't generated. Clean build folder (⇧⌘K) and re-archive.
- **iCloud / push entitlement errors** — we don't use either. If Xcode auto-added them, remove from the entitlements file.

## Per-release checklist

```
[ ] Bump CFBundleVersion in project.yml (and CFBundleShortVersionString if user-visible feature changes)
[ ] xcodegen generate
[ ] git commit (if you're tracking git)
[ ] Test once on physical device for the speaking mode (simulator can't do on-device Russian ASR)
[ ] Product → Archive
[ ] Upload via Organizer
[ ] Wait for processing email
[ ] On phone, open TestFlight, install, smoke-test
```

## What's deferred

- **Beta App Review for external testers** — only if you want non-team-members on TestFlight.
- **App Store submission** (full review, public release) — separate flow under "App Store" tab. Not needed for personal use; TestFlight is enough.
- **CloudKit sync, push notifications, widgets, App Groups** — none of these are wired up; if you add them later, they each need a corresponding capability + entitlement.
