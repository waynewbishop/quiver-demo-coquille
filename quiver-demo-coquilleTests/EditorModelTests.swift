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

@MainActor
final class EditorModelTests: XCTestCase {

    /// Records what it was asked to say instead of speaking.
    private final class FakeNarrator: Narrator {
        private(set) var state = PlaybackState.idle
        var spokenRange: Range<Int>?
        private(set) var spoken: [String] = []

        func speak(_ text: String, rate: Float) {
            spoken.append(text)
            state = .speaking
        }
        func pause() { state = .paused }
        func resume() { state = .speaking }
        func stop() {
            state = .idle
            spokenRange = nil
        }
    }

    /// Reports no misspellings, so only the grammar rules run.
    private struct SilentSpellChecker: SpellChecker {
        func misspellings(in text: String) -> [Misspelling] { [] }
    }

    private var narrator = FakeNarrator()

    /// Builds a model over the bundled French rules, with in-memory stats.
    private func makeModel() throws -> EditorModel {
        let pack = try LanguagePack.french()
        let linter = Linter(spellChecker: SilentSpellChecker(), grammar: pack.grammar, lexicon: pack.lexicon, explanations: pack.explanations)
        narrator = FakeNarrator()
        return EditorModel(stats: StatsStore(fileURL: nil), narrator: narrator, linter: linter)
    }

    /// Replaces the text as typing would, leaving the debounced lint pending.
    private func type(_ text: String, into model: EditorModel) {
        model.text = AttributedString(text)
        model.textDidChange()
    }

    // An error typed just before play is caught before anything is spoken.
    func testPlayChecksTextTypedSinceTheLastLint() throws {
        let model = try makeModel()
        type("Nous avons un fromage.", into: model)
        model.lintNow()
        XCTAssertFalse(model.isLocked)

        type("Nous avons une fromage.", into: model)
        XCTAssertFalse(model.isLintCurrent)
        model.togglePlay()

        XCTAssertTrue(model.isLintCurrent)
        XCTAssertTrue(model.isLocked)
        XCTAssertEqual(narrator.spoken, [])
    }

    // A fix typed just before play unlocks it without waiting for the debounce.
    func testPlayAcceptsAFixTypedSinceTheLastLint() throws {
        let model = try makeModel()
        type("Nous avons une fromage.", into: model)
        model.lintNow()
        XCTAssertTrue(model.isLocked)

        type("Nous avons un fromage.", into: model)
        model.togglePlay()

        XCTAssertEqual(narrator.spoken, ["Nous avons un fromage."])
    }

    // Pressing play again pauses, and again resumes, rather than starting over.
    func testPlayPausesAndResumes() throws {
        let model = try makeModel()
        type("Nous avons un fromage.", into: model)
        model.lintNow()

        model.togglePlay()
        model.togglePlay()
        XCTAssertEqual(narrator.state, .paused)
        model.togglePlay()
        XCTAssertEqual(narrator.state, .speaking)
        XCTAssertEqual(narrator.spoken.count, 1)
    }

    /// The words in the text that carry a background color.
    private func highlightedWords(in model: EditorModel) -> [String] {
        model.text.runs.compactMap { run in
            run.backgroundColor == nil ? nil : String(model.text[run.range].characters)
        }
    }

    // The word being read aloud is highlighted, stays lit while paused, and clears on stop.
    func testSpokenWordIsHighlighted() throws {
        let model = try makeModel()
        type("Un café crème.", into: model)
        model.lintNow()
        model.togglePlay()

        // "crème" starts at UTF-16 offset 8, after "Un café ", where é is one unit.
        narrator.spokenRange = 8..<13
        model.spokenWordDidChange()
        XCTAssertEqual(highlightedWords(in: model), ["crème"])

        model.togglePlay()
        model.spokenWordDidChange()
        XCTAssertEqual(highlightedWords(in: model), ["crème"])

        model.clear()
        XCTAssertEqual(highlightedWords(in: model), [])
    }

    // Try an example starts over: an issue ignored during a rehearsal comes back.
    func testExampleResetsIgnoredIssues() throws {
        let model = try makeModel()
        model.loadExample()
        let first = try XCTUnwrap(model.blockingIssues.first)
        let count = model.visibleIssues.count

        model.ignore(first)
        XCTAssertEqual(model.visibleIssues.count, count - 1)

        model.loadExample()
        XCTAssertEqual(model.visibleIssues.count, count)
        XCTAssertEqual(model.selectedIssue?.id, first.id)
        XCTAssertEqual(narrator.state, .idle)
    }
}
