# RISE RoutineTimer — Audit & Plan (2026-09-06)

Product goal (from owner): help us **design** our morning routine, be an **active timer** while doing it,
and **get better every day** by becoming more efficient.

Scorecard against those three goals today:

| Goal | State | Gap |
|---|---|---|
| 1. Design the routine | Basic list editor works | No target "done by" time, no icons, no duplicate/reset, editor polish |
| 2. Active timer | Core countdown works and looks good | **Cannot pause or exit while running**, session lost if app is killed, alerts too weak, no lock-screen presence |
| 3. Get better daily | **Nothing** | No session recording, no summary, no history, no suggestions |

Build status: compiles clean on Xcode 26 (no warnings). No test target. 1,263 lines of Swift, 687 of them in `RoutineTimerView`.

---

## A. Bugs and defects found (verified in code and/or simulator)

Severity: 🔴 must fix · 🟠 should fix · 🟡 polish

### 🔴 A1. No pause / stop / back while running
`RoutineTimerView` hides the nav bar and tab bar when `isRunning`, and the active screen only has the checkmark.
The only way out is to complete every step or force-quit. Verified in simulator. `toggleRunning()` is unreachable while running.

### 🔴 A2. Run state is not persisted
All run state lives in `@State` (`currentIndex`, `stepEndDate`, `routineStartDate`, `accumulatedRoutineDeltaSeconds`, …).
If iOS kills the app in the background during a 20–30 min routine (common when the phone is locked in a bathroom), the session is gone and the app relaunches at READY. Combined with A1, this is the biggest reliability risk for the core use case.

### 🔴 A3. No feedback loop at all
`completeRoutine()` records nothing. Per-step actual durations are never captured; only the aggregate `accumulatedRoutineDeltaSeconds` exists. After completion the idle screen still says "22 MIN" (the planned time), not the actual. This is goal #3 entirely missing.

### 🟠 A4. Pausing shifts the displayed routine start time
`pauseRoutine()` sets `routineStartDate = nil`; `startRoutine()` recomputes it as `now − elapsed`, which excludes paused time. So the "started at" label drifts later by the pause length, and `stepStartDate` drifts the same way. Any future "average start time" stat built on this would be wrong. Keep an immutable `sessionStartedAt` and track `pausedSeconds` separately.

### 🟠 A5. Editing the routine while paused corrupts position
Position is tracked by `currentIndex` (an Int), and `pausedRoutineElapsedSeconds` is derived from `elapsedSecondsBeforeCurrentStep`. Deleting or reordering a step *before* the current one while PAUSED silently moves the user to a different step. `handleRoutineChanged()` only guards `currentIndex >= steps.count`. Track the current step by `persistentModelID`, or reset the run (with a warning) on structural edits.

### 🟠 A6. Alerts are too weak for the use case
- Step transitions play `SystemSoundID 1104` (the keyboard tick) via `AudioServicesPlaySystemSound`, which is quiet and silenced by the ringer switch. Morning phones are often on silent.
- No haptic on auto-advance (only on manual checkmark tap).
- No `UNUserNotificationCenterDelegate`, so notifications never show while the app is in the foreground.
- No repeated nudge when a manual step runs overtime and the app is backgrounded; one "X is done" ping, then silence.

### 🟠 A7. Notification permission prompt covers the running timer
`requestPermissionAndScheduleNotifications()` is first called from `startRoutine()`, so on first use the system dialog appears on top of a timer that is already counting (verified in simulator). Ask on the idle screen (e.g. in `ContentView.task` after seeding) or before starting the clock.

### 🟠 A8. VoiceOver reads everything twice
`InvertingFillView` renders `content` twice (black-on-white and white-on-black, masked). Both copies are in the accessibility tree, including two "notes" buttons. Add `.accessibilityHidden(true)` to the masked copy, or restructure with `blendMode(.difference)`.

### 🟡 A9. Notification cleanup is fragile
`cancelRoutineNotifications()` removes identifiers `routine-step-0…99` (hard cap of 100 steps) and never clears *delivered* notifications, so stale "Stretch is done" banners remain in Notification Center after returning to the app. Use `removeAllPendingNotificationRequests()` + `removeAllDeliveredNotifications()` (the app only schedules its own).

