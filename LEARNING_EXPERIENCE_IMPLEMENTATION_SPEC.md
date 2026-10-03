# CueFlow: learning experience and engagement implementation specification

**Date:** 3 October 2026

**Status:** Initial implementation and story preview; see section 15 for exact scope and verification. Not all acceptance criteria are complete.

**Audited baseline:** Build 53, commit `01892f1`. Recheck code before implementation.

**Audience:** Product, iOS, content, design, and QA contributors.

**User problem:** The learner likes CueFlow but instinctively opens Instagram instead. Practice must become easier to start, interesting to continue, and visibly useful in real conversations and current tutor lessons.

## 1. Scope and authority

This specification turns the October audit into implementable work. It supersedes the August plan's conclusions that learning evidence, progress, and the core learning journey are complete. The earlier reliability and platform work remains valuable. This document does not claim that every screen has been newly inspected on physical hardware, that retention has been measured, or that the proposed experience has been validated with learners.

Labels used below:

- **Confirmed:** behaviour traced in the audited source.
- **Design decision:** intended behaviour for the proposed implementation.
- **Hypothesis:** expected benefit requiring a learner experiment.
- **Provisional threshold:** a concrete initial setting, configurable and versioned, not a scientifically established optimum.

Implement in phase order. Correctness fixes apply to everyone; do not A/B test knowingly incorrect progress or misleading session lengths. New episode formats and rewards require evaluation before broad content expansion. This document requests no new external analytics service, account system, or automatic sharing.

## 2. Product outcome and principles

The target experience is: open the app, encounter a personally relevant situation, start with one tap, learn and retrieve a few useful expressions, use them to finish the situation, and leave with a reason to return.

The primary learning outcome is **successful delayed unaided production of useful language**. Supporting outcomes are meaningful learning days per week, voluntary returns, and successful transfer to a changed scenario. Session duration and raw answer counts are diagnostic measures, not success by themselves.

Design principles:

1. Honour the learner's chosen commitment; never silently enlarge a session.
2. Reward demonstrated progress accurately and immediately.
3. Keep one phrase identity and its history, while distinguishing recognition, supported production, unaided production, and transfer.
4. Make tutor material and personal goals affect the next lesson.
5. Make exercise variety part of a coherent lesson; learners should not have to assemble the pedagogy from separate modes.
6. Support quiet use without forcing the learner into recognition-only practice.
7. Make return visits inviting after an absence. Preserve earned achievements.
8. Keep offline use, native navigation, accessibility, and private storage as product requirements.

## 3. Confirmed audit findings

Source links refer to the baseline and symbols, not permanently stable line numbers.

| ID | Finding and source | Required correction |
|---|---|---|
| F01 | `GraderService.grade` produces tier 1 for exact/accepted matches, tier 2 for fuzzy grading, tier 3 for optional model grading. `LearningEvent.isStrongProductiveRecall`, session achievements, and dashboard calculations interpret higher tiers as stronger learning. Weekly recap excludes tier 1 too. See [grader](LanguageLearning/Domain/Grading/GraderService.swift), [motivation](LanguageLearning/Domain/Engagement/LearningMotivation.swift), [cache](LanguageLearning/Services/LearningDataCache.swift), [recap](LanguageLearning/Domain/Engagement/WeeklyRecap.swift). | Separate grading method from outcome and support. Exact correct production must qualify without AI. Audit every tier comparison. |
| F02 | `TodayView.practiceSessionTarget` adds due workload and can expand a five-card session to twenty. `estimatedMinutes` uses the smaller selected target; the hero shows total backlog. See [RootView](LanguageLearning/App/RootView.swift). | Use one explicit session plan for preview, duration estimate, execution, and completion. |
| F03 | `SchedulerService.nextCard` selects all ordinary due material before new tutor material. A capped session can finish without introducing the promised tutor words. See [scheduler](LanguageLearning/Domain/Scheduling/SchedulerService.swift). | Reserve tutor slots inside a bounded session plan. Keep memory scheduling distinct from lesson composition. |
| F04 | Onboarding `selectedPurpose` only changes local UI state. See [onboarding](LanguageLearning/Features/Onboarding/OnboardingView.swift). | Persist the preference and use it in lesson selection; allow later editing. |
| F05 | `recordChoiceReview` sends Good/Easy directly to the shared FSRS card. Tile submission uses `reviewModeOverride = .typeDeToRu`, obscuring the visible-answer support used. See [PracticeView](LanguageLearning/Features/Practice/PracticeView.swift). | Record exercise and support explicitly. Recognition success must not be treated as unaided productive success. |
| F06 | `ProgressionSystem` uses historical qualifying phrase IDs and labels 80% as conversation-ready, without delayed retention or transfer requirements. See [progression](LanguageLearning/Domain/Engagement/ProgressionSystem.swift). | Distinguish lifetime exposure, recent recall, delayed recall, and demonstrated scenario performance. |
| F07 | Progress's named scenario recommendation launches generic `.recommended` practice. See `capabilitySection` and its cover in [ProfileView](LanguageLearning/Features/Profile/ProfileView.swift). | Pass the displayed scenario's scope through to the session plan. |
| F08 | Listening, reading, and guided conversations do not persist evidence comparable to review activity; the conversation coach intentionally avoids changing FSRS. See [listening](LanguageLearning/Features/Practice/ListeningLabView.swift), [reading](LanguageLearning/Features/Practice/ReadingView.swift), [conversation](LanguageLearning/Features/Practice/ConversationView.swift). | Save engagement/support evidence without inventing recall or semantic correctness. |
| F09 | Tutor pacing combines all active topics against the earliest lesson date and counts introduced material as preparation. See [TutorFocusPlanner](LanguageLearning/Domain/Scheduling/TutorFocusPlanner.swift). | Calculate each topic's deadline and preparation separately, deduplicate shared phrases, distinguish introduction from retention. |
| F10 | Main practice summary leads with spoken answers even for a quiet/recognition session. Grading uses a six-second response threshold across different answer lengths. See [PracticeView](LanguageLearning/Features/Practice/PracticeView.swift) and [grader](LanguageLearning/Domain/Grading/GraderService.swift). | Give mode-appropriate summaries; separate correctness from speed and speech-system delay. |
| F11 | Reading uses FSRS stability >= 7 and a Russian function-word exemption list to estimate known language. These are heuristics, not proof that a learner retained a word across seven elapsed days or comprehends the grammar. See [ReadingSelector](LanguageLearning/Domain/Exercises/ReadingSelector.swift). | Label estimated familiarity honestly; introduce authored beginner passages and language-specific comprehension rules. |
| F12 | Daily reminder is a repeating generic request to do cards; MetricKit records delivery counts, not a learning funnel. See [notifications](LanguageLearning/Services/NotificationService.swift), [diagnostics](LanguageLearning/Services/MetricsDiagnosticsService.swift). | Add local learning events and optional, relevant reminders; do not infer retention from diagnostic payloads. |

