//
//  RoutineLiveActivity.swift
//  RISE_RoutineTimerWidget
//
//  The routine on the Lock Screen and in the Dynamic Island, in the app's own
//  language: the receipt face, tracked caps, a hard rule, a progress edge.
//
//  What it can and cannot do: the countdown runs on its own from the dates in
//  the content state, so a step ticks down correctly with the app suspended.
//  Step *transitions* need the app to push an update, which it does whenever
//  it is awake — so on a locked phone the banner shows the step that was
//  current when the app last ran, counting down to that step's end, and the
//  existing local notifications carry the boundary. That is the honest limit
//  of a Live Activity without a background keep-alive.
//

import ActivityKit
import CoreText
import SwiftUI
import WidgetKit

// MARK: - Shared vocabulary (mirrors the app; the widget cannot import it)

private func analogFont(_ size: CGFloat) -> Font {
    .custom("FakeReceipt-Regular", size: size)
}

private func registerWidgetFonts() {
    guard let url = Bundle.main.url(forResource: "Fake Receipt", withExtension: "otf") else { return }
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Keep in step with `FillTheme` in the app.
    static func theme(_ name: String) -> Color {
        switch name {
        case "ocean":  return Color(hex: 0x0C6ED6)
        case "indigo": return Color(hex: 0x4A32DC)
        case "violet": return Color(hex: 0x9A22C8)
        case "ink":    return Color(hex: 0x171717)
        default:       return Color(hex: 0x0FA057)   // green
        }
    }
}

private func clock(_ seconds: Int) -> String {
    let s = max(0, seconds)
    return "\(s / 60):" + String(format: "%02d", s % 60)
}

private let shortClock: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "h:mma"
    f.amSymbol = "AM"
    f.pmSymbol = "PM"
    return f
}()

// MARK: - Widget

struct RoutineLiveActivity: Widget {
    init() {
        registerWidgetFonts()
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RoutineActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(.white)
                .activitySystemActionForegroundColor(.black)
        } dynamicIsland: { context in
            let state = context.state
            let tint = Color.theme(state.theme)

            return DynamicIsland {
                // priority: 1 hands the leading region the leftover width so
                // titles are not squeezed to "DRINK WA…". Do NOT give it
                // `frame(maxWidth: .infinity)` instead — that swallows the
                // whole island and the trailing and bottom regions vanish.
                DynamicIslandExpandedRegion(.leading, priority: 1) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            if !state.stepIcon.isEmpty {
                                Text(state.stepIcon).font(.system(size: 16))
                            }
                            Text(state.stepTitle.uppercased())
                                .font(analogFont(15))
                                .tracking(2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .foregroundStyle(.white)
                        Rectangle().fill(.white).frame(width: 56, height: 2)
                        Text(state.autoNext ? "AUTO" : "MANUAL")
                            .font(.system(size: 8, weight: .semibold))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: state)
                        .font(analogFont(30))
                        .foregroundStyle(.white)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressEdge(fraction: state.planProgress, tint: tint, track: .white.opacity(0.18))
                        HStack {
                            if let next = state.nextTitle {
                                Text("NEXT  \(next.uppercased())")
                            } else {
                                Text("LAST STEP")
                            }
                            Spacer()
                            Text("DONE \(shortClock.string(from: state.projectedEnd))")
                        }
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                if state.stepIcon.isEmpty {
                    Circle().fill(tint).frame(width: 8, height: 8)
                } else {
                    Text(state.stepIcon).font(.system(size: 13))
                }
            } compactTrailing: {
                Countdown(state: state)
                    .font(analogFont(13))
                    .frame(width: 46)
            } minimal: {
                Circle().fill(tint).frame(width: 10, height: 10)
            }
            .keylineTint(tint)
        }
    }
}

// MARK: - Pieces

/// The live countdown, or a frozen one while paused.
private struct Countdown: View {
    let state: RoutineActivityAttributes.ContentState

    var body: some View {
        if state.isPaused {
            Text(clock(state.pausedRemainingSeconds))
                .monospacedDigit()
        } else {
            Text(timerInterval: state.stepStart...state.stepEnd, countsDown: true)
                .monospacedDigit()
        }
    }
}

/// The in-app bottom bar's top edge: a thin track that fills by the plan.
private struct ProgressEdge: View {
    let fraction: Double
    let tint: Color
    var track: Color = .black.opacity(0.1)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(track)
                Rectangle().fill(tint).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 3)
    }
}

private struct LockScreenView: View {
    let state: RoutineActivityAttributes.ContentState

    private var tint: Color { .theme(state.theme) }

    var body: some View {
        VStack(spacing: 0) {
            ProgressEdge(fraction: state.planProgress, tint: tint)

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if !state.stepIcon.isEmpty {
                            Text(state.stepIcon).font(.system(size: 20))
                        }
                        Text(state.stepTitle.uppercased())
                            .font(analogFont(20))
                            .tracking(3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                    }
                    .foregroundStyle(.black)

                    HStack(spacing: 8) {
                        Text(state.isPaused ? "PAUSED" : (state.autoNext ? "AUTO" : "MANUAL"))
                            .font(.system(size: 8, weight: .semibold))
                            .tracking(1.6)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .overlay(Capsule().strokeBorder(Color.black.opacity(0.3), lineWidth: 1))
                        Text("STEP \(state.stepIndex) OF \(state.stepCount)")
                            .font(.system(size: 8, weight: .semibold))
                            .tracking(1.6)
                    }
                    .foregroundStyle(.black.opacity(0.55))

                    Group {
                        if let next = state.nextTitle {
                            Text("NEXT  \(next.uppercased())")
                        } else {
                            Text("LAST STEP")
                        }
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(.black.opacity(0.4))
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 4) {
                    Countdown(state: state)
                        .font(analogFont(44))
                        .foregroundStyle(state.isPaused ? .black.opacity(0.45) : .black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("DONE \(shortClock.string(from: state.projectedEnd))")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(.black.opacity(0.45))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }
}
