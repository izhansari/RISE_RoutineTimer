# RISE RoutineTimer

SwiftUI iOS app for running a timed morning routine. Single-routine model: one ordered list of steps, each with a title, duration, auto-next flag, and optional notes. Uses SwiftData for persistence. Targets iOS 17+ (deployment target 17.0; built with Xcode 26). Product direction: a sleeker, single-purpose take on Routinery (voice-guided step timer, session summaries) without the clutter or subscription. See `PLAN.md` for the audit and roadmap.

## Project layout

```
RISE_RoutineTimer/
  RISE_RoutineTimerApp.swift    – creates the RoutineEngine + RoutineAlertCoordinator, injects engine into the environment
  ContentView.swift             – root TabView; seeds starter routine once; asks notification permission on the idle screen
  RoutineStep.swift             – SwiftData model (has a stable `stepID: UUID`) + starter routine seeds
  RunModels.swift               – Codable value types: RunStep, StepResult, RoutineRun, SessionResult, PlannedAlert
  RoutineEngine.swift           – @Observable timer engine; all time math; persists the run via RunStore (UserDefaults)
  RoutineAlertCoordinator.swift – turns engine events into chimes/voice/haptics and local notifications
  RoutineAlerts.swift           – AVAudioPlayer chimes (audible on silent), AVSpeechSynthesizer voice, haptics
  RoutineNotificationManager.swift – schedules the engine's PlannedAlerts as local notifications
  RoutineTimerView.swift        – "Run" tab: idle screen (ready/paused/complete) + active timer screen
  RoutineListView.swift         – "Routine" tab: reorderable step list
  StepEditorView.swift          – per-step form (title, duration, auto-next, notes)
  TimeFormatting.swift
  FontHelpers.swift
  Sounds/                       – generated chime .wav files
RISE_RoutineTimerTests/
  RoutineEngineTests.swift      – engine unit tests driven with synthetic dates
```

Run tests with:

```
xcodebuild -scheme RISE_RoutineTimer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Key architecture notes

- `RoutineStep` is the only SwiftData model. `sortOrder: Int` preserves list order since SwiftData does not guarantee it. `stepID` is a stable UUID for matching steps across sessions.
- **All timer logic lives in `RoutineEngine`**, not in views. When a run starts the steps are frozen into `[RunStep]`, so editing the routine mid-run cannot corrupt it. Every value the UI shows is derived from `run` + `now`. The engine emits `Event`s (`stepStarted`, `overtimeStarted`, `completed`, …) that `RoutineAlertCoordinator` turns into feedback.
- The run is saved to UserDefaults after every mutation and restored at launch (running runs catch up on wall-clock time; runs older than 12 h are dropped). Pauses are tracked separately so the real start time never shifts.
- `scheduleDeltaSeconds` (positive = behind) and `projectedEndDate` are the "ahead/behind plan" signals. `plannedAlerts(at:)` is the single source of truth for what notifications to schedule.
- The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; pure value types are marked `nonisolated`.
- The `InvertingFillView` draws content once in white with `.blendMode(.difference)` over a white page that fills black from the bottom (`currentStepFillProgress`).
- `analogFont()` / `digitFont()` are helpers from `FontHelpers.swift` for the "Fake Receipt" custom font.
- Add unit tests for any change to engine time math; they run in seconds and use synthetic dates.

## Feature backlog

### 1. Session history
Record completed routine sessions and display aggregate stats.

- The engine already produces a `SessionResult` (start/end, planned vs actual, per-step `StepResult`s, paused time, completed flag) via the `.completed` / `.abandoned` events. Persist it.
- Add a new SwiftData model `RoutineSession` (store the step results as a Codable array attribute).
- Show a "History" tab or sheet with:
  - List of past sessions (date + how long the routine took).
  - Average completion time (how long the routine took on average).
  - Average start time (clock time the routine was started on average).
- Keep it lightweight — no server, purely local.

### 2. Routine-level progress bar on active timer screen
Replace or augment the left edge of the active timer screen with a vertical bar showing where we are across the *entire* routine (not just the current step).

- Bar runs full screen height, anchored left.
- Start time label at the bottom, projected end time at the top.
- Indicator moves from bottom to top proportionally to elapsed routine time vs. total planned duration.
- If a step is completed early, the indicator jumps ahead (routine finishes earlier → end time adjusts down, indicator advances faster).
- If a step runs over time, the indicator stalls (end time extends, indicator stays put until the step is finished).
- `RoutineEngine.activeElapsedSeconds`, `plannedTotalSeconds`, `scheduleDeltaSeconds` and `projectedEndDate` already have the math needed. The active screen already shows an "X:XX AHEAD/BEHIND" label.

### 3. ~~New step immediately opens editor~~ ✓ Done
`RoutineListView` now uses a `NavigationPath`-backed `NavigationStack`. `addStep()` inserts the step, saves, then calls `path.append(step)`. `.navigationDestination(for: RoutineStep.self)` handles routing to `StepEditorView`.

### 4. ~~Notes shown on demand via sheet during active timer~~ ✓ Done
Inline notes text removed from `activeContent`. A `note.text` icon button now appears in the bottom bar when the current step has notes; tapping it sets `showingNotes = true`, which triggers a `.sheet` attached to `activeRoutineScreen`. Button is hidden when there are no notes.

### 5. Icons / emojis per step
Allow each step to have an optional emoji or SF Symbol so the step is identifiable at a glance.

- Add `var icon: String` (or `iconEmoji: String`) to `RoutineStep`. Default `""`.
- In `StepEditorView`, add a field to set an emoji (text field capped at one grapheme cluster) or a symbol picker.
- Display the icon in:
  - `IdleStepRow` (left of or replacing the step-number circle when an icon is set).
  - The active timer screen title area.
  - `RoutineStepRow` in the edit list.

### 6. ~~Remove Back / Reset / Skip buttons from the Run tab idle screen~~ ✓ Done
Only the primary Start / Resume / Start Over button remains on the idle screen (plus a small "End Routine" link while paused). Pause, end and undo-last-step live on the active timer screen.

### 7. ~~Engine extraction, persistence, pause/end/undo, real alerts~~ ✓ Done (Run 1 of PLAN.md)
See the architecture notes above and `PLAN.md` section C.
