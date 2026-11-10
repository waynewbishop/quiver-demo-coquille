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

/// The basic Markdown a learner can write in an entry: `#` headings, `-`, `*` or `+`
/// bullets, numbered items such as `1.`, `**bold**` and `*italic*`.
///
/// The symbols stay in the learner's text, dimmed in the editor like notes. The checker
/// and the voice never see them, since `masked(_:)` turns them to spaces, and the English
/// pane shows the formatting they describe. Markdown inside a note is part of the note.
enum Markdown {

    /// How a line is laid out.
    enum Block: Equatable {
        case paragraph
        /// A heading, from level 1 for `#` to level 6 for `######`.
        case heading(level: Int)
        /// A list item starting with `-`, `*` or `+`.
        case bullet
        /// A list item starting with its number, such as "1." or "2)".
        case numbered(String)
    }

    /// Emphasis covering the whole of a line's words.
    enum Emphasis: Equatable {
        case bold
        case italic
    }

    /// One line read as Markdown: its layout, any emphasis over all of it, and its words
    /// without the symbols.
    struct Line: Equatable {
        let block: Block
        let emphasis: Emphasis?
        let text: String
    }

    /// Reads one line of text as Markdown.
    static func line(_ line: String) -> Line {
        let characters = Array(line)
        let syntax = syntax(of: characters)
        let symbols = Set(syntax.ranges.flatMap { $0 })
        let words = characters.indices.filter { !symbols.contains($0) }.map { characters[$0] }
        return Line(block: syntax.block, emphasis: syntax.emphasis, text: String(words).trimmingCharacters(in: .whitespaces))
    }

    /// The character offsets of every Markdown symbol in `text`, in order, leaving out
    /// anything inside a note.
    static func ranges(in text: String) -> [Range<Int>] {
        let characters = Array(Notes.masked(text))
        var ranges: [Range<Int>] = []
        var lineStart = 0
        while lineStart <= characters.count {
            let lineEnd = characters[lineStart...].firstIndex(where: \.isNewline) ?? characters.count
            let symbols = syntax(of: Array(characters[lineStart..<lineEnd])).ranges
            ranges += symbols.map { ($0.lowerBound + lineStart)..<($0.upperBound + lineStart) }
            lineStart = lineEnd + 1
        }
        return ranges
    }

    /// `text` with every Markdown symbol turned to a space, keeping its line breaks, so
    /// each word stays at the same offset as in the learner's text.
    static func masked(_ text: String) -> String {
        let symbols = ranges(in: text)
        guard !symbols.isEmpty else { return text }
        var characters = Array(text)
        for range in symbols {
            for index in range {
                characters[index] = " "
            }
        }
        return String(characters)
    }

    /// `translation` with the headings, list markers and whole-line emphasis of the lines
    /// it was translated from, line for line.
    ///
    /// Emphasis on a few words inside a line can't follow them, since translating moves
    /// words around, so only emphasis over a whole line carries over. When the translation
    /// doesn't have one line for each source line, it's returned untouched as plain text.
    static func restyled(_ translation: String, like lines: [Line]) -> String {
        let translated = translation.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard translated.count == lines.count,
              lines.contains(where: { $0.block != .paragraph || $0.emphasis != nil }) else { return translation }
        return zip(lines, translated).map { line, english in
            let words = english.trimmingCharacters(in: .whitespaces)
            guard !words.isEmpty else { return "" }
            let emphasized = switch line.emphasis {
            case .bold: "**\(words)**"
            case .italic: "*\(words)*"
            case nil: words
            }
            let marker = switch line.block {
            case .paragraph: ""
            case .heading(let level): String(repeating: "#", count: level) + " "
            case .bullet: "- "
            case .numbered(let number): number + " "
            }
            return marker + emphasized
        }.joined(separator: "\n")
    }

    // MARK: - Reading a line

    /// A pair of asterisk runs around emphasized words.
    private struct EmphasisPair {
        let open: Range<Int>
        let close: Range<Int>
        let kind: Emphasis
    }

    /// A line's layout, any emphasis over all of it, and the offsets of its symbols.
    private static func syntax(of characters: [Character]) -> (block: Block, emphasis: Emphasis?, ranges: [Range<Int>]) {
        let (block, marker) = blockMarker(in: characters)
        let contentStart = marker?.upperBound ?? 0
        let pairs = emphasisPairs(in: characters, from: contentStart)
        var ranges = marker.map { [$0] } ?? []
        for pair in pairs {
            ranges += [pair.open, pair.close]
        }
        // Emphasis covers the line when one pair runs from its first word to its last.
        var emphasis: Emphasis?
        if pairs.count == 1,
           let first = characters[contentStart...].firstIndex(where: { !$0.isWhitespace }),
           let last = characters.lastIndex(where: { !$0.isWhitespace }),
           pairs[0].open.lowerBound == first, pairs[0].close.upperBound == last + 1 {
            emphasis = pairs[0].kind
        }
        return (block, emphasis, ranges)
    }

    /// The line's layout and its marker with the space after it, such as "## " or "1. ",
    /// which may follow up to three spaces.
    private static func blockMarker(in characters: [Character]) -> (Block, Range<Int>?) {
        let lead = characters.prefix { $0 == " " }.count
        guard lead <= 3, lead < characters.count else { return (.paragraph, nil) }
        let rest = characters[lead...]

        let hashes = rest.prefix { $0 == "#" }.count
        if (1...6).contains(hashes), lead + hashes < characters.count, characters[lead + hashes] == " " {
            return (.heading(level: hashes), lead..<(lead + hashes + 1))
        }
        if "-*+".contains(characters[lead]), lead + 1 < characters.count, characters[lead + 1] == " " {
            return (.bullet, lead..<(lead + 2))
        }
        let digits = rest.prefix { $0.isASCII && $0.isNumber }.count
        let end = lead + digits
        if (1...9).contains(digits), end + 1 < characters.count, ".)".contains(characters[end]), characters[end + 1] == " " {
            return (.numbered(String(characters[lead...end])), lead..<(end + 2))
        }
        return (.paragraph, nil)
    }

    /// Each `*italic*` and `**bold**` pair from `start` on. An opening run sits before a
    /// word and a closing run after one, so neither touches a space on its inner side.
    private static func emphasisPairs(in characters: [Character], from start: Int) -> [EmphasisPair] {
        var pairs: [EmphasisPair] = []
        var index = start
        while index < characters.count {
            guard characters[index] == "*" else {
                index += 1
                continue
            }
            let width = characters[index...].prefix { $0 == "*" }.count
            if width <= 2, let close = closingRun(of: width, in: characters, after: index + width) {
                pairs.append(EmphasisPair(
                    open: index..<(index + width),
                    close: close..<(close + width),
                    kind: width == 2 ? .bold : .italic
                ))
                index = close + width
            } else {
                index += width
            }
        }
        return pairs
    }

    /// The offset of the run of `width` asterisks that closes emphasis whose words start
    /// at `start`, or `nil` when nothing closes it.
    private static func closingRun(of width: Int, in characters: [Character], after start: Int) -> Int? {
        guard start < characters.count, !characters[start].isWhitespace else { return nil }
        var probe = start + 1
        while probe < characters.count {
            guard characters[probe] == "*" else {
                probe += 1
                continue
            }
            let run = characters[probe...].prefix { $0 == "*" }.count
            if run == width, !characters[probe - 1].isWhitespace {
                return probe
            }
            probe += run
        }
        return nil
    }
}
