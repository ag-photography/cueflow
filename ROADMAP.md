# CueFlow — Roadmap to App Store

**Current state:** build 28 — Phase A complete + i18n pass + practice/Profile visual refresh, on TestFlight (personal).
**Goal:** ship to App Store as a free, self-contained, privacy-first language-learning app for German speakers learning Russian (and Arabic).
**Realistic timeline:** 3–4 months / ~18–20 more builds.

---

## Strategic decisions (locked)

- **Free.** No IAP, no subscription, no pro features. Everything in the app, available to everyone.
- **No marketing website / companion site.** App-only experience. Privacy policy hosted as a one-page public Gist (Apple requires the URL).
- **Self-contained.** No accounts, no server, no sign-up. Install and use.
- **Privacy-first, on-device only.** No analytics, no tracking, no telemetry-to-server. SwiftData local + CloudKit-via-iCloud for sync (which is end-to-end encrypted by Apple).
- **Audience:** German speakers learning Russian (or Arabic). UI stays German for v1. English UI deferred.
- **Monetization mindset:** none. This is a passion project the developer also uses.

---

## What's already in place (build 20 baseline)

- ✅ Practice loop with three modes (Tippen / Sprechen / Karten)
- ✅ FSRS-6 SRS via swift-fsrs
- ✅ On-device grading (Tier 1 + 2 + opt-in Tier 3 Apple Foundation Models)
- ✅ On-device TTS (with ar-SA + ru-RU voice selection) and ASR (SFSpeechRecognizer)
- ✅ Russian curated A1 starter (~250 phrases) + Arabic A1 starter (~115 phrases)
- ✅ OpenRussian.org A2/B1/B2 wordlists (~1700 phrases) — all bundled, no manual loading
- ✅ Tutor-PDF import with semantic auto-classification + 14-day priority boost
- ✅ Streak chip + ProfileView with 7-day chart
- ✅ Daily reminder (opt-in, user-picked time)
- ✅ Variable-ratio surprise praise (~12% per correct, toggleable)
- ✅ Milestone celebrations (3/7/14/30/100/365 day streak)
- ✅ Backup → JSON export (one-way)
- ✅ Brand visual system (warm cream, serif headlines, deep teal accent, custom app icon)
- ✅ Privacy manifest (PrivacyInfo.xcprivacy) for App Store compliance
- ✅ Active-language switcher (RU / AR) with full content filtering

---

## Phased roadmap (build 21 → launch)

### Phase A — Foundation polish (~3-4 weeks, builds 21-25)
*Make the existing app shippable. No new features.*