Tests currently construct many successful `LearningEvent` fixtures with tier 3. A passing fixture-based progress suite therefore does not disprove F01. Add tests beginning with real grader outputs.

## 4. Target interaction contract

### 4.1 Today

Above the fold: language, one recommended episode with an outcome, approximate duration and explicit scope, a primary Start button, and a Speaking/Quiet control. Below: a compact current-tutor-focus card and a small Explore entry. Detailed review backlog belongs in a secondary view with a bounded suggested catch-up plan.

Example German copy for an authored seasons lesson:

> Dein erster Herbst-Smalltalk
>
> Sag, welche Jahreszeit du magst – und warum.
>
> Etwa 90 Sekunden · 3 Ausdrücke
>
> Starten · Sprechen / Leise üben

Ninety seconds is a provisional estimate, not a forced countdown or guaranteed duration. The preview must be derived from the actual planned steps. Do not display total due cards as though they are today's session workload. If a backlog exists, use wording such as “Heute eine kleine Runde; weitere Wiederholungen bleiben eingeplant.”

After a break, recommend a bounded re-entry session using previously familiar material plus an optional relevant new expression. Avoid asking the learner to clear all missed reviews before receiving something interesting.

### 4.2 Episode flow

An initial episode contains: a short hook/context, model input, a meaning check if necessary, an unaided recall after intervening activity, a small variation, and an application turn. An episode may contain fewer stages when the learner already knows the material. Scaffolding is offered explicitly when needed.

Example seasons episode:

1. A character asks about the learner's favourite season, with optional meaning support.
2. Model one useful expression with audio and canonical target script.
3. Introduce or retrieve the season needed for the response.
4. Revisit the expression without the model visible after another step.
5. Change the season or preference so the response is not only a verbatim replay.
6. Answer a short follow-up and show a concise recap.

Completion means the planned activity was completed, not that every learning objective was mastered. The recap distinguishes independent success, supported practice, and material to revisit. An optional next episode names its outcome and length; Finish stays clear and reachable.

### 4.3 Quiet route

Quiet mode uses unaided typed retrieval for productive steps. A visible tile bank or reveal remains an optional scaffold and is recorded as such. No microphone prompt occurs on this route. A learner unfamiliar with the target keyboard can choose supported practice without receiving false unaided-recall credit. Switching routes preserves session progress.

### 4.4 Explore and Progress

- Keep the three native main destinations initially; a rename of Bibliothek to Entdecken is a later content/UI decision, not required for the first episode release.
- Explore groups content by communicative outcome, interest, and tutor lessons. Advanced editing/import remains readily available but subordinate to learning entry points.
- Progress leads with specific evidence: “Diese drei Ausdrücke nach einer Woche selbst abgerufen,” followed by what to practise next. Detailed counts/charts remain secondary.
- A named recommendation must launch that named content. Empty content has an honest fallback with explanatory copy, not a silent launch of unrelated practice.
- Continue using shared `DS` canvas, spacing, card geometry, and `LearningTypography`. Episode illustrations and scene changes provide personality; do not reintroduce inconsistent screen chrome.
- Sound, motion, colour, and haptics supplement visible/accessible feedback. Honour Reduce Motion and sound preferences. Quiet mode must not surprise users with automatic speech playback.

## 5. Architecture and data contract

### 5.1 Separate decisions from views

Introduce pure, versioned domain services; the names below are proposed and may be adapted to repository conventions:

| Component | Responsibility |
|---|---|
| `LearningEvidencePolicy` | Interpret correctness, support, input, and provenance consistently across every progress consumer. |
| `SessionPlanner` | Produce the bounded plan from user budget, scope, tutor deadlines, and memory state. |
| `EpisodeDefinition` / `EpisodeSession` | Versioned authored content and resumable execution state. |
| `CapabilityEvidencePolicy` | Derive exposure, unaided recall, delayed retention, and transfer separately. |
| `TutorPreparationPlanner` | Topic-specific preparation, achievable allocation, and deadline shortfalls. |
| `LearningEventStore` | Local activity/funnel events and aggregate export. |

SwiftUI renders value snapshots and sends intents. SwiftData model access stays on its appropriate actor; background planning receives immutable value inputs. Reuse existing interaction tokens and stale-work cancellation. Avoid adding a second independent implementation of progress inside the cache.

### 5.2 Evidence fields

Keep the canonical `Phrase`, `StudyCard`, and existing review history. Add backward-compatible review evidence, or a related attempt record, with these logical fields:

| Field | Values / semantics |
|---|---|
| `attemptID`, `sessionID` | Stable IDs for deduplication and resume; new records must populate them. |
| `exerciseKind` | recognition, tiles, typedRecall, spokenRecall, cloze, shadowing, listening, reading, conversation. |
| `supportLevel` | none, hint, visibleOptions, revealedModel, unknownLegacy. |
| `gradingMethod` | exact, acceptedAlternative, fuzzy, modelAssisted, selfReported, ungraded, unknownLegacy. Never a score. |
| `outcome` | correct, partiallyCorrect, incorrect, unassessed; retain original rating and suggested rating separately. |
| `inputChannel` | speech, keyboard, selection, none. Separate from exercise kind. |
| `firstAttemptOutcome`, `attemptOrdinal` | Preserve initial failure when an immediate retry succeeds. |
| `phraseID`, `scenarioID`, `episodeVersion` | Optional where the activity does not assess a specific phrase. |
| `promptVariantID`, `modelExposedAt`, `lastExposureAt` | Establish whether a later answer is independent or a transfer probe. |
| timing fields | Response onset when available, submission time, system wait time; do not equate total ASR elapsed time with hesitation. |
| `evidencePolicyVersion` | Makes subsequent derivation changes auditable. |

An **unaided successful recall** requires a productive exercise, support `none`, and a correct outcome. Spoken success additionally requires actual speech input. Revealed models, tiles, immediate corrections, ungraded conversation, and speech-system failures do not become unaided successes.

User overrides remain possible and visible as self-reported evidence. They must not silently become machine-verified transfer successes. A recognition tap made while the parent mode is “speaking” must be stored as recognition.

### 5.3 History and migration

