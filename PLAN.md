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

### Later (next)
16. Live Activity / Dynamic Island.
17. iCloud sync via SwiftData + CloudKit (decide **before** run 2: CloudKit requires all properties to have defaults and all relationships optional, which constrains the `RoutineSession` design).
18. Multiple routines / profiles if "our routine" means more than one person.

---

## D. Open questions (non-blocking; defaults in bold)

1. "Our" routine: one person, or multiple people/routines? **Default: single routine, model it so a `Routine` parent can be added later.**
2. Deployment target: **17.0** or keep 26.0?
3. Active screen: keep the strict white/black look regardless of dark mode? **Default: keep.**
4. iCloud sync wanted eventually? **Default: design the session model to be CloudKit-compatible (defaults on every property).**
5. Update CLAUDE.md: mark backlog #1 and #2 as superseded by this plan, fix the iOS version line.
