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

/// The learner's quoted text, which the checker skips just as a compiler skips the
/// contents of a string literal.
///
/// A span opens with `"`, `“` or `«` and ends at the matching `"`, `”` or `»` on the same
/// line, so a name such as "Trader Joe's" stays whole. An apostrophe never ends a span.
/// The quote marks themselves stay in the text; only what sits between them is skipped.
/// A quote with no closing mark is never an error: it raises a warning at the opening
/// mark, and only the rest of that line goes unchecked.
enum Quotes {

    /// The closing mark for each opening mark.
    private static let closers: [Character: Character] = ["\"": "\"", "“": "”", "«": "»"]

    /// The character offsets of the text between each pair of quote marks in `text`, in
    /// order, leaving out the marks themselves. An unclosed quote covers the rest of its line.
    static func ranges(in text: String) -> [Range<Int>] {
        spans(in: text).map(\.content)
    }

    /// The offset of every opening mark in `text` that has no closing mark on its line.
    static func unclosed(in text: String) -> [Int] {
        spans(in: text).filter { !$0.isClosed }.map(\.open)
    }

    /// A warning for each unclosed quote in `text`, pointing at its opening mark.
    static func unclosedIssues(in text: String) -> [Issue] {
        let characters = Array(text)
        return unclosed(in: text).map { offset in
            Issue(
                kind: .quotation,
                severity: .warning,
                offset: offset,
                length: 1,
                original: String(characters[offset]),
                replacement: nil,
                reason: "This quotation mark never closes, so the rest of the line isn't checked.",
                hint: "Close the quote after the name or phrase.",
                source: "Coquille · quoted text"
            )
        }
    }

    /// `text` with every quoted character turned to spaces, keeping its line breaks, so
    /// each character of French stays at the same offset as in the learner's text.
    static func masked(_ text: String) -> String {
        let quoted = ranges(in: text)
        guard !quoted.isEmpty else { return text }
        var characters = Array(text)
        for range in quoted {
            for index in range where !characters[index].isNewline {
                characters[index] = " "
            }
        }
        return String(characters)
    }

    /// Each quote in `text`: where it opens, the offsets of what it holds, and whether its
    /// closing mark was found on the same line.
    private static func spans(in text: String) -> [(open: Int, content: Range<Int>, isClosed: Bool)] {
        let characters = Array(text)
        var found: [(open: Int, content: Range<Int>, isClosed: Bool)] = []
        var index = 0
        while index < characters.count {
            guard let closer = closers[characters[index]] else {
                index += 1
                continue
            }
            let start = index + 1
            var probe = start
            while probe < characters.count, characters[probe] != closer, !characters[probe].isNewline {
                probe += 1
            }
            let isClosed = probe < characters.count && characters[probe] == closer
            found.append((index, start..<probe, isClosed))
            index = isClosed ? probe + 1 : probe
        }
        return found
    }
}
