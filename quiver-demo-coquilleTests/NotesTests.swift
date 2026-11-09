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

import XCTest
@testable import quiver_demo_coquille

/// Covers finding the learner's notes, blanking them for the checker, and taking them
/// out for translation.
@MainActor
final class NotesTests: XCTestCase {

    /// Reports no misspellings, so only the grammar rules can raise issues.
    private struct NoSpellChecker: SpellChecker {
        func misspellings(in text: String) -> [Misspelling] { [] }
    }

    /// Builds a linter over the bundled pack that never reports misspellings.
    private func linter() throws -> Linter {
        let pack = try LanguagePack.french()
        return Linter(
            spellChecker: NoSpellChecker(),
            grammar: pack.grammar,
            lexicon: pack.lexicon,
            explanations: pack.explanations
        )
    }

    // MARK: - Finding notes

    /// A line note runs from its slashes to the end of the line, not past it.
    func testLineNoteEndsAtLineBreak() {
        let text = "le fromage // cheese\nla pomme"
        XCTAssertEqual(Notes.ranges(in: text), [11..<20])
    }

    /// A line note on the last line runs to the end of the text.
    func testLineNoteAtEndOfText() {
        XCTAssertEqual(Notes.ranges(in: "// Vocabulary"), [0..<13])
    }

    /// Return is recognized only at the end of the line that opens an unclosed block note.
    func testLineBreakOpeningBlockNote() {
        XCTAssertEqual(Notes.lineBreakOpeningBlockNote(from: "/* note", to: "/* note\n")?.lineBreak, 7)
        XCTAssertEqual(Notes.lineBreakOpeningBlockNote(from: "/* note", to: "/* note\n")?.asteriskColumn, 1)
        XCTAssertEqual(Notes.lineBreakOpeningBlockNote(from: "/* a\nBonjour", to: "/* a\n\nBonjour")?.lineBreak, 4)
        XCTAssertEqual(Notes.lineBreakOpeningBlockNote(from: "Je /* a", to: "Je /* a\n")?.asteriskColumn, 4)
        XCTAssertEqual(Notes.lineBreakOpeningBlockNote(from: "Salut\n/* a", to: "Salut\n/* a\n")?.asteriskColumn, 1)
        XCTAssertNil(Notes.lineBreakOpeningBlockNote(from: "/* a*/", to: "/* a\n*/"))
        XCTAssertNil(Notes.lineBreakOpeningBlockNote(from: "// a", to: "// a\n"))
        XCTAssertNil(Notes.lineBreakOpeningBlockNote(from: "/* a\nb", to: "/* a\nb\n"))
        XCTAssertNil(Notes.lineBreakOpeningBlockNote(from: "/* ab", to: "/* a\nb"))
        XCTAssertNil(Notes.lineBreakOpeningBlockNote(from: "/* a", to: "/* ab"))
    }

    /// A block note can sit between words and spans its markers.
    func testBlockNoteBetweenWords() {
        let text = "Je /* I */ mange."
        XCTAssertEqual(Notes.ranges(in: text), [3..<10])
    }

    /// A block note can run across lines.
    func testBlockNoteAcrossLines() {
        let text = "/* one\ntwo */Bonjour"
        XCTAssertEqual(Notes.ranges(in: text), [0..<13])
    }

    /// A block note with no closing marker runs to the end, never raising an error.
    func testUnclosedBlockNoteRunsToEnd() {
        let text = "Bonjour. /* still writing"
        XCTAssertEqual(Notes.ranges(in: text), [9..<25])
    }

    /// The slash that opens a block note can't also close it.
    func testOpeningSlashDoesNotCloseBlock() {
        XCTAssertEqual(Notes.ranges(in: "/*/ x"), [0..<5])
    }

    /// Inside a line note, a block opener means nothing, and the next line is French again.
    func testBlockOpenerInsideLineNoteIsIgnored() {
        let text = "// see /* here\nBonjour"
        XCTAssertEqual(Notes.ranges(in: text), [0..<14])
    }

    /// Inside a block note, slashes mean nothing until the block closes.
    func testLineOpenerInsideBlockNoteIsIgnored() {
        let text = "/* a // b */ Bonjour"
        XCTAssertEqual(Notes.ranges(in: text), [0..<12])
    }

    /// A single slash, as in a date or "et/ou", is French, not a note.
    func testSingleSlashIsNotANote() {
        XCTAssertEqual(Notes.ranges(in: "et/ou le 2/11"), [])
    }

    // MARK: - Masking and removing

    /// Masking keeps the text's length and line breaks, so offsets still line up.
    func testMaskedKeepsOffsetsAndLineBreaks() {
        let text = "Je mange. // I eat\n/* a\nb */ Tu bois."
        let masked = Notes.masked(text)
        XCTAssertEqual(masked.count, text.count)
        // "// I eat" is 8 characters, "/* a" is 4, and "b */" is 4 before the space.
        let expected = "Je mange. " + String(repeating: " ", count: 8) + "\n"
            + String(repeating: " ", count: 4) + "\n"
            + String(repeating: " ", count: 4) + " Tu bois."
        XCTAssertEqual(masked, expected)
    }

    /// Removing drops lines that were only notes, keeps blank lines, and closes up spaces.
    func testRemovedForTranslation() {
        let text = "// Monday\nJe /* I */ mange.\n\nTu bois. // you drink"
        XCTAssertEqual(Notes.removed(text), "Je mange.\n\nTu bois.")
    }

    /// Text with no notes comes back unchanged.
    func testTextWithoutNotesIsUnchanged() {
        let text = "Je  mange.\n\n"
        XCTAssertEqual(Notes.masked(text), text)
        XCTAssertEqual(Notes.removed(text), text)
    }

    // MARK: - Checking

    /// An error the checker catches in French goes unflagged inside a note, and the
    /// French around the note is still checked at the right offsets.
    func testCheckerSkipsNotes() throws {
        let linter = try linter()
        let error = "Je suis faim."
        let flagged = linter.lint(error)
        XCTAssertFalse(flagged.isEmpty, "The word-choice rule should flag \"\(error)\" as French.")

        let note = "// " + error
        XCTAssertTrue(linter.lint(note).isEmpty)

        let both = note + "\n" + error
        let offset = note.count + 1
        let shifted = linter.lint(both)
        XCTAssertEqual(shifted.map(\.range), flagged.map { ($0.range.lowerBound + offset)..<($0.range.upperBound + offset) })
    }
}
