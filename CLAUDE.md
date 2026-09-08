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
  RISE_RoutineTimerApp.swift    – builds the ModelContainer, RoutineEngine and RoutineAlertCoordinator; registers AppServices
  ContentView.swift             – root TabView (Today / Run / History / Settings); seeds the starter routine once
  AppNavigation.swift           – @Observable selected tab + AppServices (engine / container / navigation for intents)
  RoutineIntents.swift          – App Intents: Start Morning Routine, I'm Awake, Open Today; the App Shortcuts provider

  — Model & math (all pure, all unit tested) —
  RoutineStep.swift             – SwiftData model (stable `stepID: UUID`) + starter routine seeds
  RoutineSession.swift          – SwiftData model for a finished run + SessionRecorder
  MorningLog.swift              – SwiftData model for the wake time + the join into MorningRecord
  RunModels.swift               – Codable value types: RunStep, StepResult, RoutineRun, SessionResult, PlannedAlert
  RoutineEngine.swift           – @Observable timer engine; all time math; persists the run via RunStore
  RoutineStats.swift            – stats over sessions: averages, streak, trend, per-step suggestions + StepHistory
  MorningMetrics.swift          – snooze / activation / duration, baselines, spread, budgets, missed days, insights
  TargetSchedule.swift          – finish-by target math: start-by time, spare time, reminder components
  RoutinePace.swift             – FillTheme palette, per-step StepPace, cumulative pace label

  — Feedback —
  RoutineAlertCoordinator.swift – turns engine events into chimes/voice/haptics and local notifications
  RoutineAlerts.swift           – AVAudioPlayer chimes (audible on silent), AVSpeechSynthesizer voice, haptics
  RoutineNotificationManager.swift – schedules the engine's PlannedAlerts as local notifications
  RoutineLiveActivityController.swift – mirrors the engine into the Lock Screen / Dynamic Island activity

  — Views —
  TodayView.swift               – "Today" tab (landing): wake CTA, day timeline, performance tiles, budgets, insight
  RoutineTimerView.swift        – "Run" tab: idle screen (ready/paused/complete); delegates the running screen
  ActiveRoutineView.swift       – the running-timer screen (see "Active screen" below)
  RunSheetView.swift            – the sheet behind the bottom bar's chevron: note, run stats, toggles, end
  InvertingFillView.swift       – the two-layer colour-inverting fill
  PauseOverlay.swift            – the dimmed "PAUSED" layer over the running timer
  StepNotesView.swift           – editable notes sheet (+ read-only fallback)
  ReceiptDialog.swift           – branded confirmation dialog
  ReceiptUI.swift               – shared receipt controls: buttons, switches, sheet chrome
  GlyphPickerView.swift         – searchable icon picker sheet
  GlyphCatalog.swift            – the curated glyph/emoji set and its keywords
  SessionSummaryView.swift      – sheet shown when a routine completes
  RoutineListView.swift         – full step list (reorder / delete / restore), presented from Settings
  StepStatsSheet.swift          – one step's plan and recent record, from the arrow on a selected Run-tab row
  SettingsView.swift            – "Settings" tab: timer appearance, morning goal, target, DEBUG tools
  StepEditorView.swift          – per-step form (icon, title, duration, auto-next, notes, delete)
  HistoryView.swift             – "History" tab: stat tiles, charts, suggestions, session list
  MorningChartsView.swift       – the charting half of History (Swift Charts)

  DebugSeed.swift               – DEBUG-only 13-day sample history
  Assets.xcassets/AppIcon…      – generated; see Tools/make_app_icon.py
  TimeFormatting.swift
  FontHelpers.swift
  Sounds/                       – generated chime .wav files

Tools/
  make_app_icon.py              – regenerates the app icon (Light / Dark / Tinted)