### 🟡 A10. Timer tick is unaligned
`runCountdownTask` sleeps a flat 1 s from whenever it started, so the displayed seconds occasionally skip or hold for ~2 s. Sleep until the next whole second, or drive `now` with `TimelineView(.periodic(from:by:))`. Also `routineSignature` (a string join over all steps incl. notes) is recomputed on every 1 s tick; cheap today, but it is an odd change-detection mechanism — prefer observing the model.

### 🟡 A11. Project settings
- `IPHONEOS_DEPLOYMENT_TARGET = 26.0` but CLAUDE.md says iOS 17+. Every API used is available on 17 (`ContentUnavailableView`, `@Bindable`, two-param `onChange`, `.toolbar(_:for:)`). Pick one; 17.0 is recommended unless the owner only cares about their own device.
- Display name shows as "RISE_RoutineTimer" in system dialogs. Set `INFOPLIST_KEY_CFBundleDisplayName = RISE`.
- Landscape is enabled for iPhone but the active screen layout is portrait-only (fixed height fractions). Lock to portrait.
- `SWIFT_VERSION = 5.0` is fine; note it before enabling strict concurrency.

### 🟡 A12. Seeding and empty state
`seedStarterRoutineIfNeeded()` reseeds whenever `steps.isEmpty`, so a user who deliberately deletes all steps gets the starter routine back on next launch. Use a one-time `hasSeeded` flag (UserDefaults) and offer "Restore starter routine" explicitly.

### 🟡 A13. Editor rough edges
- Setting 0 min 00 sec silently stores 1 s; the wheel then shows "0 min 01 sec" on reopen. Clamp to a minimum of 5–10 s and show it.
- No delete from within the editor; no duplicate step.
- Empty title allowed (timer shows a blank heading).
- Two side-by-side `.wheel` pickers inside a `Form` are known to have touch-target bleed on some iOS versions; verify on device.
- `@Bindable` edits rely on SwiftData autosave; fine, but an explicit save on disappear is cheap insurance.

### 🟡 A14. Copy and consistency
- Last step shows "NEXT: ROUTINE COMPLETE" — should read "LAST STEP".
- Edit list uses system font for metadata ("2 min"), Run list uses the receipt font ("2 MIN"). Pick one.
- "Edit" toolbar button sits above an "Edit" tab.
- `analogFont(_:weight:)` ignores `weight`; `digitFont` is identical to `analogFont`. Collapse or make meaningful.

### 🟡 A15. Dark mode
Idle screen adapts to dark mode; active screen is hardcoded white/black. Probably intentional, but decide and document it.

### 🟡 A16. No tests, engine logic trapped in the view
15 `@State` vars with subtle invariants (`pausedRemainingSeconds` vs `stepEndDate` vs `routineStartDate`) and no way to test them. Everything in sections B and C gets easier and safer after extracting an engine.

---

## B. What is missing for the product goals

### Goal 2 — Active timer (in addition to fixes above)
- **Pause, end routine, and "undo last checkmark"** on the active screen. The 144 pt checkmark is easy to hit by accident; undo matters.
- **Ahead/behind indicator** during the run ("−1:30 ahead" / "+2:05 behind"), not just a shifting end time. The math already exists (`accumulatedRoutineDeltaSeconds + currentOvertimeSeconds`).
- **Reliable audio**: bundled sound played through `AVAudioPlayer` with `AVAudioSession` category `.playback` so it is audible on silent, plus `UINotificationFeedbackGenerator` on every transition.
- **Overtime nudges**: for manual steps, schedule notifications at +1, +3, +5 min past planned.
- **Live Activity / Dynamic Island** (ActivityKit + widget extension): current step, countdown, next step, on the lock screen. This is the single biggest UX upgrade for a phone that is locked most of the routine. Larger lift; phase 4.

### Goal 3 — Get better every day (all new)
- **`RoutineSession` model**: `startedAt`, `endedAt`, `plannedSeconds`, `actualSeconds`, `pausedSeconds`, `completed: Bool`, and `steps: [StepRecord]` where `StepRecord` = `{ title, plannedSeconds, actualSeconds, wasAutoAdvanced }`. Store `steps` as a `Codable` array attribute (no relationship, no migration headaches).
- **Completion summary sheet** on finish: actual vs planned, per-step over/under bars, ahead/behind total, comparison to personal average, streak.
- **History tab**: session list, average completion time, average start time, best time, 7/30-day trend, streak.
- **Per-step insights**: average actual vs planned per step → "You finish Stretch 2 min early on average. Set it to 3 min?" with one-tap apply. This is the "get more efficient" engine.
- **Idle screen context**: "Yesterday 19:32 · Avg start 6:42am".
- Record abandoned sessions too (`completed = false`) so "how often do I bail" is visible.

