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

            Spacer()

            PlayControl(model: model, jumpToFirstError: jumpToFirstError)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

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
                StatusChip(errors: model.blockingIssues.count, warnings: model.warnings.count)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows every issue")

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
        .disabled(model.isLocked || !model.hasText)
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
    /// Called when the learner taps the locked play button.
    let jumpToFirstError: () -> Void

    /// The button's diameter, in points.
    private static let diameter = 60.0

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
            if model.isLocked {
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
                .frame(width: Self.diameter, height: Self.diameter)
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
        Button(action: model.togglePlay) {
            Image(systemName: model.narrator.isSpeaking ? "pause.fill" : "play.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: Self.diameter, height: Self.diameter)
                .background(Circle().fill(.tint))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!model.hasText)
        .opacity(model.hasText ? 1.0 : 0.4)
        .accessibilityLabel(model.narrator.isSpeaking ? "Pause" : model.narrator.state == .paused ? "Resume" : "Read aloud in French")
    }
}
