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

@MainActor
final class MarkdownTests: XCTestCase {

    // MARK: - Reading lines

    // Each heading level, bullet and numbered marker is read, with the words left alone.
    func testBlocks() {
        XCTAssertEqual(Markdown.line("# Mon week-end"), .init(block: .heading(level: 1), emphasis: nil, text: "Mon week-end"))
        XCTAssertEqual(Markdown.line("### Le soir"), .init(block: .heading(level: 3), emphasis: nil, text: "Le soir"))
        XCTAssertEqual(Markdown.line("- du pain"), .init(block: .bullet, emphasis: nil, text: "du pain"))
        XCTAssertEqual(Markdown.line("* du lait"), .init(block: .bullet, emphasis: nil, text: "du lait"))
        XCTAssertEqual(Markdown.line("+ du café"), .init(block: .bullet, emphasis: nil, text: "du café"))
        XCTAssertEqual(Markdown.line("2. Je mange."), .init(block: .numbered("2."), emphasis: nil, text: "Je mange."))
        XCTAssertEqual(Markdown.line("3) Je dors."), .init(block: .numbered("3)"), emphasis: nil, text: "Je dors."))
    }

    // Text that only looks like Markdown stays a plain paragraph.
    func testLookalikesArePlain() {
        for line in ["#hashtag", "-5 degrés ce matin.", "2026 était une bonne année.", "    - trop loin", "Il est 9.30 h."] {
            XCTAssertEqual(Markdown.line(line).block, .paragraph, line)
            XCTAssertEqual(Markdown.line(line).text, line.trimmingCharacters(in: .whitespaces), line)
        }
    }

    // Emphasis over a whole line is kept; emphasis on a few words only loses its symbols.
    func testEmphasis() {
        XCTAssertEqual(Markdown.line("**Lundi 9 novembre**"), .init(block: .paragraph, emphasis: .bold, text: "Lundi 9 novembre"))
        XCTAssertEqual(Markdown.line("- *Il pleut.*"), .init(block: .bullet, emphasis: .italic, text: "Il pleut."))
        XCTAssertEqual(Markdown.line("Il fait *très* beau."), .init(block: .paragraph, emphasis: nil, text: "Il fait très beau."))
        XCTAssertEqual(Markdown.line("**Il** fait **beau**"), .init(block: .paragraph, emphasis: nil, text: "Il fait beau"))
    }

    // Asterisks with a space on their inner side, or with nothing to close them, are plain text.
    func testUnmatchedAsterisksArePlain() {
        XCTAssertEqual(Markdown.line("5 * 3 = 15").text, "5 * 3 = 15")
        XCTAssertEqual(Markdown.line("Un *seul astérisque").text, "Un *seul astérisque")
        XCTAssertEqual(Markdown.line("** pas gras **").text, "** pas gras **")
    }

    // MARK: - Masking

    // Masking turns each symbol to a space, so every word keeps its offset.
    func testMaskingKeepsOffsets() {
        let text = "# Titre\n- **Bonjour** !"
        let masked = Markdown.masked(text)
        XCTAssertEqual(masked, "  Titre\n    Bonjour   !")
        XCTAssertEqual(masked.count, text.count)
    }

    // Markdown inside a note belongs to the note, so it isn't read as Markdown.
    func testNotesHideMarkdown() {
        XCTAssertTrue(Markdown.ranges(in: "Il pleut. // **pas du gras**").isEmpty)
        XCTAssertEqual(Markdown.ranges(in: "**Il pleut.** // # note"), [0..<2, 11..<13])
    }

    // MARK: - Restyling translations

    // Headings, list markers and whole-line emphasis return on the matching English lines.
    func testRestyledFollowsTheSourceLines() {
        let lines = ["# Mon week-end", "", "**Lundi 9 novembre**", "- Il fait *très* beau.", "1. Je mange."].map(Markdown.line)
        let english = "My weekend\n\nMonday, November 9\nThe weather is very nice.\nI eat."
        XCTAssertEqual(
            Markdown.restyled(english, like: lines),
            "# My weekend\n\n**Monday, November 9**\n- The weather is very nice.\n1. I eat."
        )
    }

    // A translation whose lines don't match the source comes back as it was, as plain text.
    func testRestyledLeavesMismatchedLinesAlone() {
        let lines = ["# Titre", "Il pleut."].map(Markdown.line)
        XCTAssertEqual(Markdown.restyled("Title. It's raining.", like: lines), "Title. It's raining.")
    }

    // MARK: - Editor

    /// Reports no misspellings, so the test checks grammar alone.
    private struct SilentSpellChecker: SpellChecker {
        func misspellings(in text: String) -> [Misspelling] { [] }
    }

    /// Translates line for line from a fixed list, and keeps what it was asked to translate.
    private final class LineTranslator: Translator {
        let english: [String: String]
        private(set) var sources: [String] = []

        init(english: [String: String]) {
            self.english = english
        }

        /// Returns each line's English, or the line itself when it isn't in the list.
        func translate(_ text: String) async throws -> String {
            sources.append(text)
            return text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { english[String($0)] ?? String($0) }
                .joined(separator: "\n")
        }
    }

    // The translator never sees the symbols, and the English pane gets the formatting back.
    func testEnglishKeepsTheFormatting() async throws {
        let translator = LineTranslator(english: ["Lundi 9 novembre": "Monday, November 9", "Il pleut.": "It's raining."])
        let pack = try LanguagePack.french()
        let linter = Linter(spellChecker: SilentSpellChecker(), grammar: pack.grammar, lexicon: pack.lexicon, explanations: pack.explanations)
        let model = EditorModel(stats: StatsStore(fileURL: nil), journal: nil, linter: linter, translator: translator)
        model.text = AttributedString("**Lundi 9 novembre**\n\n- Il pleut.")
        model.textDidChange()
        model.lintNow()
        XCTAssertFalse(model.isLocked, "The French should be clean: \(model.blockingIssues.map(\.original))")

        model.isEnglishOn = true
        for _ in 0..<200 {
            guard case .translating = model.english else { break }
            await Task.yield()
        }
        XCTAssertEqual(translator.sources.last, "Lundi 9 novembre\n\nIl pleut.")
        guard case .translated(let english) = model.english else {
            return XCTFail("Expected English, got \(model.english)")
        }
        XCTAssertEqual(english, "**Monday, November 9**\n\n- It's raining.")
    }
}