RISE_RoutineTimerWidget/          – the RISE_RoutineTimerWidgetExtension target (WidgetKit)
  RoutineActivityAttributes.swift – ActivityAttributes + ContentState; compiled into BOTH targets
  RoutineLiveActivity.swift       – Lock Screen banner + Dynamic Island (expanded / compact / minimal)
  RISE_RoutineTimerWidgetBundle.swift, Info.plist, Fake Receipt.otf

RISE_RoutineTimerTests/
  RoutineEngineTests.swift      – engine time math driven with synthetic dates
  RoutineStatsTests.swift       – stats and suggestion tests
  MorningMetricsTests.swift     – snooze / activation / baselines / spread / budgets / missed days / streak
  StepPaceTests.swift           – per-step pace colours, theme/overtime separation, glyph catalog
  TargetScheduleTests.swift     – target/start-by tests
```

## Build & test

```
xcodebuild -scheme RISE_RoutineTimer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

89 tests — mostly pure value-type math against synthetic dates; the suite runs in well under a second. The build should be warning-free; keep it that way.

The Xcode project uses synchronized buildable folders, so new `.swift` files dropped into `RISE_RoutineTimer/` or `RISE_RoutineTimerTests/` are picked up with no pbxproj surgery.

**Sample data:** in a DEBUG build, the Routine tab's ⋯ menu has *Seed Sample History* (13 days that gradually improve, with 2 missed days) and *Clear All History*. Use it rather than waiting two weeks to see the charts, baselines, budgets and streak logic.

## Key architecture notes

### Data

- **Three SwiftData models:** `RoutineStep`, `RoutineSession`, `MorningLog`. All are registered in the schema in `RISE_RoutineTimerApp.init()` — a new model must be added there *and* in the `#Preview` container in `ContentView.swift`.
- Every `RoutineSession` / `MorningLog` property has a default so the models stay CloudKit-compatible.
- `RoutineStep.sortOrder: Int` preserves list order, since SwiftData does not guarantee it. `stepID` is a stable UUID for matching a step across sessions as it gets renamed.

### The engine

- **The active run is a file, not a preference.** It lived in `UserDefaults`, and an ended routine could come back from the dead: `UserDefaults` hands writes to `cfprefsd`, which batches them, so a removal could still be pending when the process died — and iOS will kill a backgrounded app. The earlier save had committed, the removal had not. `synchronize()` did not reliably force it. `FileRunStore` writes atomically and deletes immediately, so the problem cannot recur.
- Its migration off `UserDefaults` uses its own **marker file**, not "does the run file exist". Ending a routine deletes the run file, so keying the migration on that would re-read the stale legacy value on the next launch and restore the run just ended — the same bug through the back door. `FileRunStoreTests.testLegacyRunIsNotRestoredAgainAfterBeingEnded` pins this.

- **All timer logic lives in `RoutineEngine`**, never in views. When a run starts the steps are frozen into `[RunStep]`, so editing the routine mid-run cannot corrupt it. Every value the UI shows is derived from `run` + `now`.
- The engine emits `Event`s (`stepStarted`, `overtimeStarted`, `completed`, …) that `RoutineAlertCoordinator` turns into feedback and `SessionRecorder` turns into history.
- **The screen stays on while a routine is running, app-wide.** `RISE_RoutineTimerApp.syncIdleTimer()` sets `UIApplication.shared.isIdleTimerDisabled = engine.hasActiveRun && scenePhase == .active`, driven by both values. It used to live on the Run tab and switched itself off in `onDisappear`, so glancing at Today mid-routine let the phone sleep.
- The run is saved by `FileRunStore` (an atomic JSON file in Application Support) after every mutation and restored at launch (running runs catch up on wall-clock time; runs older than 12 h are dropped). Pauses are tracked separately so the real start time never shifts.
- `scheduleDeltaSeconds` (positive = behind) and `projectedEndDate` are the ahead/behind signals. `plannedAlerts(at:)` is the single source of truth for what notifications get scheduled.

### Active screen

