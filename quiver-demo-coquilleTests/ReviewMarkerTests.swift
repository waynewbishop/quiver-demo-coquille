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

/// Covers finding review markers and completing them in the editor.
@MainActor
final class ReviewMarkerTests: XCTestCase {

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

    // MARK: - Finding markers

    /// A marker starts its line, though spaces may come before it.
    func testMarkerStartsItsLine() {
        XCTAssertEqual(Notes.markerRanges(in: "//: check\nBonjour."), [0..<9])
        XCTAssertEqual(Notes.markerRanges(in: "Salut.\n  //: ok"), [9..<15])
    }

    /// Plain notes, block notes and a `//:` after French aren't markers.
    func testOtherNotesAreNotMarkers() {
        XCTAssertEqual(Notes.markerRanges(in: "// check"), [])
        XCTAssertEqual(Notes.markerRanges(in: "/*: check */"), [])
        XCTAssertEqual(Notes.markerRanges(in: "/* //: check */"), [])
        XCTAssertEqual(Notes.markerRanges(in: "Je vais. //: check"), [])
    }

    /// The checker skips a marker, as it skips any note.
    func testCheckerIgnoresMarkers() {
        XCTAssertEqual(Notes.masked("//: ok\nBonjour."), "      \nBonjour.")
    }

    // MARK: - Completing markers

    /// Every keyword is offered after `//:`, narrowing as the keyword is typed.
    func testKeywordsNarrowAsTyped() {
        XCTAssertEqual(Notes.markerBeingCompleted(at: 3, in: "//:")?.keywords, Notes.markerKeywords)
        XCTAssertEqual(Notes.markerBeingCompleted(at: 6, in: "//: ch")?.keywords, ["check"])
    }

    /// Nothing is offered once the keyword is whole, past it, or away from the marker's end.
    func testNoKeywordsOnceChosen() {
        XCTAssertNil(Notes.markerBeingCompleted(at: 9, in: "//: check"))
        XCTAssertNil(Notes.markerBeingCompleted(at: 10, in: "//: check "))
        XCTAssertNil(Notes.markerBeingCompleted(at: 6, in: "//: zz"))
        XCTAssertNil(Notes.markerBeingCompleted(at: 1, in: "//:"))
    }

    /// Choosing a keyword finishes the marker and leaves room for a topic where one can follow.
    func testCompletingMarkerReplacesWhatWasTyped() throws {
        let model = try makeModel()
        type("Salut.\n//: ch", into: model)
        XCTAssertEqual(model.offeredMarkerKeywords, ["check"])

        model.completeMarker(with: "check")
        XCTAssertEqual(model.plainText, "Salut.\n//: check ")
        XCTAssertEqual(model.offeredMarkerKeywords, [])
    }

    /// A keyword nothing can follow gets no trailing space.
    func testCompletingMarkerWithoutTopic() throws {
        let model = try makeModel()
        type("//:", into: model)
        model.completeMarker(with: "natural")
        XCTAssertEqual(model.plainText, "//: natural")
    }
}