1. Do not overwrite `gradeTier` or rewrite original reviews. Map its old values to grading method only.
2. Recompute corrected historical counts centrally. Distinguish “historically recorded successful response” from “verified unaided response.”
3. Old typed reviews cannot always be distinguished from tile submissions; copied/retried responses may also lack support metadata. Mark ambiguous support as `unknownLegacy`, show an explanatory transition state, and collect new evidence. Do not manufacture mastery.
4. Do not retroactively replay all FSRS schedules after this fix. Preserve due dates and parameters; new evidence policy applies prospectively.
5. Inspect the existing SwiftData schema before adding a version: `SchemaV1` currently references live model classes. Establish a genuinely stable old schema or prove the additive migration on a real baseline-store fixture; never assume a version-number change is sufficient.
6. Add CloudKit-compatible defaults/optional relationships. Review sync conflict handling and use stable event IDs for deduplication rather than relying on uniqueness constraints unsupported by the chosen store configuration.
7. Update backup format deliberately from current v4, retain supported older imports, round-trip new evidence/preferences/resume data, and retain idempotent restore. Unknown future formats must fail clearly.
8. Existing earned achievements are historical. Preserve their identity, distinguish legacy evidence, and do not replay all old celebration animations after migration.

## 6. Session planning and scheduling

### 6.1 Hard budget

For existing card sessions, the chosen target is a hard maximum number of primary review opportunities. Five means at most five; retries are optional and clearly do not silently add primary items. Episode plans declare their stages and optional supports explicitly. The time label is an estimate; ending on a timer must not discard an answer in progress.

Create a `SessionPlan` containing plan ID/version, language, scope, budget, ordered steps, expected duration, and reasons for selection. Preview and execution consume the same plan. Background refresh must not change a plan already started. If an item becomes invalid, replace it within the same scope and budget or finish early with accurate counts.

### 6.2 Proposed initial allocation

For a generic session with target `N` and active tutor demand:

1. Reserve up to `ceil(N / 2)` primary slots for outstanding tutor preparation, bounded by the demand and eligible content. Interleave them with general due material so a short session reaches tutor work.
2. Fill remaining slots with due reviews, then goal-relevant new material within the daily-new cap. If one pool is empty, fill from the others within the same scope and cap.
3. For an explicit topic/scenario session, enforce that scope first. Do not insert unrelated backlog items.
4. Deduplicate phrases shared by multiple tutor topics; record all objectives the practice helps.
5. A deadline never silently raises the daily-new cap or session budget. Show a shortfall and offer a separately chosen focus session or cap adjustment.
6. Each slot is selected at most once as a primary item; subsequent retrievals inside an episode are explicitly planned rehearsal steps. Each actual memory review has a unique ID and can be committed once.

The 50% tutor reservation is a provisional configurable policy. It is not a claim that this ratio maximises learning. Test with both large backlogs and multiple active lessons.

### 6.3 FSRS and production follow-up

Retain one canonical FSRS card. In the first implementation:

- Existing due unaided recall updates FSRS using the actual outcome and learner rating once per review opportunity.
- Recognition, tile assembly, reading, and shadowing save exposure/support evidence but do not submit a successful unaided rating to FSRS.
- Recognition-only success does not clear a production follow-up. New material is followed by an unaided attempt after intervening activity, within the declared budget if available, otherwise at a later session. Count the introduction toward daily-new limits even if its FSRS state remains new.
- A failure before revealing the answer is an actual failed retrieval; save it once. Repeating the displayed answer immediately is rehearsal, not a second Easy review.
- Separate introduction status from FSRS state in new-content counters and tutor preparation. Existing code uses `state != .new` as a proxy; update those consumers as part of this work.
- Add a lightweight persistent follow-up queue for production practice deferred by the budget. It references the canonical phrase and does not create competing FSRS memories.
- Do not invent an undocumented numeric conversion from recognition accuracy to productive FSRS ratings. A later modality-aware memory model would be a separately validated change.

Keep explicit self-rated card review available, record its provenance, and distinguish it from verified unaided production. Label synthetic content and generated dialogue separately; they must not silently become trusted assessment targets.

## 7. Tutor alignment and personalisation

Persist a language-specific learner profile: goal/interest, current focus, preferred session size, quiet/speaking preference, optional lesson dates, and Arabic variety where supported. Onboarding must use saved values when revisited and show one concrete resulting recommendation.

For each active tutor topic calculate unique phrase counts for: introduced, recent unaided recall, delayed retained recall, and context use. Divide outstanding introduction needs by that topic's remaining study opportunities, then allocate across topics by deadline and outstanding need. Review needs remain separate. Past-due lessons appear as “Termin vergangen” with reschedule/complete actions; do not silently reset deadlines forever. No date means a clearly labelled rolling preparation suggestion, not a claimed deadline.

Existing imported tutor lessons remain selectable and retain review history. A learner can set a focus before adding more words. Pasting vocabulary produces an immediate preview of its planned use. Arbitrary imported words support bounded vocabulary practice immediately; authored story episodes are offered only when compatible content exists. Do not promise automatic high-quality scenarios for every import.

Add optional short calibration for already-running courses. “Already familiar” may change initial presentation, but one placement answer does not establish durable mastery. Learners can skip calibration or correct their starting point.

## 8. Content and episode contract

Each authored episode must declare:

- Stable ID, version, language/variety, difficulty band, content provenance, review status.
- Title, concrete communicative outcome, interest tags, relevant tutor-topic tags.
- Required and introduced phrase IDs; grammar/construction objectives.
- Step order, prompt variants, accepted responses, optional hints/models, input alternatives, branch rules, and completion behaviour.
- Canonical target script, optional transliteration, source-language meaning, optional audio asset and synthesis fallback.
- Illustration/scene state, accessible description, optional next episode and reason.
- Which steps produce assessed recall, exposure only, or an unassessed conversation attempt.

Minimum pilot: three connected Russian seasons episodes and three Russian everyday episodes. Produce a small Arabic counterpart covering equivalent communicative goals and verifying RTL/variety behaviour; do not treat Russian morphology or translations as reusable Arabic pedagogy. Development drafts can exercise the engine; native-speaker review is required before claiming content quality for release.

Russian pilot constructions should include season names, time expressions, preferences, and a short reason. Arabic must explicitly state whether it teaches Modern Standard Arabic or a supported dialect; do not imply `ar-SA` speech settings constitute a dialect curriculum. Supply examples and accepted variants intentionally.

Content validation rejects missing phrase references, duplicate IDs, inaccessible step routes, unsupported language/variety combinations, absent required model answers, broken audio references, and branches that cannot finish. Unknown or missing content versions use an honest fallback and preserve prior history.

Beginner reading uses authored comprehensible scenes with optional meaning support. Existing heuristic sentence selection can supplement these; it must not claim comprehension from stability or ignored function words alone.

