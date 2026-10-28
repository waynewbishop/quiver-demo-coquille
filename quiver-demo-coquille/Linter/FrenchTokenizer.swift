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

/// Splits French text into words, keeping each word's position for underlining.
nonisolated enum FrenchTokenizer {

    /// Words that end in an apostrophe when elided before a vowel, such as l'école.
    /// Other apostrophes stay inside the word, as in aujourd'hui.
    static let elisionPrefixes: Set<String> = [
        "l", "d", "j", "m", "t", "s", "n", "c", "qu", "jusqu", "lorsqu", "puisqu", "quoiqu"
    ]

    /// Returns the words of `text` in order, each with its offset and trailing gap.
    ///
    /// - Complexity: O(n) in the number of characters.
    static func tokens(in text: String) -> [Token] {
        let characters = Array(text)
        var spans: [(start: Int, end: Int)] = []
        var start: Int?
        var index = 0

        while index < characters.count {
            let character = characters[index]
            let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
            let nextIsLetter = next?.isLetter ?? false

            if character.isLetter {
                if start == nil { start = index }
            } else if start != nil, character == "-", nextIsLetter {
                // A hyphen inside a word, as in grand-mère, keeps the word whole.
            } else if let wordStart = start, character == "'" || character == "’" {
                let prefix = normalize(String(characters[wordStart..<index]))
                if elisionPrefixes.contains(prefix) {
                    // Elision: the apostrophe closes this word, as in l' + école.
                    spans.append((wordStart, index + 1))
                    start = nil
                } else if !nextIsLetter {
                    spans.append((wordStart, index))
                    start = nil
                }
            } else if let wordStart = start {
                spans.append((wordStart, index))
                start = nil
            }
            index += 1
        }
        if let wordStart = start {
            spans.append((wordStart, characters.count))
        }

        var tokens: [Token] = []
        tokens.reserveCapacity(spans.count)
        for (position, span) in spans.enumerated() {
            let gapEnd = position + 1 < spans.count ? spans[position + 1].start : characters.count
            let word = String(characters[span.start..<span.end])
            tokens.append(Token(
                text: word,
                normalized: normalize(word),
                offset: span.start,
                gap: String(characters[span.end..<gapEnd])
            ))
        }
        return tokens
    }

    /// Lowercases a word and folds the typographic apostrophe to the one Lexique uses.
    static func normalize(_ word: String) -> String {
        word.lowercased().replacingOccurrences(of: "’", with: "'")
    }
}
