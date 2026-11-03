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

/// Covers two words typed as one, such as "mecouche" for "me couche" or "jaime" for "j'aime".
@MainActor
final class RunTogetherWordTests: XCTestCase {

    private static let pack: LanguagePack? = try? LanguagePack.french()

    /// Returns the bundled pack, failing the test if it didn't load.
    private func pack() throws -> LanguagePack {
        try XCTUnwrap(Self.pack, "The French language pack failed to load")
    }

    /// Reports a fixed list of misspellings, so the split can be tested without the system spellchecker.
    private struct FakeSpellChecker: SpellChecker {
        let results: [Misspelling]
        func misspellings(in text: String) -> [Misspelling] { results }
    }

    /// Builds a linter over the bundled pack with the given spellchecker.
    private func linter(_ spellChecker: any SpellChecker) throws -> Linter {
        let pack = try pack()
        return Linter(spellChecker: spellChecker, grammar: pack.grammar, lexicon: pack.lexicon, explanations: pack.explanations)
    }

    /// Builds the orthographic filter alone over the bundled pack.
    private func filter() throws -> OrthographicFilter {
        let pack = try pack()
        return OrthographicFilter(spellChecker: FakeSpellChecker(results: []), lexicon: pack.lexicon, explanations: pack.explanations)
    }

    // MARK: - The split

    // Each run-together word splits one way only: a short function word, then a known word.
    func testSplitsAfterAFunctionWord() throws {
        let filter = try filter()
        XCTAssertEqual(filter.runTogetherFix(for: "mecouche"), "me couche")
        XCTAssertEqual(filter.runTogetherFix(for: "jesuis"), "je suis")
        XCTAssertEqual(filter.runTogetherFix(for: "tumanges"), "tu manges")
        XCTAssertEqual(filter.runTogetherFix(for: "nousavons"), "nous avons")
        XCTAssertEqual(filter.runTogetherFix(for: "unchat"), "un chat")
        XCTAssertEqual(filter.runTogetherFix(for: "dela"), "de la")
    }

    // A dropped apostrophe is restored when the second word starts with a vowel or h.
    func testRestoresTheApostrophe() throws {
        let filter = try filter()
        XCTAssertEqual(filter.runTogetherFix(for: "jaime"), "j'aime")
        XCTAssertEqual(filter.runTogetherFix(for: "jaimerais"), "j'aimerais")
        XCTAssertEqual(filter.runTogetherFix(for: "sappelle"), "s'appelle")
        XCTAssertEqual(filter.runTogetherFix(for: "quil"), "qu'il")
    }

    // The fix keeps the learner's capital letter.
    func testKeepsTheCapital() throws {
        let filter = try filter()
        XCTAssertEqual(filter.runTogetherFix(for: "Jesuis"), "Je suis")
        XCTAssertEqual(filter.runTogetherFix(for: "Jaime"), "J'aime")
    }

    // A two-letter second word must itself be a function word, so "ilya" never becomes "il ya";
    // fragments Lexique lists, as in "mangerai" → "mange rai", never qualify.
    func testShortOrJunkSecondWordsAreRejected() throws {
        let filter = try filter()
        XCTAssertNil(filter.runTogetherFix(for: "ilya"))
        XCTAssertNil(filter.runTogetherFix(for: "mangerai"))
        XCTAssertNil(filter.runTogetherFix(for: "abc"))
    }

    // MARK: - Through the linter

    // A run-together word is a warning whose fix is the split, ahead of the system's single-word guess.
    func testSplitBeatsTheSystemGuess() throws {
        let linter = try linter(FakeSpellChecker(results: [Misspelling(offset: 9, word: "mecouche", guesses: ["recouche", "découche"])]))
        let issue = try XCTUnwrap(linter.lint("Ce soir, mecouche tôt.").first)
        XCTAssertEqual(issue.kind, .spelling)
        XCTAssertEqual(issue.severity, .warning)
        XCTAssertEqual(issue.replacement, "me couche")
        XCTAssertEqual(issue.reason, "mecouche is two words run together: me couche.")
        XCTAssertFalse(issue.hint.contains("me couche"))
    }

    // When the system offers the same letters with accents, the word may be a missing accent
    // ("demanger" for "démanger"), so the split steps aside and the usual ranking decides.
    func testAccentGuessWinsOverTheSplit() throws {
        let linter = try linter(FakeSpellChecker(results: [Misspelling(offset: 0, word: "etait", guesses: ["était", "étant"])]))
        XCTAssertEqual(linter.lint("etait là.").first?.replacement, "était")
    }

    // A capitalized word in mid-sentence is probably a name the system doesn't know, so it isn't split.
    func testNameInMidSentenceIsNotSplit() throws {
        let linter = try linter(FakeSpellChecker(results: [Misspelling(offset: 9, word: "Lemarchand", guesses: []) ]))
        XCTAssertNotEqual(linter.lint("Monsieur Lemarchand arrive.").first?.replacement, "Le marchand")
    }

    // MARK: - Unseen scorecard, real spellchecker

    // Sentences written before the filter was built, run through the whole linter with the
    // Mac's own French spellchecker, as a learner would see them.
    func testUnseenScorecard() throws {
        let pack = try pack()
        let linter = try linter(SystemSpellChecker(language: pack.spellCheckerLanguage))

        let mustFix: [(sentence: String, fix: String)] = [
            ("Ce soir, je mecouche tôt.", "me couche"),
            ("Jesuis content.", "Je suis"),
            ("Tumanges une pomme.", "Tu manges"),
            ("Nousavons un chien.", "Nous avons"),
            ("J'ai unchat noir.", "un chat"),
            ("Elle sappelle Marie.", "s'appelle"),
            ("Cest mon ami.", "C'est"),
            ("Il nest pas là.", "n'est"),
            ("Je vais aumarché.", "au marché"),
            ("Ellemange une pomme.", "Elle mange"),
            ("Jarrive demain.", "J'arrive"),
            ("Il mange dupain.", "du pain"),
            ("Je parle avec lesenfants.", "les enfants"),
            ("Je pense quil pleut.", "qu'il"),
            ("Ilya un chat.", "Il y a")
        ]
        for (sentence, fix) in mustFix {
            XCTAssertTrue(linter.lint(sentence).contains { $0.replacement == fix }, "\(sentence) should offer \(fix)")
        }

        // The one miss in the unseen set: the Mac accepts a capitalized "Jaime" as a first
        // name, so the filter never sees it. Lowercase "jaime" is flagged and split.
        XCTAssertFalse(linter.lint("Jaime le fromage.").contains { $0.replacement == "J'aime" })
        XCTAssertTrue(linter.lint("Moi, jaime le fromage.").contains { $0.replacement == "j'aime" })

        let mustNotSplit: [(sentence: String, wrongFix: String)] = [
            ("Ça va me demanger.", "de manger"),
            ("Il etait là.", "et ait"),
            ("Monsieur Dupont arrive.", "Du pont")
        ]
        for (sentence, wrongFix) in mustNotSplit {
            XCTAssertFalse(linter.lint(sentence).contains { $0.replacement == wrongFix }, "\(sentence) offered \(wrongFix)")
        }

        let correct = ["Je suis content.", "Bonjour, je m'appelle Paul.", "Il a un parapluie.", "Je mangerai demain.", "C'est bon."]
        for sentence in correct {
            XCTAssertEqual(linter.lint(sentence).map(\.original), [], sentence)
        }
    }
}