- ✅ **21. Onboarding** *(shipped)* — 5-screen first-launch walkthrough (Willkommen / So funktioniert's / Tagesziel / Starter-Themen / Russische Tastatur); `hasCompletedOnboarding` gate in RootView with `markExistingUsersOnboarded` so returning users skip it; "Einführung wiederholen" in Settings replays it non-destructively.
- ✅ **22. Library overhaul** *(shipped)* — search field; filter by language + active/inactive status; per-topic detail screen (TopicDetailView) with mastery %, FSRS-state breakdown, due count, phrase list, rename; "Aktive Themen" chip-strip with toggle-off; bulk activate/deactivate on the filtered set; top-level phrase list now renders only while searching (was rendering all ~2000). *Note: per-**level** filter deferred — level isn't on the data model (A2/B1/B2 merged into semantic topics at seed time); revisit if a per-phrase level field is added.*
- ✅ **23. Settings restructure** *(shipped)* — grouped into Sprache & Inhalte / Üben / Erinnerungen / Daten / (Entwickler) / Info; dev tools (Diagnose) hidden behind a `developerModeEnabled` flag unlocked by tapping the version footer 7×; app version/build shown in the footer.
- ✅ **24. Visual coherence** *(shipped)* — Tippen/Sprechen prompt now sits on the same elevated card (surface/radius/shadow + serif scaling) as the flip card, so the prompt reads identically across all 3 modes; reveal slimmed (char-diff moved into the collapsed "Details & Abgleich" disclosure, answer is the focal point); rating row gains a "Vorschlag: X — bestätigen oder anpassen" heading and a white ring on the suggested choice.
- ✅ **25. Accessibility + dark mode** *(shipped)* — VoiceOver labels on icon-only buttons (header Fortschritt/Bibliothek, Vorlesen, Serie, Library/Onboarding controls); Dynamic Type — body/controls use semantic fonts; serif prompt + flip faces scale via capped `@ScaledMetric`; mode picker caps its growth so 3 segments keep fitting; Reduce Motion honored (flip rotation→cross-fade, reveal spring→fade, surprise praise); dark mode verified (fixed the onboarding badge: was using `surface0` which inverts to near-black on the teal — now a fixed cream `DS.onAccent`). Body text uses system semantic colours (AA by design).

### Phase A+ — Language-agnostic pass (build 26)
*The app ships Russian **and** Arabic; the UI must not assume Russian.*

- ✅ **26. Language-agnostic** *(shipped)* — onboarding gains a language-choice step (RU/AR with native names); starter-topic matching strips the " (XX)" suffix so the curated set resolves per language; the keyboard page is now data-driven (only shows when the target is non-Latin script — Russian Cyrillic yes, Arabic Latin-transliteration no) with language-neutral copy. Manual/paste/topic content entry (PhraseEditor, PasteImportView, TopicEditorView) files under the **active** language with adaptive labels instead of hardcoded "Russisch". *Still Russian-specific by design: PDF tutor-import (Cyrillic/Latin pair parsing) — revisit if Arabic tutor material appears.*

### Phase B — Continuity (~3 weeks)
*Make it feel like a real iOS app across devices. (Build numbers are approximate — bug-fix builds between features shift them; next feature build is ~28.)*

- **iCloud sync** — SwiftData + CloudKit configuration; conflict resolution strategy; iCloud account check on launch; gracefully handles iCloud-disabled.
- **27. iPad layout** — adaptive sizing; multi-column where useful (Library + Practice side-by-side on iPad); regular-size class respect.
- **28. Backup restore** — bidirectional JSON; file picker; idempotent merge on (de, ru) signature; conflict UI when target collides with existing.
- **29. Home Screen widget** — Lock Screen + Home Screen complications showing "X cards due today"; tap-to-launch-practice; small/medium sizes.

### Phase C — Engagement (~2 weeks, builds 30-32)
*Things that make people come back, without dark patterns.*

- **30. Topic detail screen** — bridges Library + Stats; phrases list, activation toggle, progress bar, FSRS state breakdown, "due now" filter.
- **31. Mistakes log + adaptive session** — "Diese Woche schwer gefallen" mode; user-picked session length (5/10/20/unbegrenzt) from Settings or session start.
- **32. Weekly recap** — Sunday morning notification with the week's stats ("Diese Woche: 87 Karten, 4 neue Vokabeln gemeistert"); pure reflection, no goal.

### Phase D — Launch prep (~1 week, builds 33-34)
*Most of this isn't code.*

- **33. App Store assets** — 6-10 screenshots per device size (iPhone 6.7", 6.1", iPad 13"); App Store description (~500 words, keyword-conscious); custom subtitle; promotional text.
- **34. Crash reporting + feedback** — MetricKit integration (Apple's built-in, privacy-safe, on-device aggregated, opt-in delivery); in-app "Probleme melden" mailto with diagnostic info; privacy policy hosted on public Gist; support email set up.

### Phase E — Beta + launch (~2-3 weeks)
*Software is done; now you find out if it works.*

- **35-37+. External TestFlight beta** — 5-15 testers from r/russian, German learning communities, Discord; iterate on feedback (probably 1-3 small fix builds); finalize App Store metadata.
- **App Store submission** — review usually 24-72h.
- **Launch announcement** — Reddit (r/russian, r/de), Hacker News if you want, Apple's indie newsletter pitch.

---

## What's deliberately deferred to post-launch

- Apple Watch companion
- Localization to English / other UI languages
- macOS Catalyst app
- More target languages beyond RU + AR
- Apple Intelligence Tier 3 grading polish
- Shortcuts / Siri intents
- Group decks / phrase sharing
- Adaptive FSRS weight refitting (via offline Python optimizer; in-app trainer skipped per build 6 decision)
- PDF OCR fallback (current PDFKit text-extract handles all observed tutor PDFs; OCR only needed for scans)

---

## What I refuse to build (regardless of how popular)

- **Streak-loss panic notifications** ("Your streak is at risk!")
- **Hearts / lives / energy gating** practice access
- **Public leaderboards / social streak comparison**
- **Random rewards unrelated to learning** (slot machine without dignity)
- **Cartoon mascots / animated characters cheering**
- **Server-side analytics / user-behaviour tracking**

The audience is adults with real learning goals working with a tutor. They don't need to be tricked into using the app.

---

## Budget

| Item | Estimate |
|---|---|
| Apple Developer Program | already paid (€99/yr) |
| Privacy policy / TOS template | €0 (write yourself / generate via Gist) |
| Native speaker review of A1 packs (optional) | €100-300 on Preply |
| Native voice recordings for top phrases (optional, v1.1) | €200-500 |
| Hosting | €0 (no website) |
| Marketing | €0 |
| **Total v1 launch** | **€0–300** |

---

## Recommended next build

**Build 21 = Onboarding.** Why before Library overhaul:
- First 30 seconds determine retention. Right now a new user opens to a card with no context.
- Library issues bite at week 2+; onboarding bites in minute 1.
- Self-contained (one new flow); Library overhaul touches many views. Lower risk for the next build.

Scope: 3-4 screen welcome flow, Russian keyboard install walkthrough, goal-setting micro-question, starter-topic selection, `hasCompletedOnboarding` flag, "Onboarding wiederholen" in Settings.

---

## Working principles for the rest of the build

1. **Cohesive > complete.** A polished feature beats a sprawling one. Skip rather than half-build.
2. **Privacy-first is the brand.** Every feature respects on-device-only; CloudKit sync is end-to-end-encrypted Apple-managed, not "our server".
3. **Adult tone.** No mascots, no panic, no manipulative gamification. Variable rewards exist (surprise praise, milestones) but always tied to real progress.
4. **First impression dominates.** Onboarding > sync > engagement features.
5. **Ship the smallest cohesive thing.** Each build does one thing well rather than three things partially.
6. **Real users > developer intuition.** Beta with external testers before launch is non-negotiable.
