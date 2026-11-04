// Copyright 2026 Wayne W Bishop. All rights reserved.
//
//
// Licensed under the Apache License, Version 2.0 (the "License"); you may not use this
// file except in compliance with the License. You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
// ANY KIND, either express or implied. See the License for the specific language governing
// permissions and limitations under the License.

import SwiftUI

/// The status chip, the file menu with the journal, New beside the phrasebook, the progress button, and the theme toggle.
struct TopBar: View {

    let model: EditorModel
    @Binding var showsIssueList: Bool
    @Binding var showsProgress: Bool
    @Binding var showsPhrasebook: Bool
    @Binding var showsEntries: Bool
    /// Hands a File menu command to the editor, which asks about unsaved changes first.
    let perform: (FileRequest) -> Void

    // Every button here hides the keyboard first, as on iPhone, so nothing opens with
    // the keyboard still up.
    var body: some View {
        HStack(spacing: 4) {
            Button {
                hideKeyboard()
                showsIssueList = true
            } label: {
                StatusChip(errors: model.blockingIssues.count, warnings: model.warnings.count, isGentle: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows every issue")

            Spacer()

            Menu {
                Button("Journal", systemImage: "list.bullet") {
                    hideKeyboard()
                    showsEntries = true
                }
                Divider()
                Button("Save", systemImage: "square.and.arrow.down") { request(.save) }
                    .disabled(!model.canSave)
                Button("Save as New Entry…", systemImage: "plus.square.on.square") { request(.saveAsNewEntry) }
                    .disabled(!model.canSave)
                Divider()
                Button("Import…", systemImage: "folder") { request(.importFile) }
                Button("Export a Copy…", systemImage: "square.and.arrow.up") { request(.export) }
                    .disabled(!model.hasText)
                ShareLink(item: model.plainText)
                    .disabled(!model.hasText)
            } label: {
                Label("File", systemImage: "folder")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)

            Button("New") { request(.new) }
                .buttonStyle(.bordered)
                .accessibilityLabel("Start a blank page")
                .disabled(!model.hasText && model.fileURL == nil)

            Button("Phrasebook", systemImage: "book") {
                hideKeyboard()
                showsPhrasebook.toggle()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())

            Button {
                hideKeyboard()
                showsProgress = true
            } label: {
                Label("\(model.stats.stats.streak(asOf: .now))", systemImage: "chart.bar.xaxis")
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 44)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityLabel("Your progress: \(model.stats.stats.streak(asOf: .now)) day streak")

            ThemeToggle()
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
    }

    /// Hides the keyboard, then hands the File menu command to the editor.
    private func request(_ fileRequest: FileRequest) {
        hideKeyboard()
        perform(fileRequest)
    }
}

#if !os(macOS)
/// The iPhone navigation bar's buttons: the journal on the leading edge, then the
/// phrasebook and a More menu holding the file commands, progress, font size, and the theme.
struct CompactToolbar: ToolbarContent {

    let model: EditorModel
    @Binding var showsProgress: Bool
    @Binding var showsPhrasebook: Bool
    @Binding var showsEntries: Bool
    /// Hands a file command to the editor, which asks about unsaved changes first.
    let perform: (FileRequest) -> Void

    // Every button here hides the keyboard first, so a sheet, menu or alert never
    // opens with the keyboard still covering the bottom of the screen.
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Journal", systemImage: "list.bullet") {
                hideKeyboard()
                showsEntries = true
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button("Phrasebook", systemImage: "book") {
                hideKeyboard()
                showsPhrasebook.toggle()
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section {
                    Button("New", systemImage: "square.and.pencil") { request(.new) }
                        .disabled(!model.hasText && model.fileURL == nil)
                    Button("Save", systemImage: "square.and.arrow.down") { request(.save) }
                        .disabled(!model.canSave)
                    Button("Save as New Entry…", systemImage: "plus.square.on.square") { request(.saveAsNewEntry) }
                        .disabled(!model.canSave)
                }
                Section {
                    FontSizePicker()
                    Button("Import…", systemImage: "folder") { request(.importFile) }
                    Button("Export a Copy…", systemImage: "square.and.arrow.up") { request(.export) }
                        .disabled(!model.hasText)
                    ShareLink(item: model.plainText)
                        .disabled(!model.hasText)
                }
                Section {
                    Button("Progress · \(plural(streak, "day")) streak", systemImage: "chart.bar.xaxis") {
                        hideKeyboard()
                        showsProgress = true
                    }
                    ThemeToggle()
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
        }
    }

    /// Hides the keyboard, then hands the file command to the editor.
    private func request(_ fileRequest: FileRequest) {
        hideKeyboard()
        perform(fileRequest)
    }

    /// The learner's current streak, in days.
    private var streak: Int {
        model.stats.stats.streak(asOf: .now)
    }
}
#endif

/// "2 errors · 1 warning", "1 warning", or "No issues"; in the gentle style, "3 to look at".
struct StatusChip: View {

    let errors: Int
    let warnings: Int
    /// Whether the chip reads as a to-do list rather than a grade: one neutral count, with
    /// only the small red or orange mark for color, so a learner's first draft isn't scored.
    var isGentle = false

    var body: some View {
        HStack(spacing: 8) {
            if errors > 0 {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text(label)
            } else if warnings > 0 {
                RoundedRectangle(cornerRadius: 2).fill(.orange).frame(width: 8, height: 8).rotationEffect(.degrees(45))
                Text(label)
            } else {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                Text("No issues")
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(textStyle)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(fillStyle))
        .frame(minHeight: 44)
    }

    /// The label's color: red, orange or the tint, or the primary color in the gentle style.
    private var textStyle: AnyShapeStyle {
        if errors == 0 && warnings == 0 { return AnyShapeStyle(.tint) }
        if isGentle { return AnyShapeStyle(.primary) }
        return errors > 0 ? AnyShapeStyle(.red) : AnyShapeStyle(.orange)
    }

    /// The capsule's fill, tinted to match the label, or neutral in the gentle style.
    private var fillStyle: AnyShapeStyle {
        if errors == 0 && warnings == 0 { return AnyShapeStyle(.tint.opacity(0.12)) }
        if isGentle { return AnyShapeStyle(.fill.tertiary) }
        return errors > 0 ? AnyShapeStyle(.red.opacity(0.12)) : AnyShapeStyle(.orange.opacity(0.14))
    }

    /// The counts, as "2 errors · 1 warning", or "3 to look at" in the gentle style.
    private var label: String {
        if isGentle { return "\(errors + warnings) to look at" }
        let parts = [
            errors > 0 ? plural(errors, "error") : nil,
            warnings > 0 ? plural(warnings, "warning") : nil
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

/// Returns "1 error" or "3 errors".
func plural(_ count: Int, _ noun: String) -> String {
    "\(count) \(noun)\(count == 1 ? "" : "s")"
}

/// Hides the iPhone and iPad keyboard by asking whatever has focus to give it up; does nothing on the Mac.
@MainActor
func hideKeyboard() {
    #if canImport(UIKit)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    #endif
}
