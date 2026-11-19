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

/// The line that gives an entry its painting: a review marker with the keyword
/// `tableau` and the painting's French title, such as `//: tableau Le parc`.
///
/// The line is ordinary text in the entry, visible in the editor and in any text editor,
/// so nothing else records which painting an entry has. It can sit on any line of its
/// own; the first one counts, and one inside a `/* */` note doesn't. Like every note,
/// the checker, Play and the postcard skip it.
///
/// Offsets are character offsets, as in `Notes`.
enum PaintingLine {

    /// The marker keyword that names a painting.
    static let keyword = "tableau"

    /// The whole line for `tableau`, as Add Painting and Replace Painting write it.
    static func text(for tableau: Tableau) -> String {
        "//: \(keyword) \(tableau.title)"
    }

    /// The range and typed title of every painting line in `text`, in order.
    static func all(in text: String) -> [(range: Range<Int>, title: String)] {
        let characters = Array(text)
        return Notes.markerRanges(in: text).compactMap { marker in
            // After "//:", skip spaces, then the keyword must stand alone.
            let body = characters[(marker.lowerBound + 3)..<marker.upperBound].drop(while: \.isWhitespace)
            let word = body.prefix(while: { !$0.isWhitespace })
            guard String(word).lowercased() == keyword else { return nil }
            let title = String(body.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
            return (marker, title)
        }
    }

    /// The painting line that counts: the first one in `text`, or `nil` when there's none.
    static func first(in text: String) -> (range: Range<Int>, title: String)? {
        all(in: text).first
    }

    /// The painting `text` names, or `nil` with no painting line or an unknown title.
    static func tableau(in text: String) -> Tableau? {
        first(in: text).flatMap { TableauCatalog.tableau(titled: $0.title) }
    }

    /// The painting lines that show no painting, for the editor to color as plain notes:
    /// every one after the first, and the first too when its title is unknown.
    static func inactiveRanges(in text: String) -> [Range<Int>] {
        let lines = all(in: text)
        guard let first = lines.first else { return [] }
        let rest = lines.dropFirst().map(\.range)
        return TableauCatalog.tableau(titled: first.title) == nil ? [first.range] + rest : rest
    }

    /// The one edit that gives `text` the painting `tableau`, or takes its painting away
    /// when `tableau` is `nil`: the characters to replace and what replaces them.
    ///
    /// A new line goes at the top. Replacing rewrites the first painting line where it is,
    /// even one with an unknown title. Removing takes out that line and its line break.
    /// Returns `nil` when there's nothing to change.
    static func edit(setting tableau: Tableau?, in text: String) -> (range: Range<Int>, replacement: String)? {
        let characters = Array(text)
        let current = first(in: text)
        switch (tableau, current) {
        case (let tableau?, nil):
            return (0..<0, self.text(for: tableau) + "\n")
        case (let tableau?, let line?):
            let replacement = self.text(for: tableau)
            return String(characters[line.range]) == replacement ? nil : (line.range, replacement)
        case (nil, let line?):
            return (wholeLine(around: line.range, in: characters), "")
        case (nil, nil):
            return nil
        }
    }

    /// `text` with `edit(setting:in:)` applied.
    static func setting(_ tableau: Tableau?, in text: String) -> String {
        guard let edit = edit(setting: tableau, in: text) else { return text }
        var characters = Array(text)
        characters.replaceSubrange(edit.range, with: Array(edit.replacement))
        return String(characters)
    }

    /// The marker's line from its start, including the line break after it, or the one
    /// before it when it's the last line, so removing it leaves no blank line behind.
    private static func wholeLine(around marker: Range<Int>, in characters: [Character]) -> Range<Int> {
        let start = characters[..<marker.lowerBound].lastIndex(where: \.isNewline).map { $0 + 1 } ?? 0
        if marker.upperBound < characters.count {
            return start..<(marker.upperBound + 1)
        }
        return (start > 0 ? start - 1 : start)..<marker.upperBound
    }
}
