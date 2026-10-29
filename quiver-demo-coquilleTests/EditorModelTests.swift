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

        func speak(_ text: String) {
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

    /// Reports every occurrence of the given words as misspelled, with no guesses.
    private struct UnknownWordSpellChecker: SpellChecker {
        let unknown: Set<String>
        func misspellings(in text: String) -> [Misspelling] {
            FrenchTokenizer.tokens(in: text)
                .filter { unknown.contains($0.text) }
                .map { Misspelling(offset: $0.offset, word: $0.text, guesses: []) }
        }
    }

    private var narrator = FakeNarrator()
    private var phraseNarrator = FakeNarrator()

    /// Builds a model over the bundled French rules, with in-memory stats.
    private func makeModel(spellChecker: any SpellChecker = SilentSpellChecker()) throws -> EditorModel {
        let pack = try LanguagePack.french()
        let linter = Linter(spellChecker: spellChecker, grammar: pack.grammar, lexicon: pack.lexicon, explanations: pack.explanations)
        narrator = FakeNarrator()
        phraseNarrator = FakeNarrator()
        return EditorModel(stats: StatsStore(fileURL: nil), narrator: narrator, phraseNarrator: phraseNarrator, linter: linter)
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

    // Stop ends playback, so the next play reads the French again from the top.
    func testStopStartsOverOnNextPlay() throws {
        let model = try makeModel()
        type("Nous avons un fromage.", into: model)
        model.lintNow()

        model.togglePlay()
        model.togglePlay()
        model.stopPlaying()
        XCTAssertEqual(narrator.state, .idle)
        model.togglePlay()
        XCTAssertEqual(narrator.spoken.count, 2)
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

    // Try an example's mistakes aren't the learner's: fixing them counts nothing until the editor is cleared.
    func testExampleIsNotCounted() throws {
        let model = try makeModel()
        model.loadExample()
        let issue = try XCTUnwrap(model.blockingIssues.first)
        model.apply(issue)
        XCTAssertEqual(model.stats.stats.errorsFixed, 0)
        XCTAssertEqual(model.stats.stats.sentencesChecked, 0)

        model.clear()
        type("Nous avons une fromage.", into: model)
        model.lintNow()
        XCTAssertEqual(model.stats.stats.sentencesChecked, 1)
    }

    // Selecting the whole example and typing over it ends the rehearsal without an empty editor in between.
    func testTypingOverTheExampleEndsTheRehearsal() throws {
        let model = try makeModel()
        model.loadExample()
        type("Nous avons une fromage.", into: model)
        model.lintNow()
        XCTAssertEqual(model.stats.stats.sentencesChecked, 1)
        XCTAssertEqual(model.stats.stats.errorsFixed, 0)

        type("Nous avons un fromage.", into: model)
        model.lintNow()
        XCTAssertEqual(model.stats.stats.errorsFixed, 1)
        XCTAssertEqual(model.stats.stats.trickyWords, ["fromage"])
    }

    // Fixing the example's mistakes leaves its opening sentence, so the rehearsal carries on.
    func testFixingTheExampleKeepsTheRehearsal() throws {
        // The rehearsal check relies on the example opening with this mistake-free sentence.
        XCTAssertTrue(EditorModel.example.hasPrefix(EditorModel.exampleOpening))
        let model = try makeModel()
        model.loadExample()
        let fixed = Self.exampleWithFirstErrorFixed
        type(fixed, into: model)
        model.lintNow()
        XCTAssertEqual(model.stats.stats.errorsFixed, 0)
        XCTAssertEqual(model.stats.stats.sentencesChecked, 0)
    }

    /// The example with "une fromage" typed as "un fromage".
    private static let exampleWithFirstErrorFixed = EditorModel.example.replacingOccurrences(of: "une fromage", with: "un fromage")

    // A half-typed word's guess never becomes a tricky word; the fix the learner keeps does.
    func testTrickyWordsComeFromFixes() throws {
        let model = try makeModel()
        type("Nous avons une fromage.", into: model)
        model.lintNow()
        XCTAssertEqual(model.stats.stats.trickyWords, [])
        type("Nous avons un fromage.", into: model)
        model.lintNow()
        XCTAssertEqual(model.stats.stats.trickyWords, ["fromage"])
    }

    // Fixing one of two identical mistakes counts once, even though the other is still flagged.
    func testFixingOneOfTwoIdenticalMistakesCounts() throws {
        let model = try makeModel()
        type("Une fromage et une fromage.", into: model)
        model.lintNow()
        XCTAssertEqual(model.blockingIssues.count, 2)

        type("Un fromage et une fromage.", into: model)
        model.lintNow()
        XCTAssertEqual(model.stats.stats.errorsFixed, 1)
        XCTAssertEqual(model.stats.stats.fixedByLearner, 1)

        type("Un fromage et un fromage.", into: model)
        model.lintNow()
        XCTAssertEqual(model.stats.stats.errorsFixed, 2)
    }

    // A phrase stops the French, and the French stops a phrase, so two voices never overlap.
    func testPhraseAndFrenchNeverSpeakTogether() throws {
        let model = try makeModel()
        let phrase = Phrase(situation: .greetings, french: "Bonjour !", english: "Hello!", register: .either, note: nil)
        type("Je fais du vélo.", into: model)
        model.lintNow()
        model.togglePlay()
        XCTAssertEqual(narrator.state, .speaking)

        model.togglePhrase(phrase)
        XCTAssertEqual(narrator.state, .idle)
        XCTAssertTrue(model.isSpeaking(phrase))
        XCTAssertEqual(phraseNarrator.spoken, ["Bonjour !"])

        model.togglePlay()
        XCTAssertFalse(model.isSpeaking(phrase))
        XCTAssertEqual(narrator.state, .speaking)
    }

    // Playing the phrase that's already playing stops it.
    func testPlayingAPhraseAgainStopsIt() throws {
        let model = try makeModel()
        let phrase = Phrase(situation: .greetings, french: "Bonjour !", english: "Hello!", register: .either, note: nil)
        model.togglePhrase(phrase)
        model.togglePhrase(phrase)
        XCTAssertFalse(model.isSpeaking(phrase))
        XCTAssertEqual(phraseNarrator.spoken, ["Bonjour !"])
    }

    // A fix the learner types counts as theirs; Apply counts only toward the total.
    func testTypedFixCountsAsTheLearners() throws {
        let model = try makeModel()
        type("Nous avons une fromage.", into: model)
        model.lintNow()
        type("Nous avons un fromage.", into: model)
        model.lintNow()
        XCTAssertEqual(model.stats.stats.errorsFixed, 1)
        XCTAssertEqual(model.stats.stats.fixedByLearner, 1)

        type("Nous avons une fromage.", into: model)
        model.lintNow()
        let issue = try XCTUnwrap(model.blockingIssues.first)
        model.apply(issue)
        XCTAssertEqual(model.stats.stats.errorsFixed, 2)
        XCTAssertEqual(model.stats.stats.fixedByLearner, 1)
    }

    // Deleting a flagged sentence clears its error but never counts as fixing it.
    func testDeletingAnErrorIsNotAFix() throws {
        let model = try makeModel()
        type("Nous avons une fromage.", into: model)
        model.lintNow()
        type("Nous avons", into: model)
        model.lintNow()
        XCTAssertFalse(model.isLocked)
        XCTAssertEqual(model.stats.stats.errorsFixed, 0)
    }

    // An unknown word warns without blocking play, and retyping it counts as the learner's fix.
    func testRetypedUnknownWordCountsAsTheLearners() throws {
        let model = try makeModel(spellChecker: UnknownWordSpellChecker(unknown: ["Ahdourdui"]))
        type("Ahdourdui, il pleut.", into: model)
        model.lintNow()
        XCTAssertEqual(model.warnings.map(\.original), ["Ahdourdui"])
        XCTAssertTrue(model.blockingIssues.isEmpty)

        type("Aujourd'hui, il pleut.", into: model)
        model.lintNow()
        XCTAssertTrue(model.warnings.isEmpty)
        XCTAssertEqual(model.stats.stats.errorsFixed, 1)
        XCTAssertEqual(model.stats.stats.fixedByLearner, 1)
    }

    // Deleting an unknown word clears its warning but never counts as fixing it.
    func testDeletingAnUnknownWordIsNotAFix() throws {
        let model = try makeModel(spellChecker: UnknownWordSpellChecker(unknown: ["Ahdourdui"]))
        type("Il pleut Ahdourdui.", into: model)
        model.lintNow()
        type("Il pleut.", into: model)
        model.lintNow()
        XCTAssertTrue(model.warnings.isEmpty)
        XCTAssertEqual(model.stats.stats.errorsFixed, 0)
    }
}