- `InvertingFillView` draws its content **twice** — a white page with dark type, and a coloured page with white type masked to the fill height — rather than the `.blendMode(.difference)` trick it used to use. That keeps type crisp *at* the fill line, lets emoji render normally (the old version needed a `.blendMode(.normal)` escape hatch), and allows a coloured fill at all.
- Two consequences the call site must respect:
  1. The masked copy is `.accessibilityHidden(true)`, so VoiceOver reads the screen once.
  2. **No interactive controls inside the content closure** — there would be two of every button, stacked. `ActiveRoutineView` keeps every control in a sibling overlay, styled as white chips so they read against both the white page and the coloured fill without per-layer colour maths. **The check and skip chips are the exception that proves the rule: their *visuals* are drawn inside the content closure** (`chipRow(textColor:)`, in the slot that used to be `Color.clear`), so the fill line crosses them exactly as it crosses the type — half dark, half white — while `controls` holds only invisible `hitTarget`s of the same size in the same slot. On the page a chip is 72 % white with a dark glyph and a soft shadow; under the fill it is a 16 % white ghost with a white glyph and ring. Two earlier versions were wrong in instructive ways: solid white chips in the overlay read as stark holes in the saturated fill, and a whole-chip flip driven by comparing the fill height with the chip's centre still snapped the glyph from black to white in one go, which nothing else on the screen does. Glyph weights are `.light` (check) and `.regular` (skip). The bottom bar stays opaque because its progress edge would fight the fill colour through a translucent one.
