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

            PlayControl(model: model, diameter: 60, captionEdge: .leading, jumpToFirstError: jumpToFirstError)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

#if os(macOS)
/// The Mac footer, laid out as in the design: status on the left, play in the
/// middle, and the English toggle on the right.
struct MacBottomBar: View {

    @Bindable var model: EditorModel
    @Binding var showsIssueList: Bool
    /// Called when the learner clicks the locked play button.
    let jumpToFirstError: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button {
                showsIssueList = true
            } label: {
                StatusChip(errors: model.blockingIssues.count, warnings: model.warnings.count)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows every issue")
            .frame(maxWidth: .infinity, alignment: .leading)

            PlayControl(model: model, diameter: 44, captionEdge: .trailing, jumpToFirstError: jumpToFirstError)

            Toggle("English", isOn: $model.isEnglishOn)
                .toggleStyle(.switch)
                .fixedSize()
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
#endif

/// The play button with its caption: locked with a dashed ring while errors remain,
/// otherwise play and pause, where a long press plays at about half speed.
struct PlayControl: View {

    let model: EditorModel
    let diameter: Double
    /// Which side of the button the caption sits on.
    let captionEdge: HorizontalEdge
    /// Called when the learner taps the locked play button.
    let jumpToFirstError: () -> Void

    /// The width kept for a caption on the button's right, wide enough for the longest one.
    private static let trailingCaptionWidth = 160.0

    /// Set by a long press so the tap that ends it doesn't also play at normal speed.
    @State private var longPressPlayed = false

    var body: some View {
        HStack(spacing: 12) {
            if captionEdge == .leading { caption }
            if model.isLocked {
                lockedPlay
            } else {
                play
            }
            if captionEdge == .trailing {
                // A fixed-width slot, so the button never moves as the caption changes.
                caption
                    .frame(width: Self.trailingCaptionWidth, alignment: .leading)
            }
        }
    }

    /// "Fix 4 errors to play", "Hold for slow", "Speaking French…", or "Paused".
    private var caption: some View {
        Group {
            if model.isLocked {
                // Beside the button on the left, the caption wraps to stay compact.
                Text("Fix \(plural(model.blockingIssues.count, "error"))" + (captionEdge == .leading ? "\nto play" : " to play"))
            } else if model.narrator.isSpeaking {
                Text("Speaking French…")
            } else if model.narrator.state == .paused {
                Text("Paused")
            } else if model.hasText {
                Text("Hold for slow")
            }
        }
        .font(.footnote)
        .multilineTextAlignment(captionEdge == .leading ? .trailing : .leading)
        .foregroundStyle(.secondary)
    }

    /// The dashed lock button; tapping it opens the first error.
    private var lockedPlay: some View {
        Button(action: jumpToFirstError) {
            Image(systemName: "lock")
                .font(diameter < 50 ? .body : .title3)
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

    /// Play and pause; a long press plays at about half speed.
    private var play: some View {
        Button {
            if longPressPlayed {
                longPressPlayed = false
            } else {
                model.togglePlay()
            }
        } label: {
            Image(systemName: model.narrator.isSpeaking ? "pause.fill" : "play.fill")
                .font(diameter < 50 ? .body : .title3)
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(.tint))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!model.hasText)
        .opacity(model.hasText ? 1.0 : 0.4)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                longPressPlayed = true
                model.togglePlay(slowly: true)
            }
        )
        .accessibilityLabel(model.narrator.isSpeaking ? "Pause" : model.narrator.state == .paused ? "Resume" : "Read aloud in French")
        .accessibilityAction(named: "Read slowly") { model.togglePlay(slowly: true) }
    }
}
