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

    let steps: [RoutineStep]

    @State private var editingList = false

    private var plannedSeconds: Int { steps.reduce(0) { $0 + $1.durationSeconds } }
    private var schedule: TargetSchedule { TargetSchedule(targetMinutesAfterMidnight: targetMinutes) }

    var body: some View {
        NavigationStack {
            List {
                routineSection
                timerSection
                alertsSection
                wakeGoalSection
                targetSection
                #if DEBUG
                debugSection
                #endif
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $editingList) {
                RoutineListView(steps: steps)
            }
            .onChange(of: targetMinutes) { _, _ in syncReminder() }
            .onChange(of: reminderEnabled) { _, _ in syncReminder() }
            .onChange(of: plannedSeconds) { _, _ in syncReminder() }
        }
    }

    #if DEBUG
    private var debugSection: some View {
        Section {
            Button {
                DebugSeed.populate(
                    context: modelContext,
                    steps: steps,
                    settings: MorningSettings(targetWakeMinutes: targetWakeMinutes)
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
            Button { editingList = true } label: {
                Label("Full Step List", systemImage: "list.bullet")
            }
        } header: {
            Text("Routine")
        } footer: {
            Text("Edit, add, reorder and delete steps on the Run tab. The full list is for duplicating a step or restoring the starter routine.")
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