- The type layer reserves a fixed-height slot for the control cluster, and both layers apply *identical* safe-area arithmetic (`bottomInset(_:)`, `nextZoneHeight`, `checkDiameter`). If the checkmark ever drifts onto the pace row again, that is the invariant that broke.
- **The screen is "silent until it matters".** On a good morning it is the step icon, its name, a rule, and the countdown — nothing else. There is no step time-range line, no status pill, and no PACE/DONE/SPARE row; those were three competing information bands and the screen read as cluttered. One line appears under the countdown only when the *routine* is at risk: `WON'T MAKE 7:30AM` if the finish-by target is projected to be missed, otherwise `X BEHIND` once `scheduleDeltaSeconds` passes `RoutinePace.behindAlertSeconds`. Step-level trouble is not mentioned here at all — the fill colour already carries it.
- **The fill colour is a per-step signal, not a cumulative one.** It used to be painted from `scheduleDeltaSeconds`, so a single slow step stained every step after it. Now `StepPace(overtimeSeconds:)` drives it: the user's chosen `FillTheme` while the step is on time, amber once it runs over, red past two minutes over. It resets with each step for free, because the engine reports overtime per step.
- Only a **manual** step can ever be amber or red: `RoutineEngine.tick()` advances an auto-next step the moment its time is up, so overtime and "this step is waiting on you" are the same condition.
- **The app is light-mode only** (`INFOPLIST_KEY_UIUserInterfaceStyle = Light` in the build settings, so system sheets and dialogs follow too). Don't add `@Environment(\.colorScheme)` branches.
- `FillTheme` colours are **saturated**, in the FLIP timer's register — that app puts white type straight onto a flat, confident red or green. An earlier pass used deep desaturated inks and read as muted pastel, which is not the look. They stay dark enough for white type and no darker.
- `FillTheme` deliberately contains no ambers or reds. If you add one, a step running over becomes indistinguishable from one running to plan — `StepPaceTests.testNoThemeCollidesWithTheOvertimeColours` will fail.
- **Auto-next is shown once, without status wording:** a small bordered `AUTO` / `MANUAL` capsule under the step name. The checkmark's border used to echo it (dashed for auto, solid for manual) and that is gone — the capsule already says it in words, and a second visual language for the same fact was a code to learn for nothing. Both chips now carry the same dashed border. The button is one quiet ghosted size (`checkDiameter`) for every step; the reserved slot is `buttonSlotHeight`, so the type above never shifts.
- The badge states what *kind* of step this is and never changes while the step runs. It is not a status line. An earlier `TAP WHEN DONE` / `OVERTIME · TAP WHEN DONE` line was removed for exactly that reason: the fill going amber and then red already says a step is running over, and saying it again in words was noise.
- **Notes are reachable three ways and editable mid-run.** When the step has a note, a `note.text` button sits tight against pause in the bottom bar (40pt wide, pulled 14pt in; a 26pt clear slot on the right keeps the label centred) — it is the signal that a note exists as much as the way to open it, so it is absent otherwise (Add lives in the run sheet); the step name is also a tap target. The name is plain text inside the fill so it still inverts; its tap target is placed over it in the overlay via a `TitleBoundsKey` anchor preference, since both copies of the content publish the same anchor from the same position. Edits write to the SwiftData `RoutineStep` and are then pushed into the run's frozen copy with `RoutineEngine.updateNotes(_:forStepID:)` — without that second step the screen would show stale text for the rest of the run.
- Notes body text is set in the **system font, not the receipt face**. The dot-matrix type is for labels and digits; at paragraph length it is genuinely hard to read.
- **The notes sheet is presented by item** (`NotesRequest`, carrying `editing`), not by a Bool plus a separate flag. The Bool version had the flag arriving as `false` on the run sheet's "Add" hand-off — the sheet's own `onDismiss` reset it mid-transition. An item is captured at presentation and nothing can zero it out underneath; a fresh `id` per request also means asking again while it is up re-presents rather than no-ops. `StepNotesView(startEditing:)` applies its initial state in `onAppear` as well as `init`, because a `@State(initialValue:)` set in `init` is not honoured when SwiftUI reuses a sheet's state storage.
- `RoutineStep.autoShowNotes` (default on) opens the sheet as a step begins — a beat (350 ms) after it, inside `withAnimation`, because set synchronously in the engine's tick the sheet appeared with no transition, already open on the new step — and is toggled by a plainly labelled "Open automatically" switch at the foot of the sheet. An icon-only version in the toolbar was tried and dropped: compact, but it gave no clue what it controlled.
- Neither the notes sheet nor the display sheet has a close button — they are dismissed by dragging down or tapping outside, which is the system default.
- **Sheets are brand surfaces, not settings panels.** They use `ReceiptUI` (square-stroked buttons, a square switch, tracked-caps titles over a hard rule) rather than `Form` and `Toggle`, and set `.presentationBackground` to an opaque colour — the translucent default let the timer's fill colour bleed through and made note text hard to read.
- **The notes sheet separates reading from editing.** It used to be a live `TextEditor` bound straight to the saved step, so a stray tap opened the keyboard and every keystroke was already saved. Now the text is plain until Edit is pressed, edits go to a local draft, and nothing reaches the step until Save. Cancel with unsaved changes confirms first, and `interactiveDismissDisabled` stops the sheet being swiped away mid-edit.
- Its chrome follows the detent (`presentationDetents(_:selection:)`): at medium it is note text and the auto-open pill only; the step title and the Edit button appear at full height, where there is room to type.
- The notes editor has **autocorrect off**. The notes hold transliterated Arabic, which autocorrect turns into nonsense. It is triggered from *two* places in `RoutineTimerView`: `currentIndex` changing, and `hasActiveRun` becoming true — starting a run does not change `currentIndex`, which is already 0, so the first step would otherwise never fire. `lastAutoNotesIndex` stops a tab switch or a return from background re-opening the same sheet.
- **Skip** offers "skip it" or "move to the end". Skipping records a `StepResult` with `skipped = true` and whatever time was spent, so the session total stays honest while the step contributes no sample to its own duration average (`RoutineStats` filters `wasSkipped`). Deferring records nothing — the step has not happened and will start fresh later; the few seconds already spent are dropped.
- **All chrome is one floating bar at the bottom**, in the shape of Arc's URL bar: pause on the left, `DONE AT 5:20AM` in the middle, a chevron on the right that raises `RunSheetView`. Its top edge is `RoutineEngine.routinePlanProgress` — position in the routine *by the plan*: planned time of every finished step plus the elapsed part of the current one, over the total. Finishing a step early jumps it to the step boundary; running over holds it there. The obvious `activeElapsedSeconds / plannedTotalSeconds` was tried first and barely moved when a five-minute step was done in one. This replaced a row of four chips plus a strip of step dots across the top, which with sixteen steps ran edge to edge. Pause is the only control that stays one tap — it is the only one with time pressure.
- The bar must stay an **opaque floating chip**: it sits at the bottom, inside the coloured fill for most of a step, and its progress edge would fight the fill colour otherwise. Same reasoning as the check and skip chips.
- Two progress indicators, on purpose: the rising fill is *this step*, the bar's edge is *the whole routine*. Unlike the depleting ring that was cut earlier, they do not say the same thing twice.
- Tapping the bar's centre swaps `DONE AT` for `MM:SS ELAPSED`; tapping again swaps straight back, and left alone it reverts after 3.5 s (`toggleElapsed`). The two readings roll vertically (`rollUp`, an asymmetric move+opacity transition) so the swap reads as a ticker turning over, not a crossfade. Animation is allowed there because the bar is in the control layer, outside the fill's `transaction { animation = nil }`.
- `RunSheetView` draws each section as a titled hairline box (`ReceiptSection` / `ReceiptStatRow` in `ReceiptUI`, shared with `StepStatsSheet`), so where one group ends and the next begins is drawn rather than implied by whitespace — evenly spaced rows made it unclear which numbers belonged together. Rows are 8pt tall; sections sit 16pt apart.
- `RunSheetView` holds what was cut from the screen for density — a `5:12 – 5:57 AM` run range (`TimeFormatting.clockRange`), elapsed, pace, spare vs target, step *n* of *m* — plus a **This step** section: planned duration, the step's average actual time over recent runs (`RoutineStats.averageActual(forStepID:)`, same evidence rules as suggestions: manual completions only, ≥2 samples), and the difference against plan. Then the step's note, the two display toggles, and End Routine. "Add" on a note-less step hands off with `editing: true`, and `StepNotesView(startEditing:)` opens fully with the keyboard up — dragging the sheet open and finding Edit was three steps too many. It dismisses itself before handing off to the notes sheet or the end dialog; `afterSheetDismisses` waits ~420 ms for the dismissal animation, or SwiftUI drops one of the two presentations.
- Two lines on the screen are optional, both `@AppStorage` via `ActiveScreenSettings`: the step start/end times at the top, and the NEXT zone. `nextZoneHeight` is computed from its setting, and the control layer's slot stack (`buttonSlotHeight`, `nextZoneHeight`, `barGap + barHeight`) mirrors the type layer's reserved `Color.clear` frames exactly — change one side without the other and the checkmark drifts. The toggles live in both the run sheet and Settings, sharing keys.
- **There is no undo / go-back-a-step.** It was removed from the engine as well as the UI (`undoLastStep` and the `.steppedBack` event are gone), so don't reintroduce a button expecting engine support. Skip and defer are the forward-only replacements.
- `RunStep` has a hand-written `init(from:)`. The synthesised one throws on a missing key even when the property has a default, which would drop an in-progress run persisted by an older build. Add new fields there with `decodeIfPresent`. `StepResult.skipped` is Optional for the same reason (a missing key on an Optional decodes as nil).
- **Pausing keeps the user on the timer.** It used to fall back to the Run tab's idle screen, which reads as "the routine is over". `PauseOverlay` now dims it in place. The timer underneath is *blurred*, not merely dimmed: the overlay restates the step and countdown, and at any scrim opacity the dot-matrix glyphs below stayed legible enough to read as a second, offset copy of both. `RoutineTimerView` routes on `engine.hasActiveRun`, not `isRunning`.
- Everything **snaps**; it is not animated. `InvertingFillView` carries `.transaction { $0.animation = nil }` because the per-second tick invalidates that view directly (it is where the engine is read), so a modifier on an ancestor misses it and the digits crossfade. The countdown also carries `.contentTransition(.identity)`. Motion is limited to a press response on the controls. Same lesson the FLIP timer learned — don't reintroduce smooth fills or rolling digits.

