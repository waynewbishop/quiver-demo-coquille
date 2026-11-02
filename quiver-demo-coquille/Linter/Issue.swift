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

import Foundation

/// One flagged span of French, with its fix and a one-line reason.
///
/// Positions are character offsets into the exact text that was linted, so an
/// issue is only meaningful alongside that text.
nonisolated struct Issue: Identifiable, Equatable, Sendable {
    let kind: IssueKind
    let severity: Severity
    /// Character offset of the flagged span.
    let offset: Int
    /// Length of the flagged span, in characters.
    let length: Int
    /// The flagged text as the learner typed it.
    let original: String
    /// The suggested replacement for the flagged span, or `nil` when there's nothing
    /// safe to suggest and the fix is left to the learner.
    let replacement: String?
    /// The one-line explanation shown with the fix.
    let reason: String
    /// The rule without the answer, shown first so the learner can try the fix.
    let hint: String
    /// Where the verdict came from, such as "Lexique · known noun".
    let source: String
    /// The wordings to choose between when the text is correct French that may not say
    /// what the learner meant, such as "pas encore" (not yet) or "plus" (no longer).
    /// Empty for every other issue, which has one fix or none.
    var choices: [Choice] = []

    /// The flagged span as a range of character offsets.
    var range: Range<Int> {
        offset..<(offset + length)
    }

    /// Identifies every occurrence of the same mistake, so Ignore applies to all of them.
    var ignoreKey: String {
        "\(kind.rawValue)|\(original.lowercased())|\(replacement?.lowercased() ?? "")"
    }

    /// Unique within one lint pass.
    var id: String {
        "\(offset)|\(ignoreKey)"
    }

    /// Whether `choice` is the wording the learner already wrote.
    func isOriginal(_ choice: Choice) -> Bool {
        choice.text.lowercased() == original.lowercased()
    }
}

/// One wording a learner can pick on a "did you mean" card, with what it means.
nonisolated struct Choice: Codable, Equatable, Sendable {
    /// The French, such as "plus".
    let text: String
    /// What it means, in a few words of English, such as "no longer: you used to".
    let meaning: String
}
