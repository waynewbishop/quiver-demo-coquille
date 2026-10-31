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

/// Every error the learner fixed, newest first: what they wrote, what it became, and
/// the sentence it sat in, like the corrections list at the back of a paper journal.
///
/// Shown from Your progress, and on the Mac in its own Corrections window too.
struct CorrectionsView: View {

    let store: StatsStore

    var body: some View {
        let corrections = store.stats.corrections.reversed()
        Group {
            if corrections.isEmpty {
                ContentUnavailableView(
                    "No corrections yet",
                    systemImage: "pencil.and.list.clipboard",
                    description: Text("Errors you fix will appear here, with the sentence they were in.")
                )
            } else {
                List(Array(corrections)) { correction in
                    CorrectionRow(correction: correction)
                }
            }
        }
        .navigationTitle("Corrections")
        .frame(minWidth: 380, minHeight: 420)
    }
}

/// One correction: the mistake struck through, its fix, the sentence, and the kind and date.
private struct CorrectionRow: View {

    let correction: LearnerStats.Correction

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(correction.original)
                    .strikethrough()
                    .foregroundStyle(.red)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("became")
                Text(correction.corrected ?? "your own spelling")
                    .foregroundStyle(correction.corrected == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            }
            .font(.body.monospaced())

            if let sentence = correction.sentence {
                Text(sentence)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text(details)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// "Gender · fixed by you · 31 Oct 2026", with "applied" for a fix chosen from a card.
    private var details: String {
        let kind = IssueKind(rawValue: correction.kind)?.displayName ?? correction.kind
        let how = correction.byLearner ? "fixed by you" : "applied"
        return [kind, how, correction.date.formatted(date: .abbreviated, time: .omitted)].joined(separator: " · ")
    }
}
