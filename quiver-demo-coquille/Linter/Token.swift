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

/// One word of the learner's text, with the characters that follow it.
nonisolated struct Token: Equatable, Sendable {
    /// The word as typed.
    let text: String
    /// Lowercased, with typographic apostrophes folded to `'`, for lexicon lookups.
    let normalized: String
    /// Character offset of the word in the linted text.
    let offset: Int
    /// The characters between this word and the next one (or the end of the text).
    let gap: String

    /// The character offset just past the end of the word.
    var end: Int {
        offset + text.count
    }

    /// Whether the next word follows directly, with only spaces between, as in
    /// "une fromage", or glued by an elided article, as in "l'arbre".
    var isAdjacentToNext: Bool {
        if gap.isEmpty {
            return normalized.hasSuffix("'")
        }
        return gap.allSatisfy { $0 == " " || $0 == "\u{00A0}" }
    }

    /// Whether punctuation or a line break follows this word before the next one.
    /// The last word of the text reports `false` when nothing follows it; callers
    /// treat the end of the text separately.
    var endsClause: Bool {
        for character in gap {
            if character.isNewline { return true }
            if character.isWhitespace { continue }
            return ".!?;,:…".contains(character)
        }
        return false
    }

    /// Whether the word begins with a vowel, which is where French elides articles.
    var startsWithVowel: Bool {
        guard let first = normalized.first else { return false }
        return "aeiouyàâäéèêëîïôöùûüœæ".contains(first)
    }

    /// Whether the word begins with a vowel or an h, either of which can trigger elision.
    var startsWithVowelOrH: Bool {
        startsWithVowel || normalized.first == "h"
    }
}