### Goal 1 — Design the routine
- **Target end time** ("Out the door by 7:30") → idle screen shows "Start by 7:08"; during the run, on-track/behind is measured against the target, not just the plan. Optional daily reminder at start-by time.
- Step icons (existing backlog #5).
- Routine-level vertical progress bar (existing backlog #2). Recommend deprioritizing in favor of the ahead/behind text + existing dots, but keep.
- Editor polish from A13; duplicate step; restore starter routine.

---

## C. Proposed execution plan

### Run 1 — Foundation + timer must-haves ✓ DONE (2026-09-06)

Everything below shipped; 23 engine unit tests pass. Also added: voice announcements (AVSpeechSynthesizer, toggle in the toolbar menu), the ahead/behind label on the active screen, a completion line on the idle screen (actual time + delta), and the tab renamed to "Routine". Not yet verified on a physical device: audio on the silent switch, ducking, haptics.
1. **Extract `RoutineEngine`** (`@Observable final class`) from `RoutineTimerView`:
   - Explicit state enum: `idle`, `running`, `paused`, `complete`.
   - Immutable `sessionStartedAt`, `pausedSeconds`, per-step `actualSeconds` array, current step tracked by model ID.
   - Pure computed values: remaining, overtime, fill progress, projected end, ahead/behind delta.
   - Add a unit-test target; test early finish, overtime, pause/resume, auto-advance chains, background catch-up, structural edits while paused.
2. **Persist the engine snapshot** (`Codable` → UserDefaults or a single SwiftData row) on every transition; restore on launch, catching up on wall-clock time.
3. **Active screen controls**: pause, end routine (confirm), undo last checkmark. Keep them visually quiet to preserve the design.
4. **Alerts**: `AVAudioPlayer` + `.playback` session, haptics on every transition, foreground notification delegate, overtime nudges, `removeAll…` cleanup.
5. **Permission timing**: request on idle screen, not on Start.
6. **Small fixes**: A4, A8, A10, A11 (target + display name + portrait), A12, A14.

### Run 2 — Feedback loop ✓ DONE (2026-09-06)

Shipped: `RoutineSession` SwiftData model (step results stored as a Codable array, every property defaulted for CloudKit), `SessionRecorder` fed by engine events (abandoned runs kept only if a step was completed), `SessionSummaryView` sheet on completion, `HistoryView` tab (average / best / average start / streak tiles, 5-vs-5 trend, per-step suggestions with one-tap apply, swipe-to-delete), `RoutineStats` pure math with 7 unit tests, and a "Last X · usually start Y · N day streak" line on the READY screen.
7. `RoutineSession` + `StepRecord`, saved on complete and on end-early.
8. Completion summary sheet.
9. History tab with averages, trend, streak.
10. Per-step suggestions with one-tap apply.
11. Idle screen context line.

### Run 3 — Planning + polish ✓ DONE (2026-09-06)

Shipped: `TargetSchedule` (finish-by time stored as minutes after midnight; start-by, spare time, reminder components; unit tested), Routine tab "Target" section with time picker and optional daily start-by reminder (run alerts are now cancelled by identifier prefix so the reminder survives), start-by guidance on the READY screen, "X TO SPARE / PAST TARGET" line on the active screen, emoji step icons (model field, editor field limited to one grapheme, shown in all three lists and the active screen), delete from the editor, duplicate via leading swipe, empty-title guard, Restore Starter Routine in the tab menu. The routine-level vertical progress bar was skipped: the ahead/behind and target lines cover the need.
12. Target end time and start-by computation.
13. Step icons.
14. Editor polish (A13), duplicate step, restore starter routine.
15. Routine-level progress bar if still wanted.

### Run 4 — Active screen rebuild + morning accountability ✓ DONE (2026-09-06)

Owner's brief: pull in the tracking from the MorningCheckin web app, and make the running screen feel like a
premium iOS app while keeping the FLIP timer's minimal-tech look.

**Active screen.** Rebuilt as `ActiveRoutineView`. The blend-mode fill was replaced with FLIP's two-layer
`InvertingFillView` (white page + dark type, coloured page + white type, masked), so type stays crisp across the
fill line, emoji render without an escape hatch, and the fill can be coloured. The fill colour is now the
ahead/behind signal (`RoutinePace`: green on plan → ochre slipping → deep red behind, the last matching
MorningCheckin's over-budget ink). Magic height fractions and `.position()` arithmetic are gone; controls sit in a
sibling overlay as white chips (undo · complete · notes, centred with placeholders so the big button never moves),
and the old four-number corner is now three aligned micro-stats.

**Accountability.** `MorningLog` records the wake time; `MorningRecord.join` merges it with `RoutineSession`.
`MorningMetrics` ports `metrics.js` wholesale: snooze, activation latency, duration, 7/30-day rolling baselines,
wake spread (standard deviation), weekly budgets counting overruns only, missed-day counters, streak, and insight
sentences — 23 unit tests. A new **Today** tab is the landing screen: wake CTA ("I'M AWAKE" → "START ROUTINE"),
day timeline, live performance tiles with a selectable baseline, budget bars and an insight card. History gained
Swift Charts (snooze bars, activation bars, duration line, each with an average rule), the rolling-baselines
table and missed days. Wake goal and budgets are editable on the Routine tab; `DebugSeed` provides 13 days of
sample history in DEBUG builds.

Not done: negative activation is reported as "—" rather than prompting a fix; the timeline is not scrubbable
(the web app's "touch to explore"); Today does not yet surface per-step suggestions.

### Run 5 — Active-screen feedback pass ✓ DONE (2026-09-06)

Six items from the owner after using Run 4:

1. **Auto-next was invisible.** A status pill under the countdown now reads `AUTO-ADVANCES` or `TAP WHEN DONE`.
2. **Overtime needed to be glanceable, but the colour must not persist across steps.** The fill was repainted from
   the cumulative `scheduleDeltaSeconds` to a per-step `StepPace`: the chosen colour on time, amber once the step
   runs over, red past two minutes. It resets each step on its own. Only manual steps can reach it, since
   auto-next steps are advanced the moment their time is up. The pill also switches to `OVERTIME · TAP WHEN DONE`,
   so the state does not depend on colour alone.
3. **Pausing looked like ending.** `PauseOverlay` keeps the user on the timer and blurs it behind a scrim.
   Blur rather than a heavier scrim: the overlay restates the step and countdown, and dimming alone left the
   dot-matrix type below legible as a second, offset copy.
4. **The end-routine prompt was ugly.** `ReceiptDialog` — hard-bordered card, tracked receipt caps, a rule under
   the title, square filled/outlined buttons. Used for confirmations shown over the timer.
5. **Selectable timer colour.** `FillTheme`: Forest, Ocean, Indigo, Plum, Graphite, picked in the Routine tab.
   No ambers or reds — they are reserved for overtime, and a test enforces it.
6. **Icon entry only kept the first character.** `GlyphPickerView` + `GlyphCatalog`: a searchable, curated set of
   typographic marks and emoji with keywords, plus an explicit slot for a single typed letter or number.

72 tests. Not done: settings-surface dialogs still use the system sheet; the glyph catalog is curated rather than
the full emoji set.

### Run 6 — Active-screen density pass ✓ DONE (2026-09-07)

The owner found the screen too dense and disliked the auto-advance badge. Five candidate layouts were mocked in
the real font (a throwaway `MockupGalleryView`, since deleted) and style **C — "silent until it matters"** was
picked, then refined:

- **Removed:** the PACE / DONE / SPARE row, the step time-range line, the `AUTO-ADVANCES` pill, the undo button
  *and the go-back-a-step feature itself* (`undoLastStep` and `.steppedBack` are gone from the engine), and the
  notes chip. The screen went from ten bands to five.
- **One line, conditionally.** Under the countdown, only when the routine is at risk: `WON'T MAKE 7:30AM`, else
  `X BEHIND` past `RoutinePace.behindAlertSeconds`. Step-level overtime stays the fill's job.
- **Notes moved to the step name.** Tapping the title opens the sheet; the tap target rides an anchor preference
  so it can live in the control overlay while the text stays inside the (twice-built) fill.
- **The checkmark is the auto-next indicator.** Large and solid when the step needs the tap; small and dimmed when
  it will advance on its own. A depleting progress ring was tried and rejected — a second progress indicator
  alongside the fill, saying the same thing in a different shape.

Known tradeoff the owner accepted: a manual step that is still on time now has no *positive* signal, only a bigger
button. If it turns out to be unclear in real use, the cheapest fix is one line of `TAP WHEN DONE` for manual
steps only, leaving auto steps silent.

### Run 7 — Notes, skip and display toggles ✓ DONE (2026-09-07)

- **Notes chip returns**, beside pause, and is always available — the point is to *capture* a thought mid-routine,
  not only to read one. The step name stays a tap target too. The sheet is now editable, writes through to
  SwiftData, and pushes the result into the run's frozen copy via `RoutineEngine.updateNotes`.
- **Notes body set in the system font.** The receipt face was unreadable at paragraph length.
- **`RoutineStep.autoShowNotes`** (default on, per-step) opens the note as the step starts. Toggled by an eye
  button in the sheet's top-right corner, and also from the step editor.
- **Step start/end times** moved to the top of the screen, behind a toggle; **NEXT** got a toggle too. Both live in
  the Routine tab's "Timer" section.
- **Skip** sits to the right of the checkmark, with a three-way prompt: skip it / move to the end / cancel. `ReceiptDialog` was generalised to take any
  number of stacked actions.
- **`TAP WHEN DONE`** now appears on manual steps only, closing the gap left when the auto-advance badge was
  removed. Auto steps stay silent.

78 tests. Data-shape notes: `RunStep` gained a hand-written `init(from:)` so old persisted runs still decode, and
`StepResult.skipped` is Optional for the same reason.

### Run 8 — Light mode, saturated palette, control polish ✓ DONE (2026-09-07)

- **Light mode only**, set at the app level so system sheets and dialogs follow.
- **Saturated palette.** The deep desaturated inks read as muted pastel. `FillTheme` is now green / ocean /
  indigo / violet / ink in the FLIP timer's register, with brighter overtime amber and red to match. Renaming the
  cases means a stored `forest`, `plum` or `graphite` selection falls back to the default (`green`);
  `indigo` and `ocean` survive.
- **Notes sheet:** close button removed (drag down or tap outside), and the auto-open control is a plainly
  labelled switch at the foot rather than an unlabelled eye icon in the toolbar.
- **Display options** (step times, next step) are now behind a chip in the running screen's top bar as well as in
  the Routine tab.
- **Complete button** is the single ghosted size for every step. Auto-next is a **dashed** border, manual is a
  **solid** border.

Tradeoff worth watching: with size and weight no longer varying, the required/optional distinction rests on
border style alone, which is subtler than the old big-vs-small contrast.

### Run 9 — Step-type badge ✓ DONE (2026-09-07)

Dropped the `TAP WHEN DONE` / `OVERTIME · TAP WHEN DONE` line: the fill turning amber and then red already
carries step-level overtime, so the words were restating what the colour showed. In its place, a small bordered
`AUTO` / `MANUAL` capsule under the step name — a statement of what kind of step it is, not a status message, so
the wording never changes mid-step. The checkmark's dashed/solid border still echoes it.

### Run 10 — App icon ✓ DONE (2026-09-07)

A dot-matrix sunrise — a sun ring with five rays over a full-width rule — built as a sibling to the FLIP timer's
dot-matrix hourglass, in the same black-on-white dot construction. Light / Dark / Tinted variants, the dark one a
straight inversion. Generated by `Tools/make_app_icon.py`, whose header records the shapes that failed first so
they are not retried: an arc sitting on the horizon (reads as a tent), a filled disc (a stepped pyramid), a small
outlined circle (a rounded square), and an angle-walked ring (lumpy on the diagonals).

### Run 11 — Undo wake, brand timeline, editing moved ✓ DONE (2026-09-07)

- **Undo wake up** under the Start Routine button, confirmed through `ReceiptDialog`. "I'm awake" is one tap and
  starts the clock on the morning's whole scoreline, so a mis-tap needed a way back.
- **Timeline recoloured** to the app's own palette: waking is scored on the same green / amber / red the timer
  uses for pace, activation is indigo, and the routine leg takes whatever colour the user picked for the timer.
- **The Routine tab is gone.** Step editing hangs off a pencil in the Run tab's top-left; what remains is a
  **Settings** tab (timer appearance, morning goal, target, DEBUG tools), moved to the end of the tab bar.
- **Idle step rows compacted** so a whole routine fits without scrolling.

### Run 12 — Owner's real routine, and a persistence bug ✓ DONE (2026-09-07)

- **The owner's actual 16-step routine** is now the seed (44 min 10 s). `RoutineStep.starterRoutineVersion`
  gates it: bumping the version replaces the saved routine on next launch, which is how a new routine reaches a
  device that already has one. It discards on-device edits, so only bump it when a reload has been asked for.
- **Fixed: an ended routine came back from the dead.** The run lived in `UserDefaults`, whose writes `cfprefsd`
  batches; a removal could still be pending when the process was killed, while the earlier save had committed.
  `FileRunStore` now writes an atomic JSON file in Application Support. Its migration off `UserDefaults` needs its
  own marker file — keying it on "the run file exists" reintroduced the bug, since ending a routine deletes that
  file. Six tests cover it.

### Run 13 — Brand-language sheets ✓ DONE (2026-09-07)

The Display and Notes sheets were still stock `Form`/`Toggle` chrome. Both now use a new `ReceiptUI` kit —
square-stroked buttons, a square switch, tracked-caps titles over a hard rule — on an opaque background (the
translucent default let the timer's fill bleed through the note text).

The notes sheet also changed behaviourally: reading and editing are separate modes, so a stray tap no longer
opens the keyboard and no keystroke is saved until Save is pressed. Cancel with changes confirms first, the sheet
cannot be swiped away mid-edit, and autocorrect is off (it mangles transliterated Arabic). Chrome follows the
detent — at medium it is note text and the auto-open pill only; the step title and Edit appear at full height.

### Run 14 — Routine end time ✓ DONE (2026-09-07)

A third optional line on the running screen: `ROUTINE ENDS 5:20AM`, under the next-task preview, behind its own
toggle in both the Display sheet and Settings. Labelled rather than a bare time so it cannot be misread as the
current step's end, which is the line at the top.

### Run 15 — Bottom bar ✓ DONE (2026-09-07)

The running screen's top row — four chips plus a strip of step dots — ran edge to edge with a sixteen-step
routine. All of it is now one floating bar at the bottom, in the shape of Arc's URL bar: pause left, `DONE AT
5:20AM` centre, chevron right. Its top edge fills in proportion to the whole routine (no step ticks — tried in
thought, judged noise). Tapping the centre shows elapsed time for a moment. The chevron raises `RunSheetView`: the
step's note (opens the separate notes sheet), the run's numbers that were cut for density, the two display
toggles, and End Routine. The routine-end toggle from Run 14 went away — the end time is now structural to the bar.

### Run 16 — Friction pass ✓ DONE (2026-09-07)

- **Bar progress is by plan position** (`routinePlanProgress`), not elapsed time: finishing a step early now
  jumps the edge to the boundary instead of barely moving. Three engine tests.
- **Run sheet:** started/done-at collapsed into one `5:12 – 5:57 AM` range; new **This step** section with
  planned, average actual over recent runs, and the difference against plan (`RoutineStats.averageActual`).
- **Bar centre is a toggle** — tap back to `DONE AT` at once, or it reverts after 3.5 s — and the two readings
  roll vertically instead of the default crossfade.
- **Adding a note is one tap:** "Add" opens the notes sheet fully with the keyboard up (`startEditing`). The
  first cut presented the sheet with a Bool plus a separate editing flag, and the flag kept arriving as false —
  the sheet's own `onDismiss` reset it during the hand-off from the run sheet. Now presented by item
  (`NotesRequest`), which carries the flag and cannot be zeroed out underneath.
- **The idle list edits in place:** tap a step to edit it, `+` on a connector to insert exactly there, `ADD STEP`
  to append. Going through the pencil was a detour nobody remembered to take.
- Step-times toggle removed from Settings; it lives on the run sheet.

### Run 17 — Idle timer, sheet grouping, Live Activity (2026-09-07)

- **Screen stays awake app-wide** during a run. The Run-tab-only version turned the idle timer back on when you
  switched tabs, so reading Today mid-routine could let the phone sleep.
- **Run sheet sections are boxed** — titled hairline groups, tighter rows — so grouping is drawn, not implied.
- **Live Activity / Dynamic Island.** New `RISE_RoutineTimerWidgetExtension` target (`RISE_RoutineTimerWidget/`),
  `RoutineActivityAttributes` shared with the app through a build-file exception set, and
  `RoutineLiveActivityController` mirroring the engine on every event / on becoming active. Lock Screen banner:
  progress edge, icon + title, AUTO / MANUAL / PAUSED badge, STEP n OF m, NEXT, the receipt-face countdown, DONE
  time. Island: expanded (title, badge, countdown, progress, NEXT / DONE), compact (icon · countdown), minimal
  (theme dot). Verified in the simulator on Home, expanded, and Lock Screen; the countdown is self-running from
  the step dates, so the known limit is that a step *transition* needs the app awake — on a locked phone the
  banner sits at 0:00 on the step that was current when the app last ran, and the local notifications carry the
  boundary. A background audio session is the only way past that and was deliberately not added.
- Fixes on the way: the expanded island's trailing countdown had `maxWidth: .infinity` and squeezed every title
  to "DRINK WA…". The leading region now carries `priority: 1`; a `maxWidth: .infinity` on it was tried first
  and blanked the trailing and bottom regions.

### Run 18 — Draft editor, quieter chips (2026-09-08)

- `StepEditorView` edits a draft: Cancel / Save (or Add for a new step), discard confirmation, no swipe-away when
  dirty, no back button on a push. `StepEditRequest` carries `isNew` so a cancelled new step is deleted rather
  than left as "New Step".
- Run-tab idle rows no longer print the current step's note.
- Check / skip chips are 72 % white instead of solid.
- **Run-tab list edits by selection.** The toolbar pencil and the always-on `+` connectors are gone. Tap a step:
  it highlights, `+` appears above and below it, and pencil (edit) / arrow (stats) buttons appear on the right.
  New `StepStatsSheet` (plan, average / vs plan / best / last / skipped over recent runs, one-tap suggestion)
  backed by `RoutineStats.history(forStepID:)` (`StepHistory`, tested). The full list (reorder / delete /
  restore) moved to Settings › Routine.
- **Swipe-to-delete and drag-to-reorder on the Run tab.** The idle list became a plain `List`. A drag only sets a
  pending order; CANCEL / SAVE ORDER replace the Start button until it is confirmed or dropped. The chime / voice
  speaker menu left the Run toolbar for Settings › Alerts, leaving the toolbar empty.
- A pending reorder now locks the screen: tab bar hidden, no selection / swipe / add / sheets until Cancel or Save.
- **App Intents:** Start Morning Routine (opens the app on Run) and I'm Awake (confirms, then logs the wake time;
  does not open the app). Both listed as App Shortcuts. Meant for a charger-unplug automation in Shortcuts.
- Editor: red asterisk on Task, Add / Save dims and pulses the missing field on tap, ✕ on a new step's sheet.
- Active screen: notes sheet slides in a beat after the step lands; a `note.text` button beside pause when the
  step has a note; the check / skip chips are drawn inside the inverting fill's layers, so the fill line
  crosses them like the type rather than flipping them whole.
- Both chips carry the same dashed border now; the AUTO / MANUAL capsule is the only auto-next signal.
- Third App Intent: Open Today.

### Later (next)
17. iCloud sync via SwiftData + CloudKit (decide **before** run 2: CloudKit requires all properties to have defaults and all relationships optional, which constrains the `RoutineSession` design).
18. Multiple routines / profiles if "our routine" means more than one person.

---

## D. Open questions (non-blocking; defaults in bold)

1. "Our" routine: one person, or multiple people/routines? **Default: single routine, model it so a `Routine` parent can be added later.**
2. Deployment target: **17.0** or keep 26.0?
3. Active screen: keep the strict white/black look regardless of dark mode? **Default: keep.**
4. iCloud sync wanted eventually? **Default: design the session model to be CloudKit-compatible (defaults on every property).**
5. Update CLAUDE.md: mark backlog #1 and #2 as superseded by this plan, fix the iOS version line.
