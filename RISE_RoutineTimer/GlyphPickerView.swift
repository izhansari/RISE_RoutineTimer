//
//  GlyphPickerView.swift
//  RISE_RoutineTimer
//
//  Replaces the step editor's one-character text field, which accepted any
//  typing but silently threw away everything after the first grapheme — so
//  typing "shower" left you with "s" and no explanation.
//
//  Now: a searchable grid of curated glyphs and emoji, plus an explicit slot
//  for a single typed letter or number for anyone who wants "1", "A" or "§".
//

import SwiftUI

struct GlyphPickerView: View {
    /// The step's current icon; written straight through on selection.
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var typed = ""
    @FocusState private var typingFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 54), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    customSection

                    let matches = GlyphCatalog.filtered(by: query)
                    if matches.isEmpty {
                        noMatches
                    } else {
                        ForEach(matches) { category in
                            section(category)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .searchable(text: $query, prompt: "Search icons")
            .navigationTitle("Step Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("None") {
                        selection = ""
                        dismiss()
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
    }

    // MARK: - Type your own

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("LETTER OR NUMBER")

            HStack(spacing: 12) {
                TextField("", text: $typed, prompt: Text("A"))
                    .font(.system(size: 24, weight: .medium))
                    .multilineTextAlignment(.center)
                    .focused($typingFocused)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .frame(width: 62, height: 54)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                    .onChange(of: typed) { _, newValue in
                        // Keep one grapheme, same rule the model enforces.
                        typed = RoutineStep.normalizedIcon(newValue)
                    }
                    .accessibilityLabel("Type a letter or number")

                if !typed.isEmpty {
                    Button {
                        choose(typed)
                    } label: {
                        Text("USE \(typed)")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(1.4)
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .background(Color.primary, in: Capsule())
                            .foregroundStyle(Color(.systemBackground))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Catalog

    private func section(_ category: GlyphCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(category.name.uppercased())
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(category.glyphs) { glyph in
                    tile(glyph.value)
                }
            }
        }
    }

    private func tile(_ value: String) -> some View {
        let isSelected = value == selection
        return Button {
            choose(value)
        } label: {
            Text(value)
                .font(.system(size: 26))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    isSelected ? Color.primary.opacity(0.12) : Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.primary, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var noMatches: some View {
        VStack(spacing: 8) {
            Text("No icons match “\(query)”")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Try a word like shower, gym, coffee or notes.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.8)
            .foregroundStyle(.secondary)
    }

    private func choose(_ value: String) {
        selection = RoutineStep.normalizedIcon(value)
        dismiss()
    }
}
