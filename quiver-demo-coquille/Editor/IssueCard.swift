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

/// The open issue: the rule as a hint, then on request the fix and its reason, where
/// the verdict came from, and Ignore / Apply.
///
/// The card names the rule and leaves the fix to the learner, who can still ask for it.
/// An issue with no replacement, such as an unknown word, has no fix to show.
struct IssueCard: View {

    let issue: Issue
    let model: EditorModel
    /// Whether the learner asked to see the fix.
    @State private var showsFix = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(issue.kind.label + " · " + issue.severity.rawValue.uppercased())
                    .font(.plexMono(12, relativeTo: .caption))
                    .tracking(1)
                    .foregroundStyle(issue.severity.tint)
                Spacer()
                Button {
                    hideKeyboard()
                    model.closeCard()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close")
            }

            if showsFix, let replacement = issue.replacement {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(issue.original)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("becomes")
                    Text(replacement)
                        .font(.plexMono(16, weight: .medium, relativeTo: .body))
                        .foregroundStyle(.tint)
                }
                .font(.plexMono(16, relativeTo: .body))
            } else {
                Text(issue.original)
                    .font(.plexMono(16, relativeTo: .body))
                    .underline(pattern: .dot, color: issue.severity.tint)
            }

            Text(showsFix ? issue.reason : issue.hint)
                .font(.plexSans(14, relativeTo: .subheadline))
                .fixedSize(horizontal: false, vertical: true)

            if !issue.choices.isEmpty {
                choiceList
            }

            HStack(spacing: 12) {
                Text(issue.source)
                    .font(.plexSans(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Ignore") {
                    hideKeyboard()
                    model.ignore(issue)
                }
                .buttonStyle(.bordered)
                if issue.replacement != nil {
                    if showsFix {
                        Button("Apply fix") {
                            hideKeyboard()
                            model.apply(issue)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Show fix") {
                            hideKeyboard()
                            showsFix = true
                        }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .controlSize(.regular)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
    }

    /// The wordings to pick between, each with its meaning. The learner's own wording
    /// is marked Keep; any other replaces it.
    private var choiceList: some View {
        VStack(spacing: 0) {
            ForEach(Array(issue.choices.enumerated()), id: \.offset) { position, choice in
                if position > 0 {
                    Divider()
                }
                Button {
                    hideKeyboard()
                    model.choose(choice, for: issue)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(choice.text)
                                .font(.plexMono(16, weight: .medium, relativeTo: .body))
                            Text(choice.meaning)
                                .font(.plexSans(13, relativeTo: .footnote))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Text(issue.isOriginal(choice) ? "Keep" : "Use this")
                            .font(.plexSans(13, relativeTo: .footnote))
                            .foregroundStyle(.tint)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(choice.text): \(choice.meaning)")
                .accessibilityHint(issue.isOriginal(choice) ? "Keeps your wording" : "Replaces your wording")
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
    }
}

extension Severity {
    /// The color that marks this severity in chips, cards and lists.
    var tint: Color {
        switch self {
        case .error: .red
        case .warning: .orange
        case .suggestion: .secondary
        }
    }
}
