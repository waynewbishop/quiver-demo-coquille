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

/// The iPhone and iPad bar: the English toggle and the play button, which stays
/// locked until the French is correct.
struct BottomBar: View {

    @Bindable var model: EditorModel
    /// Called when the learner taps the locked play button.
    let jumpToFirstError: () -> Void

    var body: some View {
        HStack {
            Toggle("English", isOn: $model.isEnglishOn)
                .toggleStyle(.switch)
                .fixedSize()
                .font(.body.weight(.medium))

            if model.cannotKeepDraft { DraftWarning() }

            Spacer()

            PlayControl(model: model, jumpToFirstError: jumpToFirstError)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// A quiet warning that the writing couldn't be kept for next launch, shown until a
/// later attempt succeeds. Saving to the journal is unaffected.
struct DraftWarning: View {

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .help("Coquille couldn't keep this writing for next time. Save it to your journal to be safe.")
            .accessibilityLabel("Writing not kept")
            .accessibilityHint("Coquille couldn't keep this writing for next time. Save it to your journal to be safe.")
    }
}

#if !os(macOS)
/// The iPhone bar: status on the left beside the English toggle, and play on the right.
///
/// The status chip lives here rather than in the navigation bar, as it does in the Mac
/// footer, so it always has room for "2 errors · 1 warning" on one line.
struct CompactBottomBar: View {

    @Bindable var model: EditorModel
    @Binding var showsIssueList: Bool
    /// Whether the French editor has the keyboard up.
    let isEditing: Bool
    /// Whether height is scarce, as in landscape, which slims the bar and its play button.
    var isShort = false
    /// Hides the keyboard by taking focus from the editor.
    let dismissKeyboard: () -> Void
    /// Called when the learner taps the locked play button.
    let jumpToFirstError: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                dismissKeyboard()
                showsIssueList = true
            } label: {
                StatusChip(errors: model.blockingIssues.count, warnings: model.warnings.count, isGentle: true)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityHint("Shows every issue")

            // Grey when off and solid blue when on, so the state reads at a glance.
            Button {
                dismissKeyboard()
                model.isEnglishOn.toggle()
            } label: {
                Image(systemName: "translate")
                    .font(.body.weight(.medium))
                    .foregroundStyle(model.isEnglishOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(model.isEnglishOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("English")
            .accessibilityValue(model.isEnglishOn ? "On" : "Off")
            .accessibilityHint("Shows the English translation below the French")

            if model.cannotKeepDraft { DraftWarning() }

            Spacer(minLength: 0)

            // Shown only while typing, as in Things, so the learner can see the whole page again.
            if isEditing {
                Button(action: dismissKeyboard) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.fill.tertiary))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide keyboard")
                .transition(.scale.combined(with: .opacity))
            }

            // The chip already counts the errors, so the locked caption only says why play
            // waits; while typing there's no room for any caption beside the keyboard button.
            PlayControl(model: model, diameter: isShort ? 44 : 52, usesShortLockedCaption: true, showsCaption: !isEditing, jumpToFirstError: jumpToFirstError)
        }
        .animation(.snappy(duration: 0.2), value: isEditing)
        .padding(.horizontal, 16)
        .padding(.vertical, isShort ? 4 : 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
#endif

#if os(macOS)
/// The Mac footer: status on the left and the English toggle on the right. Play
/// sits in the toolbar, as Run does in Xcode.
struct MacBottomBar: View {

    @Bindable var model: EditorModel
    @Binding var showsIssueList: Bool

    var body: some View {
        HStack(spacing: 16) {
            Button {
                showsIssueList = true
            } label: {
                StatusChip(errors: model.blockingIssues.count, warnings: model.warnings.count, isGentle: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows every issue")

            if model.cannotKeepDraft { DraftWarning() }

            Spacer()

            Toggle("English", isOn: $model.isEnglishOn)
                .toggleStyle(.switch)
                .fixedSize()
                .font(.body.weight(.medium))
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// The Mac toolbar's play and pause button, disabled while errors remain. It shares
/// a group with `MacStopButton`, as Run and Stop do in Xcode.
struct MacPlayButton: View {

    let model: EditorModel

    var body: some View {
        Button(action: model.togglePlay) {
            Label(model.narrator.isSpeaking ? "Pause" : "Play", systemImage: model.narrator.isSpeaking ? "pause.fill" : "play.fill")
        }
        .disabled(model.isLocked || !model.hasFrench)
        .help(model.narrator.isSpeaking ? "Pause" : "Read aloud in French")
        .accessibilityLabel(model.narrator.isSpeaking ? "Pause" : model.narrator.state == .paused ? "Resume" : "Read aloud in French")
    }
}

/// The Mac toolbar's stop button: ends playback, so the next play starts from the top.
struct MacStopButton: View {

    let model: EditorModel

    var body: some View {
        Button(action: model.stopPlaying) {
            Label("Stop", systemImage: "stop.fill")
        }
        .disabled(model.narrator.state == .idle)
        .help("Stop")
    }
}
#endif

/// The iPhone and iPad play button with its caption: locked with a dashed ring while
/// errors remain, otherwise play and pause.
struct PlayControl: View {

    let model: EditorModel
    /// The button's diameter, in points.
    var diameter = 60.0
    /// Whether the locked caption is "Fix to listen" rather than "Fix 2 errors to play",
    /// for a bar whose status chip already gives the count.
    var usesShortLockedCaption = false
    /// Whether any caption shows beside the button.
    var showsCaption = true
    /// Called when the learner taps the locked play button.
    let jumpToFirstError: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            caption
            if model.isLocked {
                lockedPlay
            } else {
                play
            }
        }
    }

    /// "Fix 4 errors to play", "Speaking French…", or "Paused".
    private var caption: some View {
        Group {
            if !showsCaption {
                EmptyView()
            } else if model.isLocked && usesShortLockedCaption {
                Text("Fix to\nlisten")
            } else if model.isLocked {
                // Beside the button, the caption wraps to stay compact.
                Text("Fix \(plural(model.blockingIssues.count, "error"))\nto play")
            } else if model.narrator.isSpeaking {
                Text("Speaking French…")
            } else if model.narrator.state == .paused {
                Text("Paused")
            }
        }
        .font(.footnote)
        .multilineTextAlignment(.trailing)
        .foregroundStyle(.secondary)
    }

    /// The dashed lock button; tapping it opens the first error.
    private var lockedPlay: some View {
        Button(action: jumpToFirstError) {
            Image(systemName: "lock")
                .font(.title3)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(.quaternary))
                .overlay(Circle().strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Play locked. Fix \(plural(model.blockingIssues.count, "error")) to play.")
        .accessibilityHint("Goes to the first error")
    }

    /// Play and pause.
    private var play: some View {
        Button {
            hideKeyboard()
            model.togglePlay()
        } label: {
            Image(systemName: model.narrator.isSpeaking ? "pause.fill" : "play.fill")
                .font(.title3)
                // An empty page shows a plain disabled control, not a faded blue one.
                .foregroundStyle(model.hasFrench ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary))
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(model.hasFrench ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!model.hasFrench)
        .accessibilityLabel(model.narrator.isSpeaking ? "Pause" : model.narrator.state == .paused ? "Resume" : "Read aloud in French")
    }
}
