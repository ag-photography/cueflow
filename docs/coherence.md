# CueFlow — coherence rules

The spec every feature is checked against (`product-coherence` skill). Short on
purpose; update it when a decision changes it. Status: **adopted 2026-10-06**
(Alex approved the proposed defaults by asking for the fixes).

**App type:** practice/habit (the Bibliothek is a task-style pocket: topics and content management).

## Core loop
German intent → retrieve the target-language expression → **say it aloud** → use it
in context. *(stated: README.md:3, ROADMAP.md:41)*
**Next thing:** one "Weiterlernen" on Heute that composes today's Runde and says
≈ how long and why now. *(stated: PRODUCT_UX_REMEDIATION_PLAN.md:114-143)*
**Free lane:** one collapsed "Frei üben" list under it; every activity there still
earns the same daily unit.

## Objects & actions
| Object | What it is |
|---|---|
| **Ausdruck** | One learning item: German intent, target form, audio. One FSRS memory each. |
| **Runde** | One session, composed or chosen. |
| **Situation** | A story/episode (only that). |
| **Thema** | A topic collection in the Bibliothek. |
| **Fortschritt** | The evidence of productive recall and speaking. |

Shared actions, one UI each: **anhören** · **aus dem Kopf sagen** · **prüfen** ·
**Antwort zeigen** · **später**.

## Glossary
| Use | Never | Meaning |
|---|---|---|
| Ausdruck | Karte, Phrase, Wort, Formulierung | the learning item |
| Runde | Einheit, Board, Session | a session |
| Situation | — for Themen/Szenarien | story/episode only |
| Thema | Mission, Szenario | topic collection |
| Wochenziel | Mission, Quest | weekly goal |
| Serie | — for in-round answer runs | consecutive days only |
| Antwort zeigen | Wort zeigen, Gemeinsam lösen, Ich weiß es nicht, Konnte ich nicht | help/reveal |
| Leise üben | Sprechen pausiert, Lieber tippen (as mode name) | quiet mode |
| Spiele-Mix, Paare finden, Hör hin, Wisch & triff, Satzbau, Aus dem Kopf | Word Snap, Sound Hunt, Swipe Match, Phrase Builder, Quick Recall, Board | game names |

Never in UI: FSRS, SRS, Tier, Habit, author notes, "Lernplan" disclaimers.
One name per activity everywhere (not "Tempo machen" *and* "Sprint").

## Interaction grammar — session
Implemented: `.dsPrimary` for every primary action, "Antwort zeigen", "Leise üben",
"Antwort" as the reference label, `CompletionCelebration` endings, quit asks
"Runde beenden?" when progress exists. Still open: one `SessionShell` component
that owns header, mic, feedback banner and summary for every activity.

| Moment | Wording | Component |
|---|---|---|
| Start | activity title, ≈ Minuten | shell header |
| Answer | speak first; "Lieber tippen" fallback | `MicButton` |
| Help / reveal | "Antwort zeigen" | one help action |
| Check | "Prüfen" | one check button |
| Feedback | richtig / fast / noch nicht — one colour + haptic set | `FeedbackBanner` |
| Continue | "Weiter" | `DSPrimaryButton` |
| Finish | one summary for every activity | `CompletionSummary` |
| Quit | X; confirm **and save** if progress would be lost | shell header |
Activities may differ in **tone** (energy, illustration), never in grammar.

## Success signal
**Daily rule:** a day counts when anything was answered from memory or practised
in a Runde, in this language (Reviews from Üben, Situationen, Sprint, Spiele —
one definition in Practice and Fortschritt). Shown as a quiet fact, never a countdown.
**Progress number:** "aus dem Kopf gesprochen" this week + Ausdrücke that sit
(stability ≥ 21 d).
**Memory:** unsupported spoken recall writes to FSRS in every activity; helped,
revealed, tapped or receptive attempts log activity only, never a grade
(rule exists: EpisodeVocabulary.swift:69-79).
Everything else (Sprint best, Arcade run, badges…) is a diagnostic one tap down.
No new scores, streaks or bests.

## Visual language
One primary button (`DSPrimaryButton`); accent for actions only. Each mode colour
means one mode and never a state; correct/close/wrong have their own tokens.
Heavy rounded type only inside celebrations. Tokens from `DS` — no raw colours or
radii in feature code.

## Product rules
- **Speaking = recall or shadowing.** While the learner speaks, the target text is
  not on screen; reveal is opt-in after the attempt. Check what is *visible*.
- On-device only: no cloud grading or data leaving the device.
- Adult tone: no mascots, no guilt, no countdown pressure, no dark patterns.
- Language-agnostic: RU and AR (and any future pack) via `LanguagePack`; never
  hardcode "ru", "ru-RU" or "Russisch".
- Speaking volume is a first-class goal — but only speaking that trains something.

## Entry points
| Activity | Lives at | Name |
|---|---|---|
| Composed Runde | Heute → Weiterlernen | Weiterlernen |
| Sprint, Gespräch, Hörstudio, Spiele-Mix, Paare finden, Wisch & triff, Situationen | Heute → Frei üben | one name each |
| Lesen | Bibliothek | Lesen |
| Themen & content | Bibliothek | — |
| Settings | toolbar gear | Einstellungen |

## Adding a feature
Run the `product-coherence` Feature check first. Minimum: same item pool · writes the
same memory if it is unsupported recall (`ActivityRecall`) · earns the same daily unit ·
ships first as a step or a Frei-üben row · reuses `.dsPrimary` and the session wording ·
names the job no existing feature does · reviewed after ~6 weeks via the local activity
events (`LearningActivityRecorder`). `ci_scripts/coherence_ratchet.sh` must stay green.

## Known violations (open)
Fixed 2026-10-06: one-button Heute, Situation recommendation, hidden text in spoken
steps, spoken recall → FSRS (Sprint, Aus dem Kopf), one streak definition, headline
progress, Hook-Model copy, Sprint best per language, primary-button families, Arcade
quit, stacked modals, dead Heute views and mode picker, glossary renames, Arcade/Episode
language branches, README/ROADMAP drift.
Fixed 2026-10-07: Gespräch credits known Ausdrücke used in free answers; Hör hin,
Satzbau and Aus dem Kopf are Spiele-Mix steps only; Lesen moved to the Bibliothek
with a completion; Fortschritt shows headline, speaking and topics with the rest
under "Alle Details"; `.sessionChrome` + `MicButton` for Arcade, Hörstudio, Lesen,
Gespräch; no Russian fallbacks left.

- Üben, Situationen and Sprint keep their own headers (Üben/Situationen already confirm and save on quit); move them onto `.sessionChrome` when next touched — *Grammar*
- Gespräch's chat composer uses a compact round mic next to the text field instead of `MicButton` (deliberate for the chat layout) — *Grammar*
- No shared `FeedbackBanner` yet: correct/close/not-yet copy is unified, the views are not — *Grammar*
- Ratchet baselines (raw colours 61 — mostly story illustrations, raw radii 26, `.borderedProminent` 4) — lower them, never raise — *Visual*