## 9. Progress, motivation, and feedback

### 9.1 Evidence levels

Use separate visible states with explanatory copy:

| State | Initial evidence requirement |
|---|---|
| Introduced | At least one recorded meaningful exposure. |
| Recalled independently | Correct productive attempt with no answer support. |
| Retained | Successful unaided probe at least seven days after the last recorded exposure to that item. |
| Applied in context | Correct response to an authored changed prompt with no model revealed. |
| Scenario demonstrated | Required scenario objectives completed independently using the preceding evidence; not merely an 80% vocabulary fraction. |

Seven days is a provisional reporting window. If an intervening exposure occurs, reschedule the delayed probe or label its shorter delay correctly. Do not withhold needed reviews to obtain a metric. Reading an item without identifiable phrase exposure makes retention timing uncertain; label or exclude that probe rather than claim a known gap.

For the pilot, scenario demonstration requires unaided success on every explicitly required communicative objective, with at least one authored transfer variant and one qualifying delayed check. Use “Situation selbst gemeistert” with a date, not a general language-fluency claim. Preserve lifetime achievements while showing current review needs separately. Historical achievement does not imply permanent present-day readiness.

### 9.2 Playful layer

First implement one recurring character and a small number of scenes. Answers should cause understandable changes: an order arrives, a weather plan changes, or the character responds to the selected preference. Reward the learning event at its point of occurrence with concise feedback, not a succession of modal screens.

Collections record demonstrated capabilities. Weekly rhythm is configurable and tolerant of missed days. Existing streaks can remain optional and historical; do not remove progress when a learner misses a day. Optional next-episode previews should contain a specific upcoming situation, not artificial scarcity.

Completion chimes differ from answer feedback, are short, and respect existing audio preferences. Reuse `CompletionFeedbackService`; verify audio-session interaction with playback/recording. Provide the same information visually and through accessibility labels. A mascot, competitive leaderboard, currency economy, or unlimited content feed is not required for the pilot.

### 9.3 Correctness and timing

Correctness remains correct even when slow. Response-speed feedback must account for response length and input channel; exclude system wait time when measurable. Until enough reliable timing data exists, show neutral correctness feedback and optional raw timing rather than a universal “hesitant” judgment. Recognition uncertainty must have a retry/edit route and must not automatically become a knowledge failure.

Preserve first-attempt evidence when a retry succeeds. Compare personal speed only on comparable item/input conditions; do not compare a one-word answer against a long sentence and call it a fluency record.

## 10. Local measurement and evaluation

### 10.1 Minimal events

Store an explicit session lifecycle and these local events: `session_previewed`, `session_started`, `step_presented`, `answer_submitted`, `support_used`, `feedback_shown`, `session_paused`, `session_resumed`, `session_completed`, `session_ended`, `next_episode_selected`, and `recognition_failed`.

Fields: event UUID, timestamp, session/plan ID, content/policy version, language, exercise/input/support/outcome categories, entry source, and foreground active duration when relevant. Link to local attempt IDs where needed. Do not copy raw answers, tutor text, audio, or transcripts into analytics. Existing learning history has separate retention rules.

Use local storage by default. Raw funnel events expire after 90 days; preserve useful local aggregates. Provide reset controls and a previewed, explicit aggregate export. No automatic transmission. Behavioural analytics remain separate from MetricKit diagnostics.

A background interruption is a pause, not instant abandonment. Persist a checkpoint after each committed step. Resume the same plan/version without duplicate reviews or rewards. An unfinished session is counted as abandoned for analysis only after an explicit End or 24 hours without resume; keep this definition versioned and visible in analysis.

### 10.2 Metric definitions

| Metric | Definition |
|---|---|
| Start conversion | Unique sessions started / eligible previews. |
| Time to first response | Foreground time from entry to first answer; report cold/warm start and input channel separately. |
| Completion | Completed plans / started plans; report shortened, interrupted, and content-empty plans separately. |
| Learning days | Local calendar days with at least one meaningful completed activity; report productive days separately. |
| D7 / D28 return | Eligible cohort members with meaningful activity on the seventh/twenty-eighth local day after first qualifying session / eligible cohort members. Also report weekly return separately; do not mix definitions. |
| Voluntary continuation | Completed sessions followed by explicit next-episode start; distinguish notification entry. |
| Delayed recall | First-attempt unaided correct responses / eligible delayed probes; also report probe coverage and actual exposure gap. |
| Transfer | First-attempt unaided success on changed authored prompts / eligible transfer probes. |
| Learning efficiency | Delayed retained objectives per foreground learning minute, reported alongside retention and completion. |
| Friction | Exits by step, support requests, recognition failures, persistence failures, and launch/interaction latency. |

Missing probes are not successes; show missingness separately. CueFlow activity cannot demonstrate reduced Instagram use. Assess replacement through optional participant reports or a separately authorised measurement design.

### 10.3 Evaluation sequence

1. Fix correctness for everyone and establish a baseline using the corrected metrics.
2. Run a formative pilot with 5–15 representative learners including the owner, current tutor learners, quiet-mode users, and Russian/Arabic learners. Use it to find confusion and assess interest, not claim statistically established retention lift.
3. Compare the bounded episode flow against bounded card practice with similar content, difficulty, exposure, and time budgets. Assign a stable variant per learner/language if a sufficiently sized experiment is feasible.
4. Primary engagement outcome: meaningful learning days per week. Learning guardrail: delayed recall and transfer must not materially worsen. Track enjoyment, perceived effort, and device failures.
5. Choose minimum meaningful effect, acceptable learning-loss margin, sample size, and observation window from baseline variance before running a confirmatory experiment. Small or incomplete samples yield directional findings only.
6. Expand content only when the loop is usable, evidence is trustworthy, and findings justify further investment. Do not claim faster learning based solely on session completion or same-session accuracy.

## 11. Developer backlog and acceptance criteria

Each row is a separately reviewable change. Checkboxes denote the full acceptance criteria, not partial implementations; see section 15 for implemented slices.

