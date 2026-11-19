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
import SwiftUI
@testable import quiver_demo_coquille

/// Covers the `//: tableau` line that gives an entry its painting, in the text, the
/// journal list and the editor.
@MainActor
final class PaintingLineTests: XCTestCase {

    /// Reports no misspellings, so only the grammar rules can raise issues.
    private struct NoSpellChecker: SpellChecker {
        func misspellings(in text: String) -> [Misspelling] { [] }
    }

    /// Records nothing and says nothing, so tests stay silent.
    private final class SilentNarrator: Narrator {
        var voiceID = ""
        private(set) var state = PlaybackState.idle
        var spokenRange: Range<Int>?
        func speak(_ text: String) {}
        func pause() {}
        func resume() {}
        func stop() {}
    }

    /// Builds a model over the bundled French rules, with in-memory stats.
    private func makeModel() throws -> EditorModel {
        let pack = try LanguagePack.french()
        let linter = Linter(spellChecker: NoSpellChecker(), grammar: pack.grammar, lexicon: pack.lexicon, explanations: pack.explanations)
        return EditorModel(stats: StatsStore(fileURL: nil), narrator: SilentNarrator(), phraseNarrator: SilentNarrator(), linter: linter)
    }

    /// Replaces the text as typing would and puts the caret at its end.
    private func type(_ text: String, into model: EditorModel) {
        model.text = AttributedString(text)
        model.selection = AttributedTextSelection(insertionPoint: model.text.endIndex)
        model.textDidChange()
    }

    /// The color of the character at `offset` in the model's text.
    private func color(at offset: Int, in model: EditorModel) -> Color? {
        let index = model.text.characters.index(model.text.startIndex, offsetBy: offset)
        return model.text[index..<model.text.characters.index(after: index)].foregroundColor
    }

    /// A painting from the bundled collection.
    private func painting(_ id: String) throws -> Tableau {
        try XCTUnwrap(TableauCatalog.tableau(withID: id))
    }

    // MARK: - Finding the line

    /// The line names its painting by title, on the first line or any other.
    func testFindsTheLineAnywhere() throws {
        XCTAssertEqual(PaintingLine.tableau(in: "//: tableau Les voiliers\nJe nage."), try painting("les-voiliers"))
        XCTAssertEqual(PaintingLine.tableau(in: "Je nage.\n\n  //: tableau Les voiliers\nIl fait beau."), try painting("les-voiliers"))
    }

    /// Capitals, accents, the apostrophe and extra spaces don't matter, in the title or the keyword.
    func testMatchingIsForgiving() throws {
        let nympheas = try painting("les-nympheas")
        XCTAssertEqual(PaintingLine.tableau(in: "//: tableau les nympheas"), nympheas)
        XCTAssertEqual(PaintingLine.tableau(in: "//:tableau   Les   Nymphéas  "), nympheas)
        XCTAssertEqual(PaintingLine.tableau(in: "//: Tableau LES NYMPHÉAS"), nympheas)
        XCTAssertEqual(TableauCatalog.matchKey("L’été"), TableauCatalog.matchKey("l'ete"))
    }

    /// A typo, an empty title or a near-miss keyword names no painting.
    func testUnknownTitlesNameNoPainting() {
        XCTAssertNil(PaintingLine.tableau(in: "//: tableau Le prac"))
        XCTAssertNil(PaintingLine.tableau(in: "//: tableau"))
        XCTAssertNil(PaintingLine.tableau(in: "//: tableaux Les voiliers"))
        XCTAssertNil(PaintingLine.first(in: "//: tableaux Les voiliers"))
    }

    /// Only a review marker counts: not a plain note, a block note, or a marker after French.
    func testOnlyAMarkerOnItsOwnLineCounts() {
        XCTAssertNil(PaintingLine.first(in: "// tableau Les voiliers"))
        XCTAssertNil(PaintingLine.first(in: "/* //: tableau Les voiliers */"))
        XCTAssertNil(PaintingLine.first(in: "/*\n//: tableau Les voiliers\n*/"))
        XCTAssertNil(PaintingLine.first(in: "Je nage. //: tableau Les voiliers"))
    }

    /// The first painting line counts, even when its title is unknown.
    func testFirstLineWins() throws {
        XCTAssertEqual(PaintingLine.tableau(in: "//: tableau Le bouquet\n//: tableau Les voiliers"), try painting("le-bouquet"))
        XCTAssertNil(PaintingLine.tableau(in: "//: tableau Le prac\n//: tableau Les voiliers"))
    }

