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
    private func makeModel(spellChecker: any SpellChecker = SilentSpellChecker(), journal: Journal? = nil) throws -> EditorModel {
        let pack = try LanguagePack.french()
        let linter = Linter(spellChecker: spellChecker, grammar: pack.grammar, lexicon: pack.lexicon, explanations: pack.explanations)
        narrator = FakeNarrator()
        phraseNarrator = FakeNarrator()
        return EditorModel(stats: StatsStore(fileURL: nil), journal: journal, narrator: narrator, phraseNarrator: phraseNarrator, linter: linter)
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

        model.startNew()
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

    // Picking the other wording on a "did you mean" card replaces the words.
    func testChoosingAnotherWordingReplacesIt() throws {
        let model = try makeModel()
        type("Je ne mange pas encore de viande.", into: model)
        model.lintNow()
        let issue = try XCTUnwrap(model.visibleIssues.first { $0.kind == .meaning })
        let plus = try XCTUnwrap(issue.choices.first { !issue.isOriginal($0) })
        model.choose(plus, for: issue)
        XCTAssertEqual(String(model.text.characters), "Je ne mange plus de viande.")
        XCTAssertFalse(model.visibleIssues.contains { $0.kind == .meaning })
        XCTAssertEqual(model.stats.stats.errorsFixed, 0)
    }

    // Keeping the learner's own wording closes the question without changing the text.
    func testKeepingTheOwnWordingHidesTheQuestion() throws {
        let model = try makeModel()
        type("Je ne mange pas encore de viande.", into: model)
        model.lintNow()
        let issue = try XCTUnwrap(model.visibleIssues.first { $0.kind == .meaning })
        let own = try XCTUnwrap(issue.choices.first { issue.isOriginal($0) })
        model.choose(own, for: issue)
        XCTAssertEqual(String(model.text.characters), "Je ne mange pas encore de viande.")
        XCTAssertFalse(model.visibleIssues.contains { $0.kind == .meaning })
    }

    // Try an example shows every level: errors, a warning, and a suggestion.
    func testExampleShowsEveryLevel() throws {
        let model = try makeModel()
        model.showsSuggestions = true
        model.loadExample()
        let severities = Set(model.visibleIssues.map(\.severity))
        XCTAssertEqual(severities, [.error, .warning, .suggestion])
    }

    // Try an example's mistakes aren't the learner's: fixing them counts nothing until New starts a blank page.
    func testExampleIsNotCounted() throws {
        let model = try makeModel()
        model.loadExample()
        let issue = try XCTUnwrap(model.blockingIssues.first)
        model.apply(issue)
        XCTAssertEqual(model.stats.stats.errorsFixed, 0)
        XCTAssertEqual(model.stats.stats.sentencesChecked, 0)

        model.startNew()
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

    // Opening a file that holds an error's fix doesn't count the fix as the learner's.
    func testOpeningAFileIsNotAFix() throws {
        let model = try makeModel()
        type("Nous avons acheté une fromage.", into: model)
        model.lintNow()
        XCTAssertFalse(model.blockingIssues.isEmpty)
        model.open("Nous avons acheté un fromage.")
        XCTAssertEqual(model.plainText, "Nous avons acheté un fromage.")
        XCTAssertTrue(model.blockingIssues.isEmpty)
        XCTAssertEqual(model.stats.stats.errorsFixed, 0)
    }

    // A new entry replaces the text with today's French date and opening lines, the caret after "Il fait".
    func testNewEntryStartsWithTheDate() throws {
        let model = try makeModel()
        type("Nous avons une fromage.", into: model)
        model.lintNow()
        let checkedBefore = model.stats.stats.sentencesChecked
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12)))
        model.newEntry(on: date)
        XCTAssertTrue(model.plainText.hasPrefix(EditorModel.entryGuide + "\nLe 1er novembre 2026\n\n// What's the weather like?\nIl fait \n"))
        XCTAssertTrue(model.blockingIssues.isEmpty)
        XCTAssertNil(model.fileURL)
        XCTAssertEqual(model.stats.stats.errorsFixed, 0)
        // The date line has no full stop and the notes are never checked, so starting
        // an entry checks no sentences.
        XCTAssertEqual(model.stats.stats.sentencesChecked, checkedBefore)
    }

    // Other days of the month are plain numbers.
    func testEntryHeaderDate() throws {
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12)))
        let header = EditorModel.entryHeader(for: date)
        XCTAssertTrue(header.text.hasPrefix(EditorModel.entryGuide + "\nLe 31 octobre 2026\n"))
        XCTAssertEqual(String(header.text.prefix(header.caret)), EditorModel.entryGuide + "\nLe 31 octobre 2026\n\n// What's the weather like?\nIl fait ")
    }

    // Each starter's note sits on the line above it, and typing at the caret finishes the first starter.
    func testEntryHeaderNotes() throws {
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12)))
        let header = EditorModel.entryHeader(for: date)
        // Built line by line, since each starter ends in a space an editor might strip.
        let expected = [
            "// Finish each sentence in French, then keep going. Grey notes are never checked.",
            "Le 2 novembre 2026",
            "",
            "// What's the weather like?",
            "Il fait ",
            "",
            "// Where are you writing from today?",
            "Je suis à ",
            "",
            "// What are you wearing?",
            "Je porte ",
            "",
            "// How do you feel, and why?",
            "Je me sens ",
            ""
        ].joined(separator: "\n")
        XCTAssertEqual(header.text, expected)
        XCTAssertEqual(Notes.ranges(in: header.text).count, 5)
        var typed = header.text
        typed.insert(contentsOf: "froid.", at: typed.index(typed.startIndex, offsetBy: header.caret))
        XCTAssertTrue(typed.contains("// What's the weather like?\nIl fait froid.\n"))
        XCTAssertEqual(Notes.removed(typed), "Le 2 novembre 2026\n\nIl fait froid.\n\nJe suis à\n\nJe porte\n\nJe me sens\n")
    }

    // New starts a blank page with no file, and the example has none either.
    func testFileURLFollowsTheText() throws {
        let model = try makeModel()
        let url = URL(fileURLWithPath: "/tmp/entry.txt")
        model.open("Il pleut.", from: url)
        XCTAssertEqual(model.fileURL, url)
        model.startNew()
        XCTAssertNil(model.fileURL)
        XCTAssertFalse(model.hasText)
        XCTAssertFalse(model.needsSaveDecision)
        model.open("Il pleut.", from: url)
        model.loadExample()
        XCTAssertNil(model.fileURL)
        XCTAssertEqual(model.document, .unsaved)
    }

    // A typed fix shows in the corrections list with the sentence it was made in.
    func testTypedFixIsLogged() throws {
        let model = try makeModel()
        type("Il pleut. Nous avons une fromage.", into: model)
        model.lintNow()
        type("Il pleut. Nous avons un fromage.", into: model)
        model.lintNow()
        let correction = try XCTUnwrap(model.stats.stats.corrections.last)
        XCTAssertEqual(correction.corrected, "un fromage")
        XCTAssertEqual(correction.sentence, "Nous avons une fromage.")
    }

    // Cut and Copy need selected text; a bare caret has none.
    func testHasSelection() throws {
        let model = try makeModel()
        type("Il pleut.", into: model)
        model.selection = AttributedTextSelection(insertionPoint: model.text.startIndex)
        XCTAssertFalse(model.hasSelection)
        let end = model.text.characters.index(model.text.startIndex, offsetBy: 2)
        model.selection = AttributedTextSelection(range: model.text.startIndex..<end)
        XCTAssertTrue(model.hasSelection)
    }

    // MARK: - Journal

    /// An empty journal and workspace in their own temporary folder, with their own defaults.
    private func makeJournal() throws -> (journal: Journal, workspace: Workspace) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "CoquilleTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CoquilleTests-\(UUID().uuidString)"))
        let workspace = Workspace(folderURL: folder.appending(path: "Workspace"), defaults: defaults)
        return (Journal(folderURL: folder.appending(path: "Journal")), workspace)
    }

    /// A model over a journal and workspace.
    private func makeModel(_ files: (journal: Journal, workspace: Workspace)) throws -> EditorModel {
        let pack = try LanguagePack.french()
        let linter = Linter(spellChecker: SilentSpellChecker(), grammar: pack.grammar, lexicon: pack.lexicon, explanations: pack.explanations)
        return EditorModel(stats: StatsStore(fileURL: nil), journal: files.journal, workspace: files.workspace, narrator: FakeNarrator(), phraseNarrator: FakeNarrator(), linter: linter)
    }

    /// Today as "2026-10-31", the way entry names start.
    private var today: String {
        LearnerStats.dayKey(for: .now, calendar: .current)
    }

    // Writing never reaches the journal on its own, and asks to be saved before it's replaced.
    func testUnsavedWritingIsNeverSavedToTheJournal() throws {
        let files = try makeJournal()
        let model = try makeModel(files)
        XCTAssertFalse(model.needsSaveDecision)
        type("Il pleut.", into: model)
        model.lintNow()
        XCTAssertEqual(model.document, .unsaved)
        XCTAssertTrue(files.journal.entries.isEmpty)
        XCTAssertTrue(model.needsSaveDecision)
    }

    // Opening an entry lets unsaved writing go, so the next launch shows the entry.
    func testOpeningAnEntryLetsUnsavedWritingGo() throws {
        let files = try makeJournal()
        let model = try makeModel(files)
        type("Mes notes.", into: model)
        model.lintNow()
        let url = try files.journal.createEntry(text: "Il neige.", title: "Hiver")
        try model.openEntry(url)
        XCTAssertEqual(model.plainText, "Il neige.")

        let next = try makeModel(files)
        next.restore()
        XCTAssertEqual(next.fileURL, url)
        XCTAssertEqual(next.plainText, "Il neige.")
        XCTAssertFalse(next.isEdited)
    }

    // Saving writing makes it an entry, named for today and its title.
    func testSavingUnsavedWritingMakesAnEntry() throws {
        let files = try makeJournal()
        let model = try makeModel(files)
        type("Il pleut.", into: model)
        model.lintNow()
        XCTAssertTrue(model.saveNeedsTitle)
        try model.save(title: "Au marché")
        XCTAssertEqual(model.fileURL?.lastPathComponent, "\(today) Au marché.txt")
        XCTAssertFalse(model.isEdited)
        XCTAssertFalse(model.needsSaveDecision)
        XCTAssertEqual(files.journal.entries.map(\.text), ["Il pleut."])
    }

    // Changing a saved entry marks it edited, and Save writes it back to the same file.
    func testSaveWritesBackToTheEntry() throws {
        let files = try makeJournal()
        let model = try makeModel(files)
        let url = try files.journal.createEntry(text: "Il pleut.", title: "Pluie")
        try model.openEntry(url)
        XCTAssertFalse(model.needsSaveDecision)
        type("Il pleut beaucoup.", into: model)
        XCTAssertTrue(model.isEdited)
        XCTAssertTrue(model.needsSaveDecision)
        // Typing alone never touches the entry's file.
        XCTAssertEqual(try FrenchTextFile.text(at: url), "Il pleut.")
        try model.save()
        XCTAssertEqual(try FrenchTextFile.text(at: url), "Il pleut beaucoup.")
        XCTAssertFalse(model.isEdited)
    }

    // A new entry asks to be saved only once it differs from its opening lines.
    func testNewEntryNeedsSavingOnceChanged() throws {
        let files = try makeJournal()
        let model = try makeModel(files)
        model.newEntry()
        XCTAssertFalse(model.needsSaveDecision)
        XCTAssertNil(model.fileURL)
        type(model.plainText + "Il fait beau.", into: model)
        XCTAssertTrue(model.needsSaveDecision)
        try model.save(title: "")
        XCTAssertEqual(model.fileURL?.lastPathComponent, "\(today).txt")
    }

    // Save as New Entry leaves the original as it was saved.
    func testSaveAsNewEntryLeavesTheOriginal() throws {
        let files = try makeJournal()
        let model = try makeModel(files)
        let original = try files.journal.createEntry(text: "Il pleut.", title: "Pluie")
        try model.openEntry(original)
        type("Il neige.", into: model)
        try model.saveAsNewEntry(title: "Neige")
        XCTAssertEqual(try FrenchTextFile.text(at: original), "Il pleut.")
        XCTAssertEqual(model.fileURL?.lastPathComponent, "\(today) Neige.txt")
        XCTAssertEqual(files.journal.entries.count, 2)
    }

    // Renaming the open entry keeps the editor on it, under its new name.
    func testRenameFollowsTheOpenEntry() throws {
        let files = try makeJournal()
        let model = try makeModel(files)
        let url = try files.journal.createEntry(text: "Il pleut.", title: "Pluie")
        try model.openEntry(url)
        try model.renameEntry(url, to: "Averse")
        XCTAssertEqual(model.fileURL?.lastPathComponent, "\(today) Averse.txt")
        XCTAssertEqual(model.plainText, "Il pleut.")
    }

    // Deleting the open entry keeps its text as a new entry that asks to be saved.
    func testDeletingTheOpenEntryKeepsItsText() throws {
        let files = try makeJournal()
        let model = try makeModel(files)
        let url = try files.journal.createEntry(text: "Il pleut.", title: "Pluie")
        try model.openEntry(url)
        try model.deleteEntry(url)
        XCTAssertEqual(model.document, .unsaved)
        XCTAssertEqual(model.plainText, "Il pleut.")
        XCTAssertTrue(model.needsSaveDecision)
        XCTAssertTrue(files.journal.entries.isEmpty)
    }

    // The example's mistakes aren't the learner's, so it can't be saved.
    func testExampleCannotBeSaved() throws {
        let model = try makeModel(try makeJournal())
        model.loadExample()
        XCTAssertFalse(model.canSave)
        XCTAssertFalse(model.needsSaveDecision)
    }

    // The next launch reopens the entry with the changes it hadn't saved, still marked edited.
    func testRestoreBringsBackUnsavedChanges() throws {
        let files = try makeJournal()
        let first = try makeModel(files)
        let url = try files.journal.createEntry(text: "Il pleut.", title: "Pluie")
        try first.openEntry(url)
        type("Il pleut fort.", into: first)
        first.lintNow()

        let second = try makeModel(files)
        second.restore()
        XCTAssertEqual(second.fileURL, url)
        XCTAssertEqual(second.plainText, "Il pleut fort.")
        XCTAssertTrue(second.isEdited)
    }

    // The next launch brings back writing that wasn't saved.
    func testRestoreBringsBackUnsavedWriting() throws {
        let files = try makeJournal()
        let first = try makeModel(files)
        type("Mes notes.", into: first)
        first.lintNow()

        let second = try makeModel(files)
        second.restore()
        XCTAssertEqual(second.document, .unsaved)
        XCTAssertTrue(second.needsSaveDecision)
        XCTAssertEqual(second.plainText, "Mes notes.")
    }

    // A widget prompt is an unsaved note and blank answer line, never a French answer.
    func testWidgetPromptEntryHasExactTextAndCaret() throws {
        let model = try makeModel()
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12)))
        let prompt = WritingPrompt(id: "shopping", text: "What time does it close?", level: "A1", topic: "Shopping", lesson: "Opening hours")
        let expected = EditorModel.guidedEntry(prompts: [prompt.text], for: date)
        let checkedBefore = model.stats.stats.sentencesChecked
        model.newEntry(for: prompt, on: date)
        XCTAssertEqual(model.plainText, expected.text)
        XCTAssertEqual(String(model.plainText.prefix(expected.caret)), EditorModel.entryGuide + "\nLe 1er novembre 2026\n\n// What time does it close?\n\n")
        XCTAssertEqual(Notes.removed(model.plainText), "Le 1er novembre 2026\n\n\n")
        XCTAssertNil(model.fileURL)
        XCTAssertFalse(model.needsSaveDecision)
        XCTAssertEqual(model.stats.stats.sentencesChecked, checkedBefore)
    }

    // An exercise retains its title and hint only while that draft is open.
    func testExerciseEntryContentAndLifecycle() throws {
        let files = try makeJournal()
        let model = try makeModel(files)
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12)))
        let exercise = ExercisePrompt(title: "Ouvert ou fermé", prompts: ["Is it open?", "It was closed."], hint: "c'était")
        model.newEntry(for: exercise, on: date)
        XCTAssertEqual(model.plainText, EditorModel.guidedEntry(prompts: exercise.prompts, for: date).text)
        XCTAssertEqual(model.exerciseTitle, exercise.title)
        XCTAssertEqual(model.exerciseHint, exercise.hint)
        XCTAssertTrue(model.proposedName(title: model.exerciseTitle).hasPrefix("2026-11-02"))
        XCTAssertEqual(Notes.ranges(in: model.plainText).count, 3)
        XCTAssertFalse(model.plainText.contains("c'était"))
        model.startNew()
        XCTAssertNil(model.exerciseTitle)
        XCTAssertNil(model.exerciseHint)
        model.newEntry(for: exercise, on: date)
        model.newEntry(on: date)
        XCTAssertNil(model.exerciseTitle)
        XCTAssertNil(model.exerciseHint)
    }
}

final class FrenchTextFileTests: XCTestCase {

    // The story's title names the file, without the characters a file name can't hold.
    func testSuggestedFilenameUsesTheTitle() {
        XCTAssertEqual(FrenchTextFile.suggestedFilename(for: "Une journée au marché"), "Une journée au marché")
        XCTAssertEqual(FrenchTextFile.suggestedFilename(for: "Paris: 1/2 journée"), "Paris 12 journée")
    }

    // With no title, or one that's only punctuation, the date names the file.
    func testSuggestedFilenameFallsBackToTheDate() throws {
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12)))
        XCTAssertEqual(FrenchTextFile.suggestedFilename(for: nil, on: date), "2026-10-31")
        XCTAssertEqual(FrenchTextFile.suggestedFilename(for: " / ", on: date), "2026-10-31")
    }
}
