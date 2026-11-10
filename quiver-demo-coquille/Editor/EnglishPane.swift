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
    /// The learner's text size, from the View menu.
    @AppStorage(FontSize.storageKey) private var fontSize = FontSize.standard
    /// The system's text size setting, as a multiplier, so the system font grows with it.
    @ScaledMetric(relativeTo: .body) private var textScale = 1.0

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
        // A cream a shade darker than the French pane's in light mode; in dark mode the
        // color is clear, so the secondary background shows through.
        .background(Color.englishPaper)
        .background(.background.secondary)
    }

    /// Apple's system font at `size`, scaled with the system's text size setting.
    private func systemFont(_ size: Double) -> Font {
        .system(size: size * textScale)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLocked {
            Label {
                Text("The English appears once the French is correct. Fix \(plural(model.blockingIssues.count, "error")) to see it.")
            } icon: {
                Image(systemName: "lock")
            }
            .font(systemFont(15))
            .foregroundStyle(.secondary)
        } else {
            switch model.english {
            case .idle:
                EmptyView()
            case .translating:
                ProgressView()
            case .translated(let english):
                Text(english)
                    .font(systemFont(fontSize.englishSize))
                    .lineSpacing(fontSize.englishLineSpacing)
                    .foregroundStyle(.primary.opacity(0.85))
                    .textSelection(.enabled)
            case .unavailable(let message):
                Text(message)
                    .font(systemFont(15))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
