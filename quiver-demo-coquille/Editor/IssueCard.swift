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

/// The open issue: the fix, a one-line reason, where the verdict came from, and Ignore / Apply.
struct IssueCard: View {

    let issue: Issue
    let model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(issue.kind.label + " · " + issue.severity.rawValue.uppercased())
                    .font(.plexMono(12, relativeTo: .caption))
                    .tracking(1)
                    .foregroundStyle(issue.severity.tint)
                Spacer()
                Button(action: model.closeCard) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close")
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(issue.original)
                    .strikethrough()
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("becomes")
                Text(issue.replacement)
                    .font(.plexMono(16, weight: .medium, relativeTo: .body))
                    .foregroundStyle(.tint)
            }
            .font(.plexMono(16, relativeTo: .body))

            Text(issue.reason)
                .font(.plexSans(14, relativeTo: .subheadline))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Text(issue.source)
                    .font(.plexSans(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Ignore") { model.ignore(issue) }
                    .buttonStyle(.bordered)
                Button("Apply fix") { model.apply(issue) }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.regular)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
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
