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

/// The Explain panel: the phrases worth knowing in the whole entry, each with its meaning.
///
/// It sits beside the French, as the phrasebook does, so the entry stays in view. Like the
/// English, it's locked while errors remain, so a mistake is never explained as if it
/// were right. The model's notes are labelled as its own, never as the linter's rules.
struct ExplanationPanel: View {

    let model: EditorModel
    /// The French to explain: linted, with no errors, and without the learner's notes,
    /// or `nil` while that isn't so.
    let french: String?

    /// The last answer and the French it explains, kept while the learner edits so the
    /// phrases don't vanish with every keystroke.
    @State private var explained: Explained?

    /// An answer from the model, for one version of the French.
    private struct Explained {
        let french: String
        let outcome: PassageExplainer.Outcome
    }

    /// How long the French has to stay the same before it's explained again.
    private static var pause: Duration { .seconds(1.5) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
            }

            Text("Explained on your device. It can make mistakes.")
                .font(.plexSans(12, relativeTo: .caption))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: french) { await explainIfNeeded() }
    }

    /// "EXPLANATION" in the panes' label style, with the Experimental tag.
    private var header: some View {
        HStack(spacing: 8) {
            Text("EXPLANATION")
                .font(.plexMono(12, relativeTo: .caption))
                .tracking(1)
                .foregroundStyle(.secondary)
            Text("Experimental")
                .font(.plexSans(11, weight: .medium, relativeTo: .caption2))
                .foregroundStyle(.tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(.tint.opacity(0.14), in: Capsule())
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// Why there's nothing to show yet, or the phrases.
    @ViewBuilder
    private var content: some View {
        if !PassageExplainer.isAvailable {
            message("Explain needs Apple Intelligence.")
        } else if model.isLocked {
            Label {
                Text("The explanation appears once the French is correct. Fix \(plural(model.blockingIssues.count, "error")) to see it.")
            } icon: {
                Image(systemName: "lock")
            }
            .font(.plexSans(14, relativeTo: .subheadline))
            .foregroundStyle(.secondary)
        } else if !model.hasFrench {
            // Blank, like the English pane, until there's French to explain.
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                // The English pane's spinner, while new French waits for its explanation.
                if isWorking {
                    ProgressView()
                }
                if let explained {
                    outcome(explained.outcome)
                        // Out of date while the learner edits, until the new French is explained.
                        .opacity(explained.french == french ? 1 : 0.5)
                }
            }
        }
    }

    /// Whether correct French is waiting on the model: the first explanation, or a new
    /// one after an edit.
    private var isWorking: Bool {
        guard let french else { return false }
        return explained?.french != french
    }

    /// The phrases, or a note when the model couldn't answer.
    @ViewBuilder
    private func outcome(_ outcome: PassageExplainer.Outcome) -> some View {
        switch outcome {
        case .explained(let phrases) where phrases.isEmpty:
            message("Nothing here needs explaining.")
        case .explained(let phrases):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(phrases.enumerated()), id: \.offset) { _, phrase in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .accessibilityHidden(true)
                        line(for: phrase)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.plexSans(14, relativeTo: .body))
            .lineSpacing(2)
            .textSelection(.enabled)
        case .tooLong:
            message("This entry is too long to explain at once.")
        case .failed:
            message("Coquille couldn't explain this French. Try again in a moment.")
        }
    }

    /// "avoir hâte de means can't wait to. It's about eagerness, not hurrying."
    private func line(for phrase: PassageExplainer.Phrase) -> Text {
        let meaning = phrase.meaning.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        var note = phrase.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = note.last, !".!?".contains(last) { note += "." }
        let french = Text(phrase.french).font(.plexSans(14, weight: .medium, relativeTo: .body)).foregroundStyle(.tint)
        let english = Text(meaning).font(.plexSans(14, weight: .medium, relativeTo: .body))
        return Text("\(french) means \(english). \(note)")
    }

    /// A one-line note in place of the phrases.
    private func message(_ text: String) -> some View {
        Text(text)
            .font(.plexSans(14, relativeTo: .subheadline))
            .foregroundStyle(.secondary)
    }

    /// Explains the French once it's correct, right away the first time and after a
    /// pause in typing once there's an answer, so each keystroke doesn't ask the model.
    private func explainIfNeeded() async {
        guard let french, PassageExplainer.isAvailable, explained?.french != french else { return }
        if explained != nil {
            try? await Task.sleep(for: Self.pause)
            guard !Task.isCancelled else { return }
        }
        let outcome = await PassageExplainer.explain(french)
        guard !Task.isCancelled else { return }
        explained = Explained(french: french, outcome: outcome)
    }
}
