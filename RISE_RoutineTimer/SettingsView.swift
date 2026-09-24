//
//  SettingsView.swift
//  RISE_RoutineTimer
//
//  Everything about the routine that is not the routine's steps.
//
//  The steps themselves used to live here too, in a tab of their own. They
//  now hang off an Edit button on the Run tab, next to the list you actually
//  look at — editing a routine from a different tab than the one showing it
//  was a needless round trip.
//

import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(TargetSchedule.targetKey) private var targetMinutes = TargetSchedule.none
    @AppStorage(TargetSchedule.reminderKey) private var reminderEnabled = false
    @AppStorage(FillTheme.storageKey) private var fillThemeRaw = FillTheme.default.rawValue
    @AppStorage(RoutineAlertCoordinator.soundsKey) private var soundsEnabled = true
    @AppStorage(RoutineAlertCoordinator.voiceKey) private var voiceEnabled = true
    @AppStorage(ActiveScreenSettings.showNextStepKey) private var showNextStep = true
    @AppStorage(MorningSettings.targetWakeKey) private var targetWakeMinutes = MorningSettings.defaultTargetWakeMinutes
    @AppStorage(MorningSettings.snoozeBudgetKey) private var snoozeBudget = MorningSettings.defaultSnoozeBudget
    @AppStorage(MorningSettings.activationBudgetKey) private var activationBudget = MorningSettings.defaultActivationBudget
    @AppStorage(NightSettings.targetStartKey) private var nightTargetStart = NightSettings.defaultTargetStartMinutes
    @AppStorage(NightSettings.reminderKey) private var nightReminderEnabled = true
    @AppStorage(NightSettings.eveningStartKey) private var eveningStart = NightSettings.defaultEveningStartMinutes

    /// Every step of both routines; the morning goal and target below only
    /// ever mean the morning one.
    let steps: [RoutineStep]
    /// The routine Today was showing when Settings was opened. Its goal
    /// section comes first, so the night page lands on the night's settings.
    var focus: RoutineKind = .morning

    /// The full step list being shown, if any — one per routine.
    @State private var editingList: RoutineKind?

    private var morningSteps: [RoutineStep] { steps.routine(.morning) }
    private var plannedSeconds: Int { morningSteps.reduce(0) { $0 + $1.durationSeconds } }
    private var schedule: TargetSchedule { TargetSchedule(targetMinutesAfterMidnight: targetMinutes) }

    var body: some View {
    List {
            routineSection
            if focus == .night {
                nightGoalSection
                timerSection
                alertsSection
                wakeGoalSection
                targetSection
            } else {
                timerSection
                alertsSection
                wakeGoalSection
                nightGoalSection
                targetSection
            }
            #if DEBUG
            debugSection
            #endif
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(item: $editingList) { kind in
            RoutineListView(steps: steps.routine(kind), kind: kind)
        }
        .onChange(of: targetMinutes) { _, _ in syncReminder() }
        .onChange(of: reminderEnabled) { _, _ in syncReminder() }
        .onChange(of: plannedSeconds) { _, _ in syncReminder() }
        .onChange(of: nightTargetStart) { _, _ in syncNightReminder() }
        .onChange(of: nightReminderEnabled) { _, _ in syncNightReminder() }
    }

    #if DEBUG
    private var debugSection: some View {
        Section {
            // Throwaway prototypes for the History / Today redesign — see
            // DesignLab.swift. Remove with that file once a direction is built.
            NavigationLink {
                DesignLabView()
            } label: {
                Label("Design Mockups", systemImage: "rectangle.on.rectangle.angled")
            }
            Button {
                DebugSeed.populate(
                    context: modelContext,
                    steps: morningSteps,
                    settings: MorningSettings(targetWakeMinutes: targetWakeMinutes),
                    nightSteps: steps.routine(.night),
                    nightGoalMinutes: nightTargetStart
                )
            } label: {
                Label("Seed Sample History", systemImage: "wand.and.stars")
            }
            Button(role: .destructive) {
                DebugSeed.clear(context: modelContext)
            } label: {
                Label("Clear All History", systemImage: "trash")
            }
        } header: {
            Text("Developer")
        }
    }
    #endif

    // MARK: - Sections

    /// Used to be a speaker menu in the Run tab's toolbar. Settings that are
    /// set once belong here, not on the pre-flight screen.
    private var alertsSection: some View {
        Section {
            Toggle(isOn: $soundsEnabled) { Label("Chimes", systemImage: "bell") }
            Toggle(isOn: $voiceEnabled) { Label("Voice", systemImage: "waveform") }
        } header: {
            Text("Alerts")
        } footer: {
            Text("Chimes sound at every step change, even on silent. Voice reads each step's name as it starts.")
        }
    }

    /// Day-to-day editing happens on the Run tab (tap a step). The full list
    /// is only for reordering, deleting several at once, or starting over.
    private var routineSection: some View {
        Section {
            // The routine Today was showing comes first.
            ForEach(focus == .night ? [RoutineKind.night, .morning] : [RoutineKind.morning, .night]) { kind in
                Button { editingList = kind } label: {
                    Label("\(kind.title) Steps", systemImage: kind.symbol)
                }
            }
        } header: {
            Text("Routines")
        } footer: {
            Text("Edit, add, reorder and delete steps on the Routines screen, which switches between the morning and the night. The full lists are for duplicating a step or restoring a starter routine.")
        }
    }

    /// Timer appearance: fill colour plus the two optional lines.
    private var timerSection: some View {
        Section {
            HStack(spacing: 14) {
                ForEach(FillTheme.allCases) { option in
                    Button {
                        fillThemeRaw = option.rawValue
                    } label: {
                        VStack(spacing: 7) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(option.color)
                                .frame(height: 46)
                                .overlay {
                                    if option.rawValue == fillThemeRaw {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(
                                            option.rawValue == fillThemeRaw ? Color.primary : Color.clear,
                                            lineWidth: 2
                                        )
                                        .padding(-3)
                                }
                            Text(option.title.uppercased())
                                .font(.system(size: 8, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(option.rawValue == fillThemeRaw ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(option.rawValue == fillThemeRaw ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.vertical, 8)
            Toggle("Show the next step", isOn: $showNextStep)
        } header: {
            Text("Timer")
        } footer: {
            Text("The fill turns amber and then red while a step runs over its time, so ambers and reds aren't offered here — they'd make the two states impossible to tell apart.")
        }
    }


    /// The wake goal and the weekly allowances the Today tab scores against.
    private var wakeGoalSection: some View {
        Section {
            DatePicker("Wake up by", selection: wakeGoalBinding, displayedComponents: .hourAndMinute)

            Stepper(value: $snoozeBudget, in: 0...600, step: 15) {
                LabeledContent("Snooze budget", value: "\(snoozeBudget) min / week")
            }

            Stepper(value: $activationBudget, in: 0...600, step: 15) {
                LabeledContent("Activation budget", value: "\(activationBudget) min / week")
            }
        } header: {
            Text("Morning goal")
        } footer: {
            Text("Snooze is time past your wake goal. Activation is time between waking and starting. Each week's overruns are drawn against these budgets on the Today tab.")
        }
    }

    /// The night's only goal: when the routine should have begun. Stamped on
    /// each night run as it is saved, so moving it later does not rewrite
    /// the nights already had.
    private var nightGoalSection: some View {
        Section {
            DatePicker("Start by", selection: nightGoalBinding, displayedComponents: .hourAndMinute)
            Toggle("Remind me at this time", isOn: $nightReminderEnabled)
            DatePicker("Today shows the night from", selection: eveningStartBinding, displayedComponents: .hourAndMinute)
        } header: {
            Text("Night goal")
        } footer: {
            Text("How late the night routine begins against this is its snooze. There is no activation at night — you are already up. The reminder is a daily notification at the goal itself. From the evening time until 4 AM, Today shows when you'd finish the night routine if you started now, and the app goes dark.")
        }
    }

    private var eveningStartBinding: Binding<Date> {
        Binding {
            Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(eveningStart * 60))
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            eveningStart = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    private var nightGoalBinding: Binding<Date> {
        Binding {
            Calendar.current.startOfDay(for: Date())
                .addingTimeInterval(TimeInterval(nightTargetStart * 60))
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            nightTargetStart = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    private var wakeGoalBinding: Binding<Date> {
        Binding {
            Calendar.current.startOfDay(for: Date())
                .addingTimeInterval(TimeInterval(targetWakeMinutes * 60))
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            targetWakeMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }


    private var targetSection: some View {
        Section {
            Toggle("Finish by a set time", isOn: targetEnabledBinding)
            if schedule.isSet {
                DatePicker("Finish by", selection: targetDateBinding, displayedComponents: .hourAndMinute)
                Toggle("Remind me when it's time to start", isOn: $reminderEnabled)
            }
        } header: {
            Text("Target")
        } footer: {
            if let startBy = schedule.startByDate(on: Date(), plannedSeconds: plannedSeconds) {
                Text("Start by \(TimeFormatting.shortClockTime(from: startBy)) to finish on time with the current \(TimeFormatting.durationText(from: plannedSeconds)) plan.")
            } else {
                Text("Set the time you need to be done, and RISE will tell you when to start.")
            }
        }
    }

    // MARK: - Bindings

    private var targetEnabledBinding: Binding<Bool> {
        Binding {
            schedule.isSet
        } set: { enabled in
            targetMinutes = enabled ? 7 * 60 + 30 : TargetSchedule.none
        }
    }

    private var targetDateBinding: Binding<Date> {
        Binding {
            schedule.targetDate(on: Date()) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            targetMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }


    private func syncNightReminder() {
        RoutineNotificationManager.scheduleNightReminder(atMinutesAfterMidnight: nightReminderEnabled ? nightTargetStart : nil)
    }

    private func syncReminder() {
        guard reminderEnabled, let target = schedule.targetDate(on: Date()) else {
            RoutineNotificationManager.scheduleDailyReminder(at: nil, targetText: "")
            return
        }
        RoutineNotificationManager.scheduleDailyReminder(
            at: schedule.startByComponents(plannedSeconds: plannedSeconds),
            targetText: TimeFormatting.shortClockTime(from: target)
        )
    }
}
