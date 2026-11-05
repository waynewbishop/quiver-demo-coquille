//
//  PlaybackCommands.swift
//  quiver-demo-coquille
//

import SwiftUI

extension FocusedValues {
    /// The focused window's editor, for the Play menu.
    @Entry var editorModel: EditorModel?
}

/// The Play menu on the Mac and iPad: Play and Stop as in Xcode's Run and Stop, then
/// the issue and English keys.
///
/// ⌘↵ plays from anywhere in the window, matching the Quiver Notebook's Run; inside the
/// editor, ⇧↵ does the same. Like Run, Play does nothing until the French is correct.
struct PlaybackCommands: Commands {

    @FocusedValue(\.editorModel) private var model

    var body: some Commands {
        CommandMenu("Play") {
            Button(playTitle) { model?.togglePlay() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canPlay)
            Button("Stop") { model?.stopPlaying() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(model == nil || model?.narrator.state == .idle)

            Divider()

            Button("Next Issue") { model?.selectAdjacentIssue(forward: true) }
                .keyboardShortcut("'", modifiers: .command)
                .disabled(model?.visibleIssues.isEmpty ?? true)
            Button("Previous Issue") { model?.selectAdjacentIssue(forward: false) }
                .keyboardShortcut("'", modifiers: [.command, .shift])
                .disabled(model?.visibleIssues.isEmpty ?? true)

            Divider()

            Button(model?.isEnglishOn == true ? "Hide English" : "Show English") {
                model?.isEnglishOn.toggle()
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
            .disabled(model == nil)
        }
    }

    /// Play, Pause or Resume, following the narrator.
    private var playTitle: String {
        switch model?.narrator.state {
        case .speaking: "Pause"
        case .paused: "Resume"
        default: "Play"
        }
    }

    /// Whether Play would do anything, matching the toolbar's Play button.
    private var canPlay: Bool {
        guard let model else { return false }
        return model.narrator.state != .idle || (!model.isLocked && model.hasFrench)
    }
}
