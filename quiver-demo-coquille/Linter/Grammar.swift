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
/// implements its own conformer. The linter never asks which language it is checking.
nonisolated protocol Grammar: Sendable {
    /// Returns every grammar issue in `text`, ordered by position.
    func check(_ text: String) -> [Issue]
}

/// A fixed phrase that is correct but has a more natural alternative, from `fr.idioms.json`.
nonisolated struct Idiom: Codable, Equatable, Sendable {
    let phrase: String
    let suggestion: String
    let note: String
}

/// A phrase that is wrong wherever it appears, apart from listed exceptions, and its
/// fix: look-alikes such as "comment cava" from `fr.lookalikes.json`, and English
/// patterns such as "je suis faim" from `fr.wordchoice.json`.
nonisolated struct PhraseFix: Codable, Equatable, Sendable {
    /// The words as a learner writes them, such as "cava" or "je suis faim".
    let phrase: String
    /// The words the learner means, such as "ça va" or "j'ai faim".
    let fix: String
    /// Words after which the phrase is correct French, so the rule stays silent, as in "il cava".
    let unlessAfter: [String]
    /// Words that must come right before the phrase, as in "a fait une décision", where the
    /// fix depends on the tense. `nil` means the phrase applies after any word.
    var onlyAfter: [String]? = nil
    /// Words after which the phrase is correct French, so the rule stays silent, as in "cava un trou".
    var unlessBefore: [String]? = nil
    /// Why the phrase is wrong, without the answer.
    let note: String
}
