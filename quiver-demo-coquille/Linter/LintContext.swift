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

/// The immutable input to one lint pass. Character offsets in tokens and issues refer to `text`.
nonisolated struct LintContext: Sendable {
    let text: String
    let tokens: [Token]
    /// The tokens with the part-of-speech layer's verdicts, decided once for every rule.
    let tagged: TaggedText

    /// Tokenizes `text` and tags it with `tag`, or leaves every word without a verdict.
    init(text: String, tag: (@Sendable ([Token]) -> TaggedText)? = nil) {
        self.text = text
        tokens = FrenchTokenizer.tokens(in: text)
        tagged = tag?(tokens) ?? TaggedText(untagged: tokens)
    }
}