    /// Lines that show no painting are the ones after the first, and the first when unknown.
    func testInactiveLines() {
        XCTAssertEqual(PaintingLine.inactiveRanges(in: "//: tableau Le bouquet\n//: tableau Au café"), [23..<42])
        XCTAssertEqual(PaintingLine.inactiveRanges(in: "//: tableau Le prac"), [0..<19])
        XCTAssertEqual(PaintingLine.inactiveRanges(in: "//: check\nBonjour."), [])
    }

    /// The checker, Play and the postcard skip the line like any note.
    func testTheLineIsANote() {
        XCTAssertEqual(Notes.removed("//: tableau Le bouquet\nBonjour."), "Bonjour.")
    }

    // MARK: - Changing the line

    /// Adding puts the line at the top.
    func testAddingPutsTheLineAtTheTop() throws {
        XCTAssertEqual(PaintingLine.setting(try painting("le-bouquet"), in: "Bonjour."), "//: tableau Le bouquet\nBonjour.")
        XCTAssertEqual(PaintingLine.setting(try painting("le-bouquet"), in: ""), "//: tableau Le bouquet\n")
    }

    /// Replacing rewrites the first line where it is, fixing an unknown title too.
    func testReplacingKeepsThePlace() throws {
        let bouquet = try painting("le-bouquet")
        XCTAssertEqual(PaintingLine.setting(bouquet, in: "Salut.\n//: tableau Au café\nBonjour."), "Salut.\n//: tableau Le bouquet\nBonjour.")
        XCTAssertEqual(PaintingLine.setting(bouquet, in: "//: tableau Le prac\nBonjour."), "//: tableau Le bouquet\nBonjour.")
        XCTAssertNil(PaintingLine.edit(setting: bouquet, in: "//: tableau Le bouquet\nBonjour."))
    }

    /// Removing takes out the first line and its line break, and leaves the others.
    func testRemovingTakesOutTheWholeLine() {
        XCTAssertEqual(PaintingLine.setting(nil, in: "//: tableau Au café\nBonjour."), "Bonjour.")
        XCTAssertEqual(PaintingLine.setting(nil, in: "Salut.\n  //: tableau Au café\nBonjour."), "Salut.\nBonjour.")
        XCTAssertEqual(PaintingLine.setting(nil, in: "Bonjour.\n//: tableau Au café"), "Bonjour.")
        XCTAssertEqual(PaintingLine.setting(nil, in: "//: tableau Au café\n//: tableau Le bouquet"), "//: tableau Le bouquet")
        XCTAssertNil(PaintingLine.edit(setting: nil, in: "Bonjour."))
    }

    // MARK: - The journal and the editor

    /// A listed entry reads its painting from its text.
    func testJournalEntryReadsItsPainting() throws {
        let entry = Journal.Entry(url: URL(filePath: "/tmp/2026-11-18.txt"), date: .now, modified: .now,
                                  title: nil, text: "//: tableau Au café\nUn café, s'il vous plaît.")
        XCTAssertEqual(entry.tableau, try painting("au-cafe"))
        XCTAssertEqual(entry.preview, "Un café, s'il vous plaît.")
    }

    /// Choosing a painting edits the text, so it counts as unsaved, and removing it undoes that.
    func testSettingThePaintingIsAnEdit() throws {
        let model = try makeModel()
        type("Bonjour.", into: model)
        let wasEdited = model.isEdited
        model.setTableau(try painting("le-bouquet"))
        XCTAssertEqual(model.plainText, "//: tableau Le bouquet\nBonjour.")
        XCTAssertEqual(model.tableau, try painting("le-bouquet"))
        XCTAssertTrue(model.isEdited)

        model.setTableau(nil)
        XCTAssertEqual(model.plainText, "Bonjour.")
        XCTAssertNil(model.tableau)
        XCTAssertEqual(model.isEdited, wasEdited)
    }

    /// A matching line takes the marker color, and an unknown one stays note grey.
    func testOnlyAMatchingLineTakesTheMarkerColor() throws {
        let model = try makeModel()
        type("//: tableau Le bouquet\n//: tableau Le prac", into: model)
        XCTAssertEqual(color(at: 0, in: model), Color.brand)
        XCTAssertEqual(color(at: 23, in: model), Color.secondary)
    }
}
