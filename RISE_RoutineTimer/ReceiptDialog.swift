//
//  ReceiptDialog.swift
//  RISE_RoutineTimer
//
//  A confirmation dialog in the app's own visual language, replacing
//  `.confirmationDialog`. The system sheet is fine everywhere else in iOS,
//  but sliding a stack of rounded grey capsules up over the full-bleed
//  coloured timer screen looked like a different app had taken over.
//
//  The vocabulary is the FLIP timer's: a hard-bordered card, tracked all-caps
//  receipt type, a rule under the title, and square-cornered buttons — one
//  outlined, one filled.
//

import SwiftUI

// MARK: - Dialog

/// One button on a dialog. `fill` nil means the outlined treatment.
struct ReceiptDialogAction: Identifiable {
    let id = UUID()
    var title: String
    var fill: Color?
    var action: () -> Void

    static func destructive(_ title: String, action: @escaping () -> Void) -> ReceiptDialogAction {
        ReceiptDialogAction(title: title, fill: Color(hex: 0xDB2118), action: action)
    }

    static func quiet(_ title: String, action: @escaping () -> Void) -> ReceiptDialogAction {
        ReceiptDialogAction(title: title, fill: nil, action: action)
    }
}

struct ReceiptDialog: View {
    let title: String
    var message: String?
    /// Rendered top to bottom. The last one is treated as the dismiss action
    /// for a tap on the scrim.
    let actions: [ReceiptDialogAction]
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
                .accessibilityLabel("Dismiss")
                .accessibilityAddTraits(.isButton)

            VStack(spacing: 0) {
                Text(title.uppercased())
                    .font(analogFont(22))
                    .tracking(2.5)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.primary)
                    .padding(.top, 26)
                    .padding(.horizontal, 24)

                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 96, height: 2)
                    .padding(.top, 14)

                if let message {
                    Text(message)
                        .font(.system(size: 14))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.top, 14)
                        .padding(.horizontal, 26)
                }

                VStack(spacing: 10) {
                    ForEach(actions) { action in
                        ReceiptButton(title: action.title, fill: action.fill, action: action.action)
                    }
                }
                .padding(.top, 22)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: 320)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary, lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
            .padding(.horizontal, 32)
        }
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: - Presentation

extension View {
    /// Drop-in replacement for a two-button `.confirmationDialog`.
    func receiptDialog(
        isPresented: Binding<Bool>,
        title: String,
        message: String? = nil,
        confirmTitle: String,
        isDestructive: Bool = true,
        cancelTitle: String = "Cancel",
        onConfirm: @escaping () -> Void
    ) -> some View {
        receiptDialog(isPresented: isPresented, title: title, message: message) {
            [
                ReceiptDialogAction(
                    title: confirmTitle,
                    fill: isDestructive ? Color(hex: 0xDB2118) : Color.primary,
                    action: onConfirm
                ),
                .quiet(cancelTitle, action: {})
            ]
        }
    }

    /// The general form: any number of stacked choices. Every action dismisses
    /// the dialog before it runs, so callers never have to.
    func receiptDialog(
        isPresented: Binding<Bool>,
        title: String,
        message: String? = nil,
        @ReceiptActionsBuilder actions: @escaping () -> [ReceiptDialogAction]
    ) -> some View {
        overlay {
            if isPresented.wrappedValue {
                ReceiptDialog(
                    title: title,
                    message: message,
                    actions: actions().map { action in
                        ReceiptDialogAction(title: action.title, fill: action.fill) {
                            isPresented.wrappedValue = false
                            action.action()
                        }
                    },
                    onDismiss: { isPresented.wrappedValue = false }
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.18), value: isPresented.wrappedValue)
    }
}

@resultBuilder
enum ReceiptActionsBuilder {
    static func buildBlock(_ components: [ReceiptDialogAction]...) -> [ReceiptDialogAction] {
        components.flatMap { $0 }
    }
    static func buildExpression(_ expression: ReceiptDialogAction) -> [ReceiptDialogAction] { [expression] }
    static func buildExpression(_ expression: [ReceiptDialogAction]) -> [ReceiptDialogAction] { expression }
    static func buildOptional(_ component: [ReceiptDialogAction]?) -> [ReceiptDialogAction] { component ?? [] }
    static func buildEither(first component: [ReceiptDialogAction]) -> [ReceiptDialogAction] { component }
    static func buildEither(second component: [ReceiptDialogAction]) -> [ReceiptDialogAction] { component }
    static func buildArray(_ components: [[ReceiptDialogAction]]) -> [ReceiptDialogAction] {
        components.flatMap { $0 }
    }
}
