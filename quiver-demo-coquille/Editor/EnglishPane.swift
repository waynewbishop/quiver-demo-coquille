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

/// The on-device English, or why it isn't shown yet.
///
/// While errors remain, the pane shows a locked message instead of a translation:
/// the translator is forgiving, so "une fromage" would still come out as "a cheese",
/// and clean English would hide the mistake.
struct EnglishPane: View {

    let model: EditorModel
    /// Whether to draw the header as a bar, as in the side-by-side layout.
    let showsHeaderBar: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "ENGLISH · ON-DEVICE", showsDivider: showsHeaderBar)

            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
            }
        }
        .background(.background.secondary)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLocked {
            Label {
                Text("The English appears once the French is correct. Fix \(plural(model.blockingIssues.count, "error")) to see it.")
            } icon: {
                Image(systemName: "lock")
            }
            .font(.plexSans(15, relativeTo: .subheadline))
            .foregroundStyle(.secondary)
        } else {
            switch model.english {
            case .idle:
                EmptyView()
            case .translating:
                ProgressView()
            case .translated(let english):
                Text(english)
                    .font(.plexSans(Typography.englishSize, relativeTo: .body))
                    .lineSpacing(Typography.englishLineSpacing)
                    .foregroundStyle(.primary.opacity(0.85))
                    .textSelection(.enabled)
            case .unavailable(let message):
                Text(message)
                    .font(.plexSans(15, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
