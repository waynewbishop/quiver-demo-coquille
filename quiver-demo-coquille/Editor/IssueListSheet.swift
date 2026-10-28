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
                    Text("Suggestions point out a more natural way to say correct French. They never block play.")
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
        .frame(minWidth: 360, minHeight: 420)
    }

    /// One issue: its severity, the word and its fix, and its kind.
    private func row(for issue: Issue) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: issue.severity.symbolName)
                .foregroundStyle(issue.severity.tint)
                .accessibilityLabel(issue.severity.rawValue)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(issue.original).strikethrough().foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                    Text(issue.replacement).foregroundStyle(.tint)
                }
                .font(.body.monospaced())
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
