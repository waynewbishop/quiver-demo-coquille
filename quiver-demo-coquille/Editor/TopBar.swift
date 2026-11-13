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

/// The iPad's top bar: the journal, the status chip, and the More menu, as on iPhone.
struct TopBar: View {

    let model: EditorModel
    @Binding var showsIssueList: Bool
    @Binding var showsProgress: Bool
    @Binding var showsPhrasebook: Bool
    @Binding var showsExplanation: Bool
    @Binding var showsEntries: Bool
    @Binding var showsSettings: Bool
    /// Hands a File menu command to the editor, which asks about unsaved changes first.
    let perform: (FileRequest) -> Void

    // Every button here hides the keyboard first, as on iPhone, so nothing opens with
    // the keyboard still up.
    var body: some View {
        HStack(spacing: 4) {
            PanelToggle(title: "Journal", systemImage: "list.bullet", isOn: $showsEntries)
                .frame(minWidth: 44, minHeight: 44)

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
                MoreMenuItems(model: model, showsProgress: $showsProgress, showsPhrasebook: $showsPhrasebook, showsExplanation: $showsExplanation, showsSettings: $showsSettings, perform: perform)
            } label: {
                Label("More", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
    }
}

#if !os(macOS)
/// The iPhone navigation bar's buttons: the journal on the leading edge and the More menu
/// on the trailing edge, as in Things, so the bar never holds more than two controls.
struct CompactToolbar: ToolbarContent {

    let model: EditorModel
    @Binding var showsProgress: Bool
    @Binding var showsPhrasebook: Bool
    @Binding var showsExplanation: Bool
    @Binding var showsEntries: Bool
    @Binding var showsSettings: Bool
    /// Hands a file command to the editor, which asks about unsaved changes first.
    let perform: (FileRequest) -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            PanelToggle(title: "Journal", systemImage: "list.bullet", isOn: $showsEntries)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                MoreMenuItems(model: model, showsProgress: $showsProgress, showsPhrasebook: $showsPhrasebook, showsExplanation: $showsExplanation, showsSettings: $showsSettings, perform: perform)
            } label: {
                Label("More", systemImage: "ellipsis")
            }
        }
    }
}
#endif

/// The More menu on iPhone and iPad: New, Save, Share and the phrasebook first, then
/// Save as New Entry and Explain, then font size, progress and settings.
///
/// Share stands in for Export a Copy, since the share sheet can save to Files.
/// Save as New Entry shows only once the page is a saved entry, because before that it
/// would do the same as Save. Every item hides the keyboard first, so a sheet, menu or
/// alert never opens with the keyboard still covering the bottom of the screen.
struct MoreMenuItems: View {

    let model: EditorModel
    @Binding var showsProgress: Bool
    @Binding var showsPhrasebook: Bool
    @Binding var showsExplanation: Bool
    @Binding var showsSettings: Bool
    /// Hands a file command to the editor, which asks about unsaved changes first.
    let perform: (FileRequest) -> Void

    var body: some View {
        Section {
            Button("New", systemImage: "square.and.pencil") { request(.new) }
                .disabled(!model.hasText && model.fileURL == nil)
            Button(model.saveNeedsTitle ? "Save…" : "Save", systemImage: "square.and.arrow.down") { request(.save) }
                .disabled(!model.canSave)
            ShareLink(item: model.plainText)
                .disabled(!model.hasText)
            Toggle("Phrasebook", systemImage: "book", isOn: hidingKeyboard($showsPhrasebook))
        }
        Section {
            if model.fileURL != nil {
                Button("Save as New Entry…", systemImage: "plus.square.on.square") { request(.saveAsNewEntry) }
                    .disabled(!model.canSave)
            }
            explainItem
        }
        Section {
            FontSizePicker()
            Button("Progress", systemImage: "chart.bar.xaxis") {
                hideKeyboard()
                showsProgress = true
            }
            Button("Settings", systemImage: "gear") {
                hideKeyboard()
                showsSettings = true
            }
        }
    }

    /// Explain, with the reason it's unavailable as a subtitle, since a menu item can't show a tooltip.
    ///
    /// An open panel can always be closed, even once an error appears and the panel locks.
    private var explainItem: some View {
        let reason = ExplainToggle.reason(for: model)
        return Button {
            hideKeyboard()
            showsExplanation.toggle()
        } label: {
            Label(showsExplanation ? "Hide Explanation" : "Explain", systemImage: "lightbulb")
            if let reason, !showsExplanation {
                Text(reason)
            }
        }
        .disabled(!showsExplanation && reason != nil)
    }

    /// Hides the keyboard, then hands the file command to the editor.
    private func request(_ fileRequest: FileRequest) {
        hideKeyboard()
        perform(fileRequest)
    }

    /// Wraps a panel binding so turning it on or off hides the keyboard first.
    private func hidingKeyboard(_ isOn: Binding<Bool>) -> Binding<Bool> {
        Binding {
            isOn.wrappedValue
        } set: { newValue in
            hideKeyboard()
            isOn.wrappedValue = newValue
        }
    }
}

/// An icon button that opens and closes a panel, showing a selected background while the
/// panel is open, as Apple's guidelines ask of a button that behaves like a toggle.
///
/// It hides the keyboard first, so a panel never opens with the keyboard still up.
struct PanelToggle: View {

    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: Binding {
            isOn
        } set: { newValue in
            hideKeyboard()
            isOn = newValue
        }) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .toggleStyle(.button)
    }
}

/// The Explain toggle. Like play, it's enabled only for French with no errors, and
/// greyed out rather than hidden without Apple Intelligence so learners know it's there.
///
/// An open panel can always be closed, even once an error appears and the panel locks.
struct ExplainToggle: View {

    let model: EditorModel
    @Binding var isOn: Bool

    var body: some View {
        PanelToggle(title: "Explain", systemImage: "lightbulb", isOn: $isOn)
            .disabled(!isOn && reason != nil)
            .help(reason ?? "Explain this French")
            .accessibilityHint(reason ?? "Explains the phrases in this French")
    }

    /// Why there's nothing to explain yet, or `nil` when there is.
    private var reason: String? {
        Self.reason(for: model)
    }

    /// Why `model` has nothing to explain yet, or `nil` when it has; the More menu shows it too.
    static func reason(for model: EditorModel) -> String? {
        if !PassageExplainer.isAvailable { return "Explain needs Apple Intelligence." }
        if !model.hasFrench { return "Write some French to explain it." }
        if model.isLocked { return "Explain unlocks when the French is correct." }
        return nil
    }
}

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
