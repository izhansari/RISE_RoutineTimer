# RISE RoutineTimer

SwiftUI iOS app that runs a timed morning routine **and scores the morning around it**.

Single-routine model: one ordered list of steps, each with a title, icon, duration, auto-next flag and optional notes. Around that routine the app tracks three timestamps a day — wake, routine start, routine end — against a target wake time, which is where snooze, activation latency, the weekly budgets and the trend charts come from.

SwiftData for persistence. Targets iOS 17+ (deployment target 17.0; built with Xcode 26). Product direction: a sleeker, single-purpose take on Routinery (voice-guided step timer, session summaries) without the clutter or subscription. See `PLAN.md` for the audit and the run-by-run roadmap.

## Reference projects

Two sibling repos on this machine are the design references, and the owner refers to them by name. Read the local copies — they are the working versions.

- **`../MorningCheckin`** (also `github.com/izhansari/MorningCheckin`) — React/Vite + Neon. The accountability model came from here: `src/utils/metrics.js` is the direct source for `MorningMetrics.swift`, `HomeScreen.jsx` for the Today tab, `HistoryScreen.jsx` for the charts, `seedData.js` for `DebugSeed`. **Keep the two in agreement** when either side's math changes.
- **`../TwoMinRuleTimer`** ("the FLIP timer") — source of the shared visual vocabulary: the Fake Receipt font, `analogFont`/`digitFont`, tracked all-caps micro-labels, and the two-layer inverting fill. Re-read its `ReceiptUI.swift` and `ContentView.swift` before any visual change here.

Colours are deliberately carried across: the `behind` pace ink is MorningCheckin's over-budget `#7F2020`.

## Project layout

```
RISE_RoutineTimer/
  RISE_RoutineTimerApp.swift    – builds the ModelContainer, RoutineEngine and RoutineAlertCoordinator
  ContentView.swift             – root TabView (Today / Run / Routine / History); seeds the starter routine once

  — Model & math (all pure, all unit tested) —
  RoutineStep.swift             – SwiftData model (stable `stepID: UUID`) + starter routine seeds
  RoutineSession.swift          – SwiftData model for a finished run + SessionRecorder
  MorningLog.swift              – SwiftData model for the wake time + the join into MorningRecord
  RunModels.swift               – Codable value types: RunStep, StepResult, RoutineRun, SessionResult, PlannedAlert
  RoutineEngine.swift           – @Observable timer engine; all time math; persists the run via RunStore
  RoutineStats.swift            – stats over sessions: averages, streak, trend, per-step suggestions
  MorningMetrics.swift          – snooze / activation / duration, baselines, spread, budgets, missed days, insights
  TargetSchedule.swift          – finish-by target math: start-by time, spare time, reminder components
  RoutinePace.swift             – ahead/behind as three states + the fill colour for each

  — Feedback —
  RoutineAlertCoordinator.swift – turns engine events into chimes/voice/haptics and local notifications
  RoutineAlerts.swift           – AVAudioPlayer chimes (audible on silent), AVSpeechSynthesizer voice, haptics
  RoutineNotificationManager.swift – schedules the engine's PlannedAlerts as local notifications

  — Views —
  TodayView.swift               – "Today" tab (landing): wake CTA, day timeline, performance tiles, budgets, insight
  RoutineTimerView.swift        – "Run" tab: idle screen (ready/paused/complete); delegates the running screen
  ActiveRoutineView.swift       – the running-timer screen (see "Active screen" below)
  InvertingFillView.swift       – the two-layer colour-inverting fill
  SessionSummaryView.swift      – sheet shown when a routine completes
  RoutineListView.swift         – "Routine" tab: step list, Morning goal settings, finish-by Target
  StepEditorView.swift          – per-step form (icon, title, duration, auto-next, notes, delete)
  HistoryView.swift             – "History" tab: stat tiles, charts, suggestions, session list
  MorningChartsView.swift       – the charting half of History (Swift Charts)

  DebugSeed.swift               – DEBUG-only 13-day sample history
  TimeFormatting.swift
  FontHelpers.swift
  Sounds/                       – generated chime .wav files

RISE_RoutineTimerTests/
  RoutineEngineTests.swift      – engine time math driven with synthetic dates
  RoutineStatsTests.swift       – stats and suggestion tests
  MorningMetricsTests.swift     – snooze / activation / baselines / spread / budgets / missed days / streak
  TargetScheduleTests.swift     – target/start-by tests
```

## Build & test

```
xcodebuild -scheme RISE_RoutineTimer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

58 tests, all pure value-type math against synthetic dates — the suite runs in well under a second. The build should be warning-free; keep it that way.

The Xcode project uses synchronized buildable folders, so new `.swift` files dropped into `RISE_RoutineTimer/` or `RISE_RoutineTimerTests/` are picked up with no pbxproj surgery.

**Sample data:** in a DEBUG build, the Routine tab's ⋯ menu has *Seed Sample History* (13 days that gradually improve, with 2 missed days) and *Clear All History*. Use it rather than waiting two weeks to see the charts, baselines, budgets and streak logic.

## Key architecture notes

### Data

- **Three SwiftData models:** `RoutineStep`, `RoutineSession`, `MorningLog`. All are registered in the schema in `RISE_RoutineTimerApp.init()` — a new model must be added there *and* in the `#Preview` container in `ContentView.swift`.
- Every `RoutineSession` / `MorningLog` property has a default so the models stay CloudKit-compatible.
- `RoutineStep.sortOrder: Int` preserves list order, since SwiftData does not guarantee it. `stepID` is a stable UUID for matching a step across sessions as it gets renamed.

