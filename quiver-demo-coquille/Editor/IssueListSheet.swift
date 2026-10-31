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

/// Every issue at once, like Xcode's issue navigator. Tapping a row jumps to it.
struct IssueListSheet: View {

    @Bindable var model: EditorModel
    /// Called with the row the learner tapped.
    let open: (Issue) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        macBody
        #else
        NavigationStack {
            List {
                Section {
                    if model.visibleIssues.isEmpty {
                        ContentUnavailableView("No issues", systemImage: "checkmark.circle")
                    }
                    ForEach(model.visibleIssues) { issue in
                        Button {
                            open(issue)
                        } label: {
                            row(for: issue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section {
                    Toggle("Show suggestions", isOn: $model.showsSuggestions)
                } footer: {
                    Text(Self.suggestionsNote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("Issues")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #endif
    }

    /// What the suggestions toggle controls.
    private static let suggestionsNote = "When on, Coquille also points out correct French that could sound more natural. Errors and warnings always show."

    #if os(macOS)
    /// The Mac sheet: a header, the issues, and the suggestions toggle and Done in a
    /// footer, so the note under the toggle wraps instead of being cut off.
    private var macBody: some View {
        VStack(spacing: 0) {
            Text("Issues")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            Divider()

            List {
                ForEach(model.visibleIssues) { issue in
                    Button {
                        open(issue)
                    } label: {
                        row(for: issue)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.inset)
            // An overlay, not a row, so the empty state sits in the middle of the list.
            .overlay {
                if model.visibleIssues.isEmpty {
                    ContentUnavailableView("No issues", systemImage: "checkmark.circle")
                }
            }

            Divider()

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Show suggestions", isOn: $model.showsSuggestions)
                    Text(Self.suggestionsNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 480, height: 380)
    }
    #endif

    /// One issue: its severity, the flagged words, the hint, and its kind. The fix stays
    /// on the card, so the list never hands out every answer at once.
    private func row(for issue: Issue) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: issue.severity.symbolName)
                .foregroundStyle(issue.severity.tint)
                .accessibilityLabel(issue.severity.rawValue)
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.original)
                    .font(.body.monospaced())
                Text(issue.hint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(issue.kind.label + " · " + issue.severity.rawValue.uppercased())
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .frame(minHeight: 44)
    }
}

extension Severity {
    /// The symbol that marks this severity in the issue list.
    var symbolName: String {
        switch self {
        case .error: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .suggestion: "lightbulb"
        }
    }
}