### Live Activity

- **`RoutineLiveActivityController` is a mirror, not a second engine.** `RoutineAlertCoordinator` calls `sync(with:)` in its init (a run restored at launch), on every engine event, and in `applicationDidBecomeActive()`. Each call builds one `ContentState` from the engine and upserts it: adopts an existing `Activity` if one is alive, else requests one; ends every activity when there is no run. There is nothing to keep in step by hand — if the Lock Screen is wrong, the engine is wrong or a sync call is missing.
- **The countdown runs by itself; step transitions do not.** The widget draws `Text(timerInterval: stepStart...stepEnd, countsDown: true)`, so a step ticks down with the app suspended, but the *next* step only appears when the app is awake to push it (auto-next fires in the engine, not in the widget). On a locked phone the banner reaches 0:00 and stays on that step; the local notifications carry the boundary. That is the honest limit without a background keep-alive — an audio session is the only route past it, and it has not been taken. While paused the widget shows the frozen `pausedRemainingSeconds` and a PAUSED badge.
- `RoutineActivityAttributes.swift` lives in the widget folder but is compiled into **both** targets via a `PBXFileSystemSynchronizedBuildFileExceptionSet` on the app target (the folder is a synchronized root group; the exception set is how one file joins a second target). The widget cannot import the app, so `RoutineLiveActivity.swift` carries its own copies of `analogFont`, the `FillTheme` hex table and the short clock format — **keep those in step with `FontHelpers` / `RoutinePace`**. The widget registers `Fake Receipt.otf` itself in `Widget.init()`; fonts registered by the app are not visible to the extension process.
- The extension is embedded by an "Embed Foundation Extensions" copy phase; the app's Info.plist gets `NSSupportsLiveActivities` via `INFOPLIST_KEY_NSSupportsLiveActivities`. In the expanded island the leading region is declared with `priority: 1` so it gets the leftover width and titles are not squeezed to "DRINK WA…"; a `frame(maxWidth: .infinity)` on that region instead makes the trailing and bottom regions disappear entirely.