### The engine

- **All timer logic lives in `RoutineEngine`**, never in views. When a run starts the steps are frozen into `[RunStep]`, so editing the routine mid-run cannot corrupt it. Every value the UI shows is derived from `run` + `now`.
- The engine emits `Event`s (`stepStarted`, `overtimeStarted`, `completed`, …) that `RoutineAlertCoordinator` turns into feedback and `SessionRecorder` turns into history.
- The run is saved to UserDefaults after every mutation and restored at launch (running runs catch up on wall-clock time; runs older than 12 h are dropped). Pauses are tracked separately so the real start time never shifts.
- `scheduleDeltaSeconds` (positive = behind) and `projectedEndDate` are the ahead/behind signals. `plannedAlerts(at:)` is the single source of truth for what notifications get scheduled.

### Active screen

- `InvertingFillView` draws its content **twice** — a white page with dark type, and a coloured page with white type masked to the fill height — rather than the `.blendMode(.difference)` trick it used to use. That keeps type crisp *at* the fill line, lets emoji render normally (the old version needed a `.blendMode(.normal)` escape hatch), and allows a coloured fill at all.
- Two consequences the call site must respect:
  1. The masked copy is `.accessibilityHidden(true)`, so VoiceOver reads the screen once.
  2. **No interactive controls inside the content closure** — there would be two of every button, stacked. `ActiveRoutineView` keeps every control in a sibling overlay, styled as white chips so they read against both the white page and the coloured fill without per-layer colour maths.
- The type layer reserves a fixed-height slot for the control cluster, and both layers apply *identical* safe-area arithmetic (`bottomInset(_:)`, `nextZoneHeight`, `checkDiameter`). If the checkmark ever drifts onto the pace row again, that is the invariant that broke.
- The fill colour comes from `RoutinePace(deltaSeconds:)`, so the colour of the whole screen is the ahead/behind signal — which is why the old corner pile of four numbers could collapse into three aligned micro-stats.
- Everything **snaps**; it is not animated. `InvertingFillView` carries `.transaction { $0.animation = nil }` because the per-second tick invalidates that view directly (it is where the engine is read), so a modifier on an ancestor misses it and the digits crossfade. The countdown also carries `.contentTransition(.identity)`. Motion is limited to a press response on the controls. Same lesson the FLIP timer learned — don't reintroduce smooth fills or rolling digits.

### Morning accountability

- `MorningLog` stores **only** the wake time — the one thing the timer cannot work out for itself. Routine start/end come from `RoutineSession`. `MorningRecord.join(logs:sessions:)` merges them into one record per day (earliest run wins, so an evening run doesn't overwrite the morning).
- `MorningMetrics` does all the math and is a direct port of MorningCheckin's `metrics.js`. Weekly budgets count **overruns only** — being up early doesn't earn credit toward a later lie-in. Missed days never count today.
- Settings (`targetWakeMinutes`, snooze/activation budgets) live in `@AppStorage` via `MorningSettings`, edited in the Routine tab's *Morning goal* section.

### Conventions

- The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; pure value types and pure static functions are marked `nonisolated`. `TimeFormatting`'s string maths is `nonisolated`, but `shortClockTime(from:)` stays isolated because it shares a `DateFormatter`.
- `analogFont()` / `digitFont()` from `FontHelpers.swift` are the "Fake Receipt" face. Tracked all-caps at 9–11pt is the micro-label register.
- **Add unit tests for any change to the engine, stats, metrics or schedule math.** They are pure, they run in milliseconds, and they are the reason this codebase can be refactored confidently.

## Feature backlog

### Open

**Live Activity / Dynamic Island** *(next big item)* — current step, countdown and next step on the Lock Screen via ActivityKit. Needs a widget extension target. See PLAN.md "Later".

**Routine-level progress bar on the active screen** *(deferred)* — the PACE / DONE / SPARE micro-stats plus the rising fill cover the intent. Revisit only if a visual bar is still wanted; `activeElapsedSeconds`, `plannedTotalSeconds` and `projectedEndDate` have the math.

**Smaller, known gaps** — negative activation (a wake logged after the routine started) reports "—" rather than prompting a fix; the Today timeline is not scrubbable, unlike the web app's "touch to explore"; Today does not surface per-step suggestions.

### Done

- **Run 1** — engine extraction, run persistence, pause/end/undo, real chimes + voice + haptics, overtime nudges, notification permission moved off the running screen.
- **Run 2** — session history: `RoutineSession`, `SessionRecorder`, `SessionSummaryView`, the History tab, `RoutineStats` averages/streak/trend and per-step suggestions with one-tap apply.
- **Run 3** — finish-by target (`TargetSchedule`) with an optional start-by reminder, emoji step icons, editor delete/duplicate, empty-title guard, restore-starter-routine.
- **Run 4** — the active screen rebuilt around the coloured pace-driven inverting fill, plus the whole morning-accountability layer: wake logging, `MorningMetrics`, the Today landing tab, and Swift Charts in History.
- Smaller ones: new step opens its editor immediately (`NavigationPath`); notes shown on demand via a sheet from the active screen's notes chip; Back/Reset/Skip removed from the Run idle screen.
