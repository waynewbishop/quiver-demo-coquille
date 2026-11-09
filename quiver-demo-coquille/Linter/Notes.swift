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

/// The learner's notes, written with the same syntax as Swift comments, which the
/// checker skips just as a compiler skips comments.
///
/// `//` makes a note of the rest of its line, and `/*` starts a note that runs to the
/// next `*/`, across lines if need be. A note can sit on a line of its own, beside the
/// French, or between words, and hold any language. Inside a note, the other syntax
/// means nothing: a `/*` after `//` starts nothing, and so does a `//` inside `/* */`.
/// Unlike Swift, a `/*` with no `*/` is never an error; the note runs to the end.
/// Notes don't nest.
enum Notes {

    /// The character offsets of every note in `text`, in order, each including its markers.
    static func ranges(in text: String) -> [Range<Int>] {
        let characters = Array(text)
        var ranges: [Range<Int>] = []
        var index = 0
        while index + 1 < characters.count {
            guard characters[index] == "/" else {
                index += 1
                continue
            }
            switch characters[index + 1] {
            case "/":
                let end = characters[index...].firstIndex(where: \.isNewline) ?? characters.count
                ranges.append(index..<end)
                index = end
            case "*":
                let end = blockEnd(in: characters, from: index + 2)
                ranges.append(index..<end)
                index = end
            default:
                index += 1
            }
        }
        return ranges
    }

    /// `text` with every note's characters turned to spaces, keeping its line breaks, so
    /// each character of French stays at the same offset as in the learner's text.
    static func masked(_ text: String) -> String {
        let noteRanges = ranges(in: text)
        guard !noteRanges.isEmpty else { return text }
        var characters = Array(text)
        for range in noteRanges {
            for index in range where !characters[index].isNewline {
                characters[index] = " "
            }
        }
        return String(characters)
    }

    /// `text` with its notes taken out, for translating: a line that held only a note
    /// is dropped, and the spaces a note leaves behind close up.
    static func removed(_ text: String) -> String {
        guard !ranges(in: text).isEmpty else { return text }
        let originalLines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let maskedLines = masked(text).split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var kept: [String] = []
        for (original, line) in zip(originalLines, maskedLines) {
            let words = line.split(whereSeparator: \.isWhitespace)
            // A line that was only a note goes; a line the learner left blank stays.
            if words.isEmpty && !original.allSatisfy(\.isWhitespace) { continue }
            kept.append(words.joined(separator: " "))
        }
        return kept.joined(separator: "\n")
    }

    /// The offset of the line break that `new` added to `old`, and the column of the
    /// opening `*`, when it ends the line that opens a block note with no `*/`, and
    /// nothing follows on that line.
    static func lineBreakOpeningBlockNote(from old: String, to new: String) -> (lineBreak: Int, asteriskColumn: Int)? {
        let characters = Array(new)
        guard characters.count == old.count + 1 else { return nil }
        var lineBreak = zip(new, old).prefix(while: { $0 == $1 }).count
        guard characters[lineBreak].isNewline else { return nil }
        // Beside another line break the difference lands on the later one, so step back to the first.
        while lineBreak > 0, characters[lineBreak - 1].isNewline {
            lineBreak -= 1
        }
        guard lineBreak + 1 == characters.count || characters[lineBreak + 1].isNewline,
              let note = ranges(in: new).first(where: { $0.contains(lineBreak) }),
              characters[note.lowerBound + 1] == "*",
              !characters[note.lowerBound..<lineBreak].contains(where: \.isNewline) else {
            return nil
        }
        let isClosed = note.count >= 4 && characters[note.upperBound - 2] == "*" && characters[note.upperBound - 1] == "/"
        guard !isClosed else { return nil }
        let lineStart = characters[..<note.lowerBound].lastIndex(where: \.isNewline).map { $0 + 1 } ?? 0
        return (lineBreak, note.lowerBound + 1 - lineStart)
    }

    /// The offset just past the `*/` that closes a note whose text starts at `start`, or
    /// the end of the text when nothing closes it.
    private static func blockEnd(in characters: [Character], from start: Int) -> Int {
        var probe = start
        while probe + 1 < characters.count {
            if characters[probe] == "*" && characters[probe + 1] == "/" {
                return probe + 2
            }
            probe += 1
        }
        return characters.count
    }
}
