# RISE RoutineTimer

SwiftUI iOS app for running a timed morning routine. Single-routine model: one ordered list of steps, each with a title, duration, auto-next flag, and optional notes. Uses SwiftData for persistence. Targets iOS 17+.

## Project layout

```
RISE_RoutineTimer/
  ContentView.swift           – root TabView; seeds starter routine on first launch
  RoutineStep.swift           – SwiftData model + starter routine seeds
  RoutineTimerView.swift      – "Run" tab: idle screen + active timer screen
  RoutineListView.swift       – "Edit" tab: reorderable step list
  StepEditorView.swift        – per-step form (title, duration, auto-next, notes)
  RoutineNotificationManager.swift
  RoutineSoundPlayer.swift
  TimeFormatting.swift
  FontHelpers.swift
```

## Key architecture notes

- `RoutineStep` is the only SwiftData model. `sortOrder: Int` preserves list order since SwiftData does not guarantee it.
- `RoutineTimerView` drives the timer with a `Task` that fires every second and updates `now: Date`. All time math is date-based (`stepEndDate`, `routineStartDate`) so background suspensions don't break the countdown.
- `accumulatedRoutineDeltaSeconds` tracks how much ahead/behind of schedule the routine is as steps are completed early or late.
- The `InvertingFillView` fills from the bottom up to show per-step progress (black fills white from bottom). The fill fraction is `currentStepFillProgress`.
- `analogFont()` / `digitFont()` are helpers from `FontHelpers.swift` for the "Fake Receipt" custom font.

## Feature backlog

### 1. Session history
Record completed routine sessions and display aggregate stats.

- On `completeRoutine()`, persist a session record: start time (`Date`), total duration (seconds), and per-step actual durations.
- Add a new SwiftData model `RoutineSession` (or store as JSON in a simple model).
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
- The existing `routineElapsedSeconds` and `adjustedRoutineDurationSeconds` computed properties already have the math needed.

### 3. New step immediately opens editor
In `RoutineListView.addStep()`, after inserting the new `RoutineStep` into the model context, navigate directly to `StepEditorView` for that step instead of just appending it to the list.

- Use a `@State private var navigateToNewStep: RoutineStep?` + `NavigationLink(value:)` or programmatic `NavigationPath` push.
- The new step is already saved; the editor just needs to be presented for it.

### 4. Notes shown on demand via sheet during active timer
Currently notes are always shown (dimmed, bottom of screen). Replace this with:

- A button (e.g. a small note icon) visible during the active timer screen.
- Tapping it presents the current step's notes as a `.sheet`.
- If the current step has no notes, the button is hidden or disabled.
- Remove the always-visible inline notes text from `activeContent`.

### 5. Icons / emojis per step
Allow each step to have an optional emoji or SF Symbol so the step is identifiable at a glance.

- Add `var icon: String` (or `iconEmoji: String`) to `RoutineStep`. Default `""`.
- In `StepEditorView`, add a field to set an emoji (text field capped at one grapheme cluster) or a symbol picker.
- Display the icon in:
  - `IdleStepRow` (left of or replacing the step-number circle when an icon is set).
  - The active timer screen title area.
  - `RoutineStepRow` in the edit list.

### 6. Remove Back / Reset / Skip buttons from the Run tab idle screen
In `RoutineTimerView.idleScreen`, delete the `HStack` containing the Back, Reset, and Skip buttons that sits below the primary Start/Pause button. Keep the primary button only.
