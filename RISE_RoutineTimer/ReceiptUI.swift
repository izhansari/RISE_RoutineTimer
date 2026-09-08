//
//  ReceiptUI.swift
//  RISE_RoutineTimer
//
//  The shared receipt vocabulary — square strokes, tracked all-caps, hard
//  rules — for the places that would otherwise fall back to stock iOS chrome.
//  Named after the FLIP timer's file of the same job.
//
//  Sheets in this app are full-bleed brand surfaces, not settings panels, so
//  they use these rather than `Form` and `Toggle`.
//

import SwiftUI

// MARK: - Buttons

/// The square-stroked button from the FLIP timer. `fill` makes it the one
/// primary action on a surface.
struct ReceiptButton: View {
    let title: String
    var fill: Color?
    var height: CGFloat = 48
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(analogFont(15))
                .tracking(2.5)
                .foregroundStyle(fill == nil ? Color.primary : Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background {
                    if let fill {
                        RoundedRectangle(cornerRadius: 4).fill(fill)
                    } else {
                        RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.5), lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

/// A small tracked-caps action for a sheet's top bar.
struct ReceiptBarButton: View {
    let title: String
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(prominent ? Color(.systemBackground) : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    if prominent {
                        Capsule().fill(Color.primary)
                    } else {
                        Capsule().strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Toggles

/// A labelled switch drawn in the app's own language: a square track with a
/// square knob, filled when on. Reads as a control, not as a chip.
struct ReceiptToggle: View {
    let title: String
    var caption: String?
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title.uppercased())
                        .font(analogFont(17))
                        .tracking(2)
                        .foregroundStyle(Color.primary)
                    if let caption {
                        Text(caption)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 12)
                ReceiptSwitch(isOn: isOn).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 6 }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// The switch graphic on its own, for a compact top-bar control.
struct ReceiptSwitch: View {
    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .strokeBorder(Color.primary.opacity(isOn ? 1 : 0.35), lineWidth: 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(isOn ? Color.primary : Color.clear)
            )
            .frame(width: 46, height: 26)
            .overlay(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(isOn ? Color(.systemBackground) : Color.primary.opacity(0.45))
                    .frame(width: 16, height: 16)
                    .padding(.horizontal, 4)
            }
            .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

/// A compact labelled toggle for a sheet's top bar, where a full switch row
/// will not fit but an unlabelled icon would leave the user guessing.
struct ReceiptTogglePill: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text("\(title.uppercased()) \(isOn ? "ON" : "OFF")")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(isOn ? Color(.systemBackground) : Color.primary.opacity(0.6))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background {
                    if isOn {
                        Capsule().fill(Color.primary)
                    } else {
                        Capsule().strokeBorder(Color.primary.opacity(0.3), lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

// MARK: - Sheet chrome

/// The title block a fully-opened sheet gets: tracked caps over a hard rule.
struct ReceiptSheetTitle: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Text(title.uppercased())
                .font(analogFont(22))
                .tracking(3)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Rectangle()
                .fill(Color.primary)
                .frame(width: 96, height: 2)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A hairline divider in the receipt register.
struct ReceiptRule: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
    }
}

// MARK: - Boxed stats

/// A titled hairline box. Where one group ends and the next begins is drawn,
/// not implied by whitespace — evenly spaced rows made it unclear which
/// numbers belonged together. Shared by the run sheet and the step stats.
struct ReceiptSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            )
        }
        .padding(.bottom, 16)
    }
}

/// One `LABEL  detail ........ value` line inside a `ReceiptSection`.
struct ReceiptStatRow: View {
    let label: String
    let value: String
    var detail: String? = nil

    init(_ label: String, _ value: String, detail: String? = nil) {
        self.label = label
        self.value = value
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.secondary)
            if let detail {
                Text(detail.uppercased())
                    .font(.system(size: 9, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(value)
                .font(analogFont(18))
                .tracking(1)
                .monospacedDigit()
        }
        .padding(.vertical, 8)
    }
}