| ID / phase | Deliverable and main touchpoints | Acceptance criteria / essential tests | Dependencies |
|---|---|---|---|
| [ ] T01 / 1 | Define evidence semantics and historical adapter; `LearningMotivation`, `GraderService`, `GradeResult`. | Real exact and accepted-alternative grader outputs count as historical correct production without AI; incorrect tier-3 outcomes never count as success; unknown legacy support stays unknown. | None |
| [ ] T02 / 1 | Centralise progress consumers: cache, weekly recap, progression, achievements, library/path. | Same evidence yields consistent results across Today, Library, Progress, weekly recap, and session summary; cloze included where appropriate; method is never treated as quality. | T01 |
| [ ] T03 / 1 | Add prospective attempt evidence and safe migration/backup. | Tiles, recognition, hints, copied answers, retries, overrides, and speech failures have distinct persisted records; baseline-store upgrade and old/new backup round trips preserve history. | T01 |
| [ ] T04 / 1 | Bounded card `SessionPlan`; Today preview and `PracticeView` execution. | Selecting five with 111 due items runs at most five primary opportunities; estimate reflects the actual plan; no hidden extension; insufficient content finishes honestly. | T01 |
| [ ] T05 / 1 | Tutor reservation and exact recommendation scope. | Five-card session with a large backlog and pending tutor words includes tutor work; scenario CTA only selects its phrase set; unavailable scope explains fallback. | T04 |
| [ ] T06 / 1 | Correct summary and timing copy. | Quiet, recognition-only, spoken, mixed, and early-exit recaps report real activity; a slow correct response remains correct; no zero-spoken hero implies a failed quiet session. | T02–T04 |
| [ ] T07 / 2 | Local events, checkpoints, metrics definitions, aggregate export. | Duplicate callbacks and resume do not duplicate events/reviews; background pause is not immediate abandonment; no raw content in export; event expiry/reset works. | T03–T04 |
| [ ] T08 / 3 | Episode content schema, validator, deterministic runner. | Every branch has a finishing path; content version and support state survive resume; language switch cancels stale work; invalid content falls back safely. | T03–T04, T07 |
| [ ] T09 / 3 | Six Russian pilot episodes and Arabic validation counterpart. | Canonical scripts, quiet/speaking routes, accepted variants, explicit outcomes, content provenance, and review status present; no claim of native validation without review. | T08 |
| [ ] T10 / 3 | FSRS evidence boundary and deferred production queue. | Fast choice cannot clear an unaided follow-up; failed recall plus model repeat updates schedule once; daily introductions count correctly even before a productive review; queue survives restart. | T03–T05, T08 |
| [ ] T11 / 3 | New Today episode entry and inline exercise transitions. | One tap starts; preview/execution agree; quiet route needs no mic or automatic sound; primary action reachable at accessibility sizes; no unexpected tab rebuild. | T08–T10 |
| [ ] T12 / 4 | Persist learner goals and optional calibration. | Chosen purpose changes a concrete next recommendation and survives relaunch; replay/edit preserves history; placement does not manufacture retained mastery. | T03–T04 |
| [ ] T13 / 4 | Per-topic tutor preparation and past-lesson handling. | Two lessons with different dates pace independently; shared phrases count once globally; expired dates stay visible; unrealistic targets show a shortfall without silently enlarging sessions. | T05, T10, T12 |
| [ ] T14 / 4 | Delayed/transfer evidence and capability UI. | A single exact success is not durable mastery; an intervening exposure resets delayed-probe eligibility; changed prompts retain their IDs; lifetime achievements survive new review needs. | T02–T03, T08–T10 |
| [ ] T15 / 5 | Character, scene consequences, collections, bounded next episode. | Rewards are tied to committed events and play once; Finish remains accessible; Reduce Motion and disabled sound retain equivalent feedback. | T09, T11, T14 |
| [ ] T16 / 5 | Optional contextual reminders and return sessions. | Opt-in respected; reminder deep-links to valid content; completed commitment suppresses redundant reminders when app can update the schedule; stale offline copy is generic and truthful. | T07, T11–T13 |
| [ ] T17 / 6 | Beta protocol and analysis. | Versioned cohorts, exposure-matched comparison, explicit missingness, delayed/transfer checks, and limitations reported; no Instagram substitution claim without evidence. | T07, T09–T16 |

Recommended first implementation slice: T01–T06. The first episode milestone is T07–T11. Do not implement all rewards before validating that slice.

## 12. Verification and release gates

Tests should verify user outcomes and data integrity, not repeat implementation formulas. Required cross-layer scenarios include:

1. Exact spoken answer through real grader, save, cache refresh, all progress consumers, and relaunch with AI unavailable.
2. Correct visible-tile answer versus unaided typed answer: distinct evidence and progress.
3. Five-card choice with 111 due cards, new tutor vocabulary, daily cap exhausted, and multiple lesson dates.
4. Correct and incorrect AI-assisted grades, manual override, reveal, first failure plus successful retry, and speech-engine failure.
5. Episode interruption during audio, backgrounding, microphone denial, route change, language change, and duplicate submission.
6. Baseline store upgrade, unsupported backup, supported older backup import, new-format round trip, repeat restore, and CloudKit-compatible schema review.
7. First-time and returning learner with no content, no due items, no network, unavailable AI, and no supported speech recognition.
8. Russian and Arabic canonical script/RTL, quiet mode, large Dynamic Type, VoiceOver, Reduce Motion, light/dark, iPad and landscape.

Run targeted domain/integration tests during each slice, then the repository quality gate for a release candidate. The current script is `./ci_scripts/run_quality_gate.sh`; its simulator destination can be overridden with `DESTINATION` to an installed runtime. Generate the project from `project.yml` where needed. Do not count coverage percentage as proof of behavioural completeness or reuse historical pass counts as a fresh result.

Physical-device microphone/audio/interruptions, representative accessibility checks, native-speaker content review, and learner evaluation remain explicit gates. See [release readiness](RELEASE_READINESS.md). Simulator behaviour cannot certify these.

Performance requirements: retained native tab navigation, precomputed immutable screen snapshots, and no full-store traversal in view rendering. Measure before/after launch, tab interaction, and start-to-first-step on the same device and dataset. Provisional warm-start target is first actionable step within one second; report measured percentiles and device context before making performance claims.

Definition of done for a slice: accepted behaviour demonstrated, targeted checks pass, persistence compatibility assessed, relevant documentation updated, and limitations stated. Definition of done for the product experiment: observed results with denominators, content/version context, delayed learning evidence, and a decision to keep, revise, or stop the variant.

## 13. Research basis and limits

Sources accessed during the 3 October 2026 audit. These justify principles, not guaranteed engagement or learning gains for CueFlow.

