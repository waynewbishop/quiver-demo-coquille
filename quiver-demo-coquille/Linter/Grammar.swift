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

/// A language's grammar rules: the seam where a second language plugs in.
///
/// Agreement and contraction rules are code rather than data, so each language
/// implements its own conformer. The linter never asks which language it is checking:
/// it runs each rule family as its own filter, tagged with its layer and CEFR level.
nonisolated protocol Grammar: Sendable {
    /// The language's rule families, in the order they run.
    var rules: [GrammarRule] { get }

    /// Decides the ambiguous words in `tokens` once, for every rule in a pass to read.
    func tag(_ tokens: [Token]) -> TaggedText
}

nonisolated extension Grammar {
    /// Returns every grammar issue in `text` from every rule, ordered by position.
    func check(_ text: String) -> [Issue] {
        let tagged = tag(FrenchTokenizer.tokens(in: text))
        return rules.flatMap { $0.check(tagged) }.sorted { $0.offset < $1.offset }
    }
}