### Morning accountability

- "I'm awake" can be undone from the Today tab while the routine has not started — one accidental tap otherwise skews the whole morning's snooze and activation numbers. It confirms through `ReceiptDialog`.

- `MorningLog` stores **only** the wake time — the one thing the timer cannot work out for itself. Routine start/end come from `RoutineSession`. `MorningRecord.join(logs:sessions:)` merges them into one record per day (earliest run wins, so an evening run doesn't overwrite the morning).
- `MorningMetrics` does all the math and is a direct port of MorningCheckin's `metrics.js`. Weekly budgets count **overruns only** — being up early doesn't earn credit toward a later lie-in. Missed days never count today.
- Settings (`targetWakeMinutes`, snooze/activation budgets) live in `@AppStorage` via `MorningSettings`, edited in the Routine tab's *Morning goal* section.

### Navigation

- **The Run tab's idle list edits by selection.** Tapping a step selects it: the row highlights, the connector above and below it grows a `+` (`InsertConnector`, which is otherwise a plain line — the first and last rows get a connector conjured just for this), and a pencil and an arrow appear at its right. Pencil opens `StepEditorView`; arrow opens `StepStatsSheet`; a `+` inserts a step at exactly that point. Tapping the row again deselects. An always-on `+` between every pair of rows and a pencil in the toolbar were tried first and read as clutter on what should be a quiet pre-flight list. An `ADD STEP` row still appends. Only while `engine.run == nil` — a finished run shows the frozen order, which may differ from the saved one after a move-to-end.
- **The idle list is a plain `List`**, not a ScrollView, so rows can be swiped away (`swipeActions`; the swipe only raises a `ReceiptDialog`, and the row goes when that is confirmed — an accidental full swipe on the morning list is too cheap to be irreversible) and dragged into a new order (`onMove`, long-press drag; no edit mode). Each row owns the connector beneath it, so a drag moves the step and its line together. Row insets are 14pt with 10pt inside the row, so text sits at the 24pt margin and the selection highlight reaches 10pt past it — the earlier negative-padding trick would be clipped by the cell.
- **A drag-reorder is a proposal until Save, and it locks the screen.** `moveSteps` writes only `pendingOrder: [UUID]?`; the list draws that order, and Cancel / Save Order replace the Start button while it differs from the saved one. While it is pending the tab bar is hidden (`.toolbar(.hidden, for: .tabBar)`, the same modifier a running routine uses) and `editable` is false, so no row can be selected, swiped, edited, opened for stats or added to — the only two ways out are the two buttons. `insertStep` is still written against the *saved* order and patches `pendingOrder` too, for the day something else needs to insert mid-drag.
- The toolbar is empty now: the pencil went (rows edit themselves) and the chime / voice speaker menu moved to Settings › Alerts. `RoutineListView` (duplicate, restore starter, and the same reorder / delete in system form) is still reachable from Settings › Routine › Full Step List for the occasional job.
- **`StepEditorView` edits a draft and writes nothing until Save.** It used to bind the form straight to the SwiftData step, so every wheel tick was already persisted and there was no way out of an accidental change. Cancel with changes confirms first; a sheet cannot be swiped away once dirty, and on a push the back button is hidden so both exits are explicit. It is presented by `StepEditRequest` (step + `isNew`): a step inserted just to be edited (connector `+`, `ADD STEP`, the list's Add) is *deleted again* on Cancel, so no stray "New Step" is left behind — and its title starts empty so the placeholder shows. **Save / Add refuses until the step has both a title and an icon** (`canSave`): the button dims but stays tappable, and a tap pulses whichever of the icon box / title field is missing red (`flashRequiredFields`) and focuses the title if that is one of them — a greyed-out button that explains nothing was the first version. The Task header carries a red asterisk and its footer says what is missing. A new step's sheet has an ✕ instead of Cancel.
- `ReceiptDialog` sets its `isPresented` binding to false *before* running the chosen action. Never derive that binding from the data the action needs (an optional "pending item") — the item is gone by the time the action reads it. Keep a separate Bool for the dialog and leave the item set until the action has used it; the Run tab's swipe-delete is the worked example.
- The idle rows show icon, title, duration and MANUAL only. They used to print the current step's note underneath; the note belongs in its sheet, and the pre-flight list is meant to fit on one screen.
- Step start/end times are toggled only from the run sheet now; Settings keeps just the next-step toggle and the timer colour.

- Tabs are **Today / Run / History / Settings**. There is no Routine tab: steps are edited in place on the Run tab, next to the list you are already looking at — editing a routine from a different tab than the one displaying it was a needless round trip.
- The Run tab's idle step rows are deliberately compact (18–20pt titles, 6pt row padding, 12pt connectors) so a whole routine fits without scrolling. That screen is a pre-flight check, not a document.

### App Intents

- Three intents in `RoutineIntents.swift`, all surfaced by `RISEShortcuts` so they show up in the Shortcuts app and Siri without setup. **Start Morning Routine** (`openAppWhenRun = true`) starts the engine with the saved steps and sets `AppNavigation.selectedTab = .run`; it is a no-op with a dialog if a run is already active. **I'm Awake** (`openAppWhenRun = false`) writes today's wake time through `MorningLogStore`, asks first via `requestConfirmation` unless its `askFirst` parameter is off, and reports "already marked awake at …" instead of overwriting. **Open Today** just lands the app on the Today tab — the natural second half of a wake-up automation, and the reason `AppNavigation` exists at all. The owner's automation is: phone unplugged in the morning → I'm Awake (confirm) → Open Today.
- Intents are constructed by the system, not the view tree, so they cannot use `@Environment`. `AppServices` (engine, container, navigation) is set once in `RISE_RoutineTimerApp.init`, and that is why the tab selection moved out of `ContentView` into `AppNavigation`.
- `perform()` must be marked `@MainActor` explicitly: the protocol requirement is nonisolated, so the project's default MainActor isolation does not apply to it, and the engine and store are MainActor.

### App icon

- A **dot-matrix sunrise**, deliberately a sibling to the FLIP timer's dot-matrix hourglass: the same construction — one iconic object drawn as discrete dots on a square grid, black on white, generous margins. The rule the sun rises over is the same rule the timer screen draws under the step name. The Dark variant is a straight inversion, which is what the running timer does to its own type as the fill rises.
- Regenerate with `python3 Tools/make_app_icon.py RISE_RoutineTimer/Assets.xcassets/AppIcon.appiconset`. That script's header records the four shapes that were tried and failed first (arc-on-horizon, filled disc, small outlined circle, angle-walked ring) so the same dead ends are not re-explored.

### Conventions

- The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; pure value types and pure static functions are marked `nonisolated`. `TimeFormatting`'s string maths is `nonisolated`, but `shortClockTime(from:)` stays isolated because it shares a `DateFormatter`.
- `analogFont()` / `digitFont()` from `FontHelpers.swift` are the "Fake Receipt" face. Tracked all-caps at 9–11pt is the micro-label register.
- Confirmations shown **over the timer** use `.receiptDialog(...)` (`ReceiptDialog`), not `.confirmationDialog` — a stack of system grey capsules over the full-bleed coloured screen looked like another app had taken over. Dialogs inside the Form-based settings surfaces still use the system sheet, which is idiomatic there.
- Step icons come from `GlyphCatalog` via `GlyphPickerView`. The catalog is curated, not the full emoji set, and every entry carries search keywords. Adding one: keep it a single grapheme, or `StepPaceTests.testEveryGlyphSurvivesNormalisation` will fail against `RoutineStep.normalizedIcon`.
- **Add unit tests for any change to the engine, stats, metrics or schedule math.** They are pure, they run in milliseconds, and they are the reason this codebase can be refactored confidently.

## Feature backlog

### Open

**Routine-level progress bar on the active screen** *(deferred)* — the PACE / DONE / SPARE micro-stats plus the rising fill cover the intent. Revisit only if a visual bar is still wanted; `activeElapsedSeconds`, `plannedTotalSeconds` and `projectedEndDate` have the math.

**Smaller, known gaps** — negative activation (a wake logged after the routine started) reports "—" rather than prompting a fix; the Today timeline is not scrubbable, unlike the web app's "touch to explore"; Today does not surface per-step suggestions.

### Done

- **Run 1** — engine extraction, run persistence, pause/end/undo, real chimes + voice + haptics, overtime nudges, notification permission moved off the running screen.
- **Run 2** — session history: `RoutineSession`, `SessionRecorder`, `SessionSummaryView`, the History tab, `RoutineStats` averages/streak/trend and per-step suggestions with one-tap apply.
- **Run 3** — finish-by target (`TargetSchedule`) with an optional start-by reminder, emoji step icons, editor delete/duplicate, empty-title guard, restore-starter-routine.
- **Run 4** — the active screen rebuilt around the coloured pace-driven inverting fill, plus the whole morning-accountability layer: wake logging, `MorningMetrics`, the Today landing tab, and Swift Charts in History.
- **Run 5** — active-screen feedback pass: per-step fill colour, the auto-next / overtime status pill, the pause overlay, the branded `ReceiptDialog`, a user-selectable `FillTheme`, and the searchable glyph picker.
- **Run 17** — screen-awake app-wide, boxed run-sheet sections, and the Live Activity (widget extension target, Lock Screen banner + Dynamic Island; see "Live Activity" above for its one real limitation).
- Smaller ones: new step opens its editor immediately (`NavigationPath`); notes shown on demand via a sheet from the active screen's notes chip; Back/Reset/Skip removed from the Run idle screen.