| Source | Finding relevant to this specification | Application and limit |
|---|---|---|
| [Kim & Webb, 2022: spacing meta-analysis](https://onlinelibrary.wiley.com/doi/abs/10.1111/lang.12479) | 48 experiments, 3,411 participants; medium-to-large spacing benefit, with delayed-test differences between shorter and longer spacing. | Preserve spaced practice and assess delayed learning. Does not validate our episode duration or tutor allocation. |
| [Karpicke & Roediger, 2008](https://doi.org/10.1126/science.1152408), [researchers' university summary](https://source.washu.edu/2008/03/practicing-information-retrieval-is-key-to-memory-retention-2/) | Repeated retrieval after initial success benefited retention. | Require later retrieval; first exposure or one correct choice is insufficient evidence of durable production. |
| [Duolingo: separating streak and daily goal](https://blog.duolingo.com/improving-the-streak/) | Company-reported A/B test: 3.3% relative improvement in Day-14 retention; fewer learners reached the larger daily goal. | Test smaller minimum commitments. Retention evidence is not proficiency evidence; effect size is not a CueFlow forecast. |
| [Ryan, Rigby & Przybylski, 2006](https://selfdeterminationtheory.org/SDT/documents/2006_RyanRigbyPrzybylski_MandE.pdf) | Game studies linked autonomy, competence, and relatedness to enjoyment and future play. | Meaningful choice, accurate progress, and recurring characters are design hypotheses for this learning app. |
| [Lally et al., 2010](https://onlinelibrary.wiley.com/doi/10.1002/ejsp.674) | Consistent-context repetition supported automaticity; variation was large; missing one opportunity did not materially disrupt habit formation. | Stable optional cues and forgiving returns. Study concerned everyday behaviours, not CueFlow. |
| [de la Fuente, 2002: negotiation and oral vocabulary acquisition](https://www.cambridge.org/core/journals/studies-in-second-language-acquisition/article/negotiation-and-oral-acquisition-of-l2-vocabulary/ADFAE8E63258736DA28C53666E86838E) | Negotiated interaction incorporating pushed output supported productive vocabulary acquisition/retention in the study. | Integrate meaningful responses, not only selection. Does not prove every role-play engine measures correctness. |
| [Distributed practice and L2 fluency](https://www.cambridge.org/core/journals/studies-in-second-language-acquisition/article/effects-of-distributed-practice-on-second-language-fluency-development/4F6787916C198376CAD222934D3B37E4) | Examines repetition, spacing, and transfer in fluency development. | Test changed situations and delayed performance; same-task speed is not general fluency. |
| [Wilson et al., 2019: eighty-five-percent rule](https://www.nature.com/articles/s41467-019-12552-4) | Derives an optimal accuracy for particular models/tasks. | Do not impose 85% as a universal language-learning target. |
| [Meta ranking explanation](https://about.fb.com/news/2023/06/how-ai-ranks-content-on-facebook-and-instagram/) | Describes personalised ranking using signals and predictions. | Relevance and immediate interest are useful product comparisons; no causal diagnosis of the owner's app choice follows. |
| [Drops product description](https://www.languagedrops.com/) | Describes short, visual, game-based vocabulary sessions. | Design reference for bounded commitment and visual interaction, not independent efficacy evidence. |

The owner's Babbel preference is evidence of their preference for immediately usable phrases, not comparative efficacy evidence. The combination of coherent episodes, interesting scenes, and tutor relevance remains a product hypothesis until observed learning and return behaviour support it.

## 14. Deferred work and decision log

- No new cloud service, unrestricted AI tutor, phoneme-level pronunciation claim, currency economy, or public leaderboard is required for this plan.
- Native recordings and deeper morphology content can follow the pilot; the engine should allow recorded audio now through the existing reference-audio service.
- Keep precise thresholds and allocation policies configurable and versioned. Document changes and their evidence here when experiments justify them.
- Another developer should start with F01 and T01, inspect every tier consumer, add a real-grader integration fixture, and then implement T02–T06 before broad redesign.
- Record implementation commits and validation results against ticket IDs. Do not mark an entire phase complete because a screen exists or unit tests alone pass.

## 15. October implementation status

Implemented as Build 54 on 3 October 2026. This is an end-to-end **pilot slice**, not completion of all seventeen tickets or a validated engagement improvement. It has not been uploaded to TestFlight.

### Available behavior

- Central evidence policy: exact/accepted correct answers qualify without model grading. Prospective tile, reveal, retry, and override evidence is distinct; legacy support remains unknown. Progress copy no longer equates vocabulary percentages with conversation readiness.
- Card rounds freeze selected card IDs at start and honor the selected maximum. Tutor material receives interleaved reserved slots within the daily-new cap. Named Progress recommendations use their actual scenario scope.
- Multiple-choice and tiles no longer award successful productive FSRS reviews. Recognition-only new cards remain eligible for later production through their persisted review history. Introduction counts include exposure even while FSRS state remains new. Copied/retried answers cannot erase the original failed retrieval. Explicit self-rating in the older flip mode still controls its schedule, but is not verified productive evidence.
- Main practice defaults correctness to Good rather than using an uncalibrated six-second threshold to award Easy. Quiet typing is unaided; automatic reveal playback is muted. Old submission-time-based weakness classification is disabled.
- Six Russian and three Hocharabisch draft stories: two model steps, two recall steps, and a changed-context application prompt. The story card is available on Today; the collection is accessible from all three main destinations. Characters and scene symbols, visual feedback, and existing success/completion sounds provide the initial playful layer.
- Story progress, revealed-model state, attempts, language/version, and position persist. Quiet route requires no microphone. Pause/resume does not repeat a committed answer. Follow-up checks skip model steps after at least a day, then a week after the previous check. Additional in-story exposure postpones eligibility. These are labeled delayed practice, **not seven-day retained mastery or free-conversation validation**.
- Onboarding purpose persists per language and affects recommendation. Settings → Mein Lernrhythmus controls purpose, quiet startup, and weekly learning days; it also provides explicit aggregate sharing and raw-event deletion. New journal JSON is decoded once per changed value, not on every tab redraw.
- Tutor introduction demand is calculated against each topic's deadline; shared phrases allocate once to the nearest deadline. Explicitly focused units remain active until finished, including past lesson dates. Over-cap demand does not silently raise limits.
- Frozen Build 53 `SchemaV1` plus additive `SchemaV2`, migration plan, backup v5 with backward-compatible optional fields, evidence/journal round trip, idempotent restore, journal preflight before any mutation, and rollback around the rest of the import.
- Recovery-mode warning is compact with accessible details so it cannot consume the whole interface at large text sizes.

### Implementation map and remaining work

| Tickets | Implemented slice | Still required for full acceptance |
|---|---|---|
| T01–T03 | Central success/support policy, real-grader regression, review metadata, frozen migration and backup | Rich attempt provenance including original retry payload, all historical achievement identities, physical/CloudKit upgrade checks |
| T04–T06 | Hard card cap, stable in-session selection, tutor reservation, scoped recommendation, mode-appropriate summary and neutral timing | Persisted card-plan object shared by preview/execution; comparable-item speed metrics; exhaustive mixed/exit summary fixtures |
| T07 | Local story events, saved checkpoints, 90-day raw-event pruning, reset and aggregate export | Full preview/start funnel, foreground timing, abandonment/cohort denominators; activity evidence for all older practice modes |
| T08–T09 | Versioned linear story definitions, validator, resume runner, six RU/three AR drafts, canonical scripts | Canonical phrase references, fuller accepted alternatives, content-native review, explicit provenance/difficulty fields and richer branches |
| T10–T11 | Productive FSRS boundary, implicit durable new-card follow-up, one-tap story entry and quiet route | Canonical phrase-linked episode rehearsal and FSRS integration; explicit general follow-up queue; shared actual preview plan |
| T12–T13 | Saved purpose/rhythm/quiet, per-topic deadlines, past-focus preservation, shortfall copy | Optional calibration; retained/context-use counts for each tutor unit; scheduling by chosen weekly study opportunities |
| T14–T15 | Delayed story checks, changed-context prompts, collection, recurring characters, sounds and visible feedback | Cross-mode last-exposure accounting, evidence-backed scenario mastery, richer scene consequences, named optional next-episode handoff |
| T16–T17 | Existing optional reminders retained | Contextual reminder routing/suppression, return-session policy, prospective baseline and learner pilot/analysis |

### Data and release cautions

`AppSettings.experienceJSON` contains the local story journal. Backup restore merges runs/events by UUID and run modification time. **CloudKit can still resolve simultaneous edits of this single field with last-writer-wins behavior**; backup merge is not a general cross-device conflict solution. Move runs/events to independently mergeable records before claiming robust multi-device episode continuity. Existing vocabulary/review data retain their native SwiftData model structure.

Story definitions are draft authored-model matching, not an open semantic tutor. Other correct formulations can be missed; UI says so and offers support without inflating recall credit. Story exercises do not yet schedule existing Phrase records or prove knowledge of arbitrary imported tutor vocabulary. No content has been declared native-reviewed by this implementation.

Legacy review history is preserved rather than retroactively rescheduling FSRS. Historical displayed successes may include unknown support. The on-disk migration test covers the frozen Build 53 shape; direct upgrades from earlier historical schema shapes and physical-device stores still need validation. Seven-day retention cannot be asserted from story-only exposure logs when the same expression may have appeared in another mode.

### Verification record

- Simulator app build passed on iPhone 17 / iOS 26.5 with the installed Xcode toolchain.
- Initial domain/persistence run: 66 XCTest tests and 116 Swift Testing tests passed, including a frozen-V1 on-disk upgrade and real-grader evidence regression.
- Final source domain/persistence run: 66 XCTest tests and 118 Swift Testing tests passed, including malformed-journal preflight (no vocabulary/settings mutation), backup merge, migration, bounded planning, delayed-check exposure rules, and persisted goal/resume data.
- Final complete quality gate passed with exit 0: **66 XCTest unit tests + 118 Swift Testing tests + 15 UI tests = 199 checks**, **49.82% app-target line coverage** (14% regression floor). Device: iPhone 17 simulator, iOS 26.5. Result bundle: `/tmp/cueflow-build54-final-validation.xcresult`; command: `DESTINATION='platform=iOS Simulator,id=82106FF8-4D74-42CB-9953-1F61BCDE0771' RESULT_BUNDLE=/tmp/cueflow-build54-final-validation.xcresult ./ci_scripts/run_quality_gate.sh` (choose a new output path to repeat).
- UI checks include unaided typed Russian success, quiet supported completion, pause/resume, Arabic at the largest accessibility text size, landscape primary action, tabs, tutor-topic scope, and existing practice/reading/listening/conversation journeys. Exported Russian completion and Arabic large-text screenshots were visually inspected. Earlier failures drove the recovery-banner/landscape fixes and journal import preflight; one earlier simulator runner unexpectedly exited, so the gate now defaults to serial execution.
- No physical-device audio certification, native-speaker review, cross-device merge validation, D7/D28 learner study, or Instagram-replacement claim is implied by these checks.

## 16. Build 55 roadmap implementation

Implemented on 3 October 2026. Section 15 remains the historical Build 54 record; the statements there about stories being separate from FSRS and a single-field-only journal are superseded below. This ledger distinguishes implemented software from acceptance work still outstanding. Do not infer that all seventeen tickets are closed.

### Connected learning and continuity

- `EpisodeVocabulary` resolves a canonical phrase by language and normalized target expression. It reuses imported/bundled vocabulary, creates an explicitly unreviewed A1 phrase only when needed, and uses the existing StudyCard. It never creates a competing memory schedule.
- Model exposure is stored with `kind=exposure`, zero grading tier and explicit support; it counts as introduction but is excluded from productive progress and difficult-answer detection. Recognition, tiles, reveal, retry and self-report remain distinct. Story reviews include run/content/version/prompt identity, previous exposure, actual spoken word count and whether FSRS was applied.
- The first unsupported retrieval of a canonical expression in a story can update FSRS once. Later repetitions/application turns in that run do not schedule it a second time. Supported repeats do not turn a failure into Good. Duplicate run/prompt/kind callbacks are idempotent locally.
- `ProductionFollowUp` derives an outstanding unaided opportunity from durable review evidence, including supported practice on previously scheduled cards. Recognition cannot clear it. The planner brings these items back, and smart practice uses an unaided response rather than repeatedly presenting tiles.
- A story that would exceed the daily introduction cap now asks explicitly before proceeding. The limit is not silently raised or changed.
- `PracticePlan` persists version, identity, language, scope, mode, budget, ordered portable expression keys and selection reasons. Today caches its actual remaining count and estimate; Practice uses that supplied plan or an eligible saved round. Scope-specific practice can introduce deliberately selected inactive-topic material while retaining the cap. Difficult rounds are bounded and persisted too.
- Rounds resume within a 24-hour policy window, exclude committed reviews, and retain the original finite scope. Their header/progress uses the actual item count. Editing/deleting a phrase can make a portable key unavailable; unavailable items are skipped rather than replaced with unrelated content. Topic-scope identity is store-local, so restoring a backup can require starting a new topic round rather than resuming the old topic scope.
- Unconfirmed graded attempts and revealed-model state now have private checkpoints. First answer/outcome survive retry, pause and relaunch before grade confirmation. This is learning data, not analytics. A successful retry still cannot erase the original failure.

### Learner experience

- Optional three-answer calibration starts without model steps, allows help, preserves its result and makes an explicit next-step suggestion. It is not a placement certificate or retained-mastery award.
- Learners select actual study weekdays. Tutor Focus shows introduced, observed seven-day retrieval and changed-scene use separately, calculates opportunities before each deadline, and shows a numerical shortfall without enlarging rounds. Today uses selected-day demand, allocating shared phrases once to their nearest deadline. Past focus remains active until explicitly finished.
- Return visits after at least seven days offer an explicit five-item re-entry choice without debt language.
- Story feedback now describes consequences appropriate to café, seasons, meeting or clarification scenes. Finish remains primary; a named optional next story requires a separate tap. Quiet card summaries do not auto-play completion sound; summary sound is guarded against duplicate appearances.
- Story schema includes difficulty, provenance, review status and an optional audio-reference slot. Common authored alternatives are accepted. The runner supports explicit correct/support routes, validates destination IDs and rejects cycles or more than 32 authored steps. Shipped scripts remain finite linear pilot scenes; this is not an unrestricted conversation engine.
- Progress leads with specific historically observed delayed-recall examples and distinct changed-scene counts. Its cached dashboard refreshes on data revision, not on every tab selection. Lifetime vocabulary fractions are no longer called conversation readiness, including on the skill path. Earned badge identities are persisted when the path is evaluated and survive subsequent lower activity; unknown unrecorded historical awards cannot be reconstructed with certainty.
- Reading labels FSRS familiarity as an estimate, not proof of seven-day retention/comprehension. Beginners can choose simple authored story expressions with optional translations instead of reaching only a dead end.

### Persistence, observation and reminders

- Schema V3 adds `LearningJournalRecord`; the V2 model shapes are unchanged. Immutable run/checkpoint/event/plan/exposure/award fragments merge independently. `AppSettings.experienceJSON` remains a cached projection and backup representation, not the sole copy of each run. An event-reset tombstone prevents old fragments restoring deleted analytics. Neither legacy reviews nor their FSRS history are replayed on migration.
- Story and card-plan lifecycle/answer events, Today preview-to-new-story-start IDs, foreground interaction timing with a 60-second idle cap, pause versus 24-hour inactivity, and completion are available locally. Reading translation/audio use, listening recognition/dictation/shadowing, guided-conversation turns and Sprint matches/completion also record support-aware activity without FSRS grades. D7/D28 output includes recorded learning interactions across modes and distinguishes not-yet-observable, opt-out and expired raw-event windows. No-content/no-answer observations are not silently reported as failures.
- Card attempts capture first keyboard/ASR input availability and grading wait separately. Aggregate timing compares only matching phrase, exercise, input route and answer word count, using three early versus three recent successful uninterrupted submissions. It explicitly does not equate an ASR callback with true speech onset or claim improved fluency.
- Other learning modes establish a conservative language-wide exposure boundary. When exact phrase exposure is not known, this postpones story delayed probes rather than inventing an exposure-free interval. It is intentionally less precise than full phrase-level exposure instrumentation.
- Local aggregate sharing includes card/story activity and prospective exposure strata without raw responses or phrase identities. An explicitly opt-in, sticky, versioned stories-first/cards-first assignment changes Today ordering; both variants retain the same correctness fixes. There is no automatic upload or claim of a statistically validated effect.
- Existing reminder opt-in remains required. Reminders are non-repeating requests over the next seven days, constrained to selected weekdays, with generic truthful future copy and validated story/fallback routing. Story completion removes today's redundant reminder when the app can reschedule. Foreground launch and settings changes refresh the horizon. No background daemon or notification-delivery guarantee is implied; without reopening, reminders stop after the finite horizon.
- Reminder generations and cancellation tokens prevent an older asynchronous scheduling task from resurrecting opted-out reminders or removing newer requests. A separate day-level learning ledger preserves weekly activity when raw analytics expire or are deleted; it contains dates, not submitted answers.

### Remaining acceptance work

1. Validate older-mode event coverage on physical microphones and interruption paths. Their activity is not automatically certified productive recall. Exact phrase-level exposure coverage remains conservative where arbitrary conversations or reading can expose additional words.
2. Calibrate the implemented comparable-item timing against real keyboard/speech use before claiming faster retrieval or learning efficiency. ASR callback latency still cannot isolate articulatory onset; the active-time measure is capped interaction time, not validated cognitive effort.
3. Broaden authored content and scene assets only after reviewing the pilot. Shipped alternatives and scripts are still drafts; richer native audio/illustrations, morphology/comprehension coverage and independent semantic transfer assessment are not supplied by the bounded branch engine or a correct-answer matcher.
4. Stress-test journal growth, retained-tab performance and same-card concurrent use on representative physical datasets. Independent journal fragments preserve distinct runs in local merge tests; simultaneous cross-device FSRS mutation and clock skew remain real-device risks.
5. Finish native-speaker, microphone/audio/interruption, VoiceOver, physical-store migration and multi-device checks. These require representative devices/accounts/people; simulator tests do not close them.
6. Run the prospective learner protocol below. No D7/D28, retention gain, or Instagram substitution result has been fabricated.

### Verification

Fresh Build 55 results are recorded after the final quality gate in `RELEASE_READINESS.md`. Earlier Build 54 counts and intermediate Build 55 passes are not substitutes for that final run.

## 17. Prospective pilot protocol

Before enrolling learners, freeze the content version, acceptance rules, cohort policy and exposure definition, complete native content review, and obtain agreement to the optional local comparison. The in-app assignment is a delivery mechanism, not a completed experiment.

1. Recruit both Russian and Arabic learners, recording language, broad prior level and whether tutoring is active separately from the app's anonymous aggregates. Never merge language groups without reporting them.
2. Use the persisted assignment: stories first versus bounded cards first. Keep correctness, tutor access, daily limits and reminder opt-in identical. Preserve the assignment through relaunch; do not switch a learner because an early result looks favorable.
3. Observe four weeks. Pre-specify meaningful learning days, voluntary continuation, D7/D28 return, seven-day unaided recall and changed-context response as separate endpoints. Measure recall before showing its model. Report probe eligibility, invitations, completions and missing results separately; no response is not automatically an incorrect response.
4. Compare matched language/content/exposure strata and report numerator, denominator and uncertainty. Exposure-bucket exports support inspection but do not control for all selection effects, outside tutoring or unknown exposure. Do not pool typing and speech timing as a fluency measure.
5. Ask participants separately whether CueFlow displaced Instagram and whether that was welcome. App-open counts alone cannot establish substitution or wellbeing. No cross-app surveillance is required.
6. Inspect supported-answer use, recognition failures, early exits and opt-outs as possible friction or harm signals. A higher session count with worse delayed recall is not success.
7. Publish a keep/revise/stop decision with content/policy versions, exclusions, missingness and limits. If the sample is too small, report descriptive results rather than inventing a significant result or causal claim.
