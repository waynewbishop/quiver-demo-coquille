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

/// Covers finding quoted text, blanking it for the checker, and warning about a quote
/// that never closes.
@MainActor
final class QuotesTests: XCTestCase {

    /// Reports "Joe" wherever it appears in the text it is given, so a test can tell
    /// whether the checker was shown the quoted name.
    private struct NameSpellChecker: SpellChecker {
        func misspellings(in text: String) -> [Misspelling] {
            let characters = Array(text)
            let name = Array("Joe")
            return characters.indices.compactMap { index in
                index + name.count <= characters.count && Array(characters[index..<(index + name.count)]) == name
                    ? Misspelling(offset: index, word: "Joe", guesses: [])
                    : nil
            }
        }
    }

    /// Builds a linter over the bundled pack with the name-reporting spellchecker.
    private func linter() throws -> Linter {
        let pack = try LanguagePack.french()
        return Linter(
            spellChecker: NameSpellChecker(),
            grammar: pack.grammar,
            lexicon: pack.lexicon,
            explanations: pack.explanations
        )
    }

    // MARK: - Finding quotes

    // Straight quotes, curly quotes and guillemets each hold what sits between them.
    func testEveryQuoteStyleIsFound() {
        XCTAssertEqual(Quotes.ranges(in: "a \"bc\" d"), [3..<5])
        XCTAssertEqual(Quotes.ranges(in: "a “bc” d"), [3..<5])
        XCTAssertEqual(Quotes.ranges(in: "a « bc » d"), [4..<8])
    }

    // An apostrophe never ends a quote, so the name stays whole.
    func testApostropheDoesNotEndQuote() {
        let text = "chez \"Trader Joe's\"."
        XCTAssertEqual(Quotes.ranges(in: text), [6..<18])
    }

    // Two quotes on one line are separate spans.
    func testTwoQuotesOnOneLine() {
        XCTAssertEqual(Quotes.ranges(in: "\"a\" et \"b\"").count, 2)
    }

    // Masking keeps every offset and every line break.
    func testMaskingKeepsOffsets() {
        let text = "Je suis chez \"Trader Joe's\".\nBonjour"
        let masked = Quotes.masked(text)
        XCTAssertEqual(masked.count, text.count)
        XCTAssertEqual(masked, "Je suis chez \"              \".\nBonjour")
    }

    // MARK: - Linting

    // A quoted name is never shown to the checker.
    func testQuotedNameRaisesNothing() throws {
        let linter = try linter()
        XCTAssertTrue(linter.lint("Je suis garé à \"Trader Joe's\".").isEmpty)
        XCTAssertTrue(linter.lint("Je suis garé chez « Trader Joe's ».").isEmpty)
    }

    // The same name outside quotes is still checked.
    func testUnquotedNameIsStillChecked() throws {
        let issues = try linter().lint("Je suis garé chez Trader Joe's.")
        XCTAssertTrue(issues.contains { $0.original == "Joe" })
    }

    // The French around a quote is still checked.
    func testFrenchAroundQuoteIsStillChecked() throws {
        let issues = try linter().lint("Je suis gare chez \"Trader Joe's\".")
        XCTAssertFalse(issues.isEmpty)
        XCTAssertTrue(issues.allSatisfy { $0.original.lowercased() == "gare" })
    }

    // MARK: - Unclosed quotes

    // A quote with no closing mark is a warning at its opening mark, never an error.
    func testUnclosedQuoteWarnsAtOpeningMark() throws {
        let text = "Je suis allé à \"Trader Joe's."
        let issues = try linter().lint(text)
        let warning = try XCTUnwrap(issues.first { $0.kind == .quotation })
        XCTAssertEqual(warning.severity, .warning)
        XCTAssertEqual(warning.offset, 15)
        XCTAssertEqual(warning.length, 1)
        XCTAssertFalse(warning.severity.blocksPlayback)
        XCTAssertFalse(issues.contains { $0.original == "Joe" })
    }

    // An unclosed quote only silences the rest of its own line.
    func testUnclosedQuoteStopsAtLineEnd() throws {
        let issues = try linter().lint("Je suis allé à \"Trader Joe's.\nChez Joe.")
        XCTAssertTrue(issues.contains { $0.kind == .spelling || $0.original == "Joe" })
        XCTAssertEqual(Quotes.unclosed(in: "a \"b\nc"), [2])
    }
}
