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

/// Three small rules from a learner's entry that passed with five mistakes: a hyphen inside
/// words written apart, two determiners in a row, and a bare verb form after être. Each has lines that must be flagged and lines that must stay clean.
@MainActor
final class SmallRuleTests: XCTestCase {

    /// Reports no misspellings, so the tests check grammar alone.
    private struct SilentSpellChecker: SpellChecker {
        func misspellings(in text: String) -> [Misspelling] { [] }
    }

    private func linter() throws -> Linter {
        let pack = try LanguagePack.french()
        return Linter(spellChecker: SilentSpellChecker(), grammar: pack.grammar, lexicon: pack.lexicon, explanations: pack.explanations)
    }

    /// The issues in `text`, each as "original → fix (severity)".
    private func report(_ text: String) throws -> [String] {
        try linter().lint(text).map { "\($0.original) → \($0.replacement ?? "no fix") (\($0.severity.rawValue))" }
    }

    /// Returns `text` with each issue's replacement applied, last issue first.
    private func applying(_ text: String) throws -> String {
        var characters = Array(text)
        for issue in try linter().lint(text).sorted(by: { $0.offset > $1.offset }) {
            guard let replacement = issue.replacement else { continue }
            characters.replaceSubrange(issue.range, with: Array(replacement))
        }
        return String(characters)
    }

    /// Asserts each line comes back with nothing to say.
    private func assertClean(_ lines: [String], file: StaticString = #filePath, line: UInt = #line) throws {
        for text in lines {
            XCTAssertEqual(try report(text), [], text, file: file, line: line)
        }
    }

    // MARK: - Hyphens

    // A hyphen inside words written apart is flagged, and the fix writes them apart.
    func testHyphenInsideSeparateWords() throws {
        XCTAssertEqual(try report("Je suis fatigué parce-que j'ai travaillé."), ["parce-que → parce que (error)"])
        XCTAssertEqual(try report("Il a beaucoup-de photos."), ["beaucoup-de → beaucoup de (error)"])
        XCTAssertEqual(try report("Il-y-a un chat."), ["Il-y-a → Il y a (error)"])
        XCTAssertEqual(try applying("Je suis fatigué parce-que j'ai travaillé."), "Je suis fatigué parce que j'ai travaillé.")
    }

    // Real hyphenated words, inversions and compounds stay clean.
    func testRealHyphenatedWordsStayClean() throws {
        try assertClean([
            "Peut-être qu'il viendra.",
            "Est-ce que tu viens?",
            "Dit-on cela en français?",
            "A-t-il mangé?",
            "J'adore ma grand-mère.",
            "Nous-mêmes, nous le faisons.",
            "Cet après-midi, nous allons au cinéma.",
            "Rendez-vous demain à neuf heures.",
            "Où est-il?"
        ])
    }

    // MARK: - Two determiners

    // An article beside a possessive is dropped in the fix; two articles name no fix.
    func testTwoDeterminersInARow() throws {
        XCTAssertEqual(try report("Je vois mon l'ami."), ["mon l' → mon  (error)"])
        XCTAssertEqual(try applying("Je vois mon l'ami."), "Je vois mon ami.")
        XCTAssertEqual(try report("Je vois le mon ami."), ["le mon → mon (error)"])
        XCTAssertEqual(try applying("Je vois le mon ami."), "Je vois mon ami.")
        XCTAssertEqual(try report("Il a un la maison."), ["un la → no fix (error)"])
    }

    // Correct pairs that look like two determiners stay clean.
    func testCorrectPairsOfDeterminersStayClean() throws {
        try assertClean([
            "L'un de mes amis est là.",
            "Un des enfants joue.",
            "Le ton de sa voix est doux.",
            "Au son de la musique, il danse.",
            "Il le lui donne.",
            "Elle la leur dit.",
            "Plusieurs des élèves sont partis.",
            "Le mien est rouge."
        ])
    }

    // MARK: - Quantity and des

    // Des after a quantity word that follows a participle is a warning with de as the fix.
    func testDesAfterAParticiple() throws {
        XCTAssertEqual(try report("J'ai perdu beaucoup des photos avec mon portable."), ["des → de (warning)"])
        XCTAssertEqual(try report("Nous avons invité peu des amis."), ["des amis → d'amis (warning)"])
        XCTAssertEqual(try applying("J'ai perdu beaucoup des photos."), "J'ai perdu beaucoup de photos.")
        // Right after avoir, the existing word-choice pattern speaks, as an error.
        XCTAssertEqual(try report("Il a beaucoup des photos."), ["beaucoup des → beaucoup de (error)"])
    }

    // Des that means "of the", a verb that takes de, and de itself stay clean.
    func testOfTheGroupStaysClean() throws {
        try assertClean([
            "J'ai perdu beaucoup de photos.",
            "Il a parlé beaucoup des vacances.",
            "Il parle beaucoup des vacances.",
            "J'ai perdu beaucoup des photos que j'avais prises.",
            "J'ai gardé peu des autres.",
            "Beaucoup des gens que je connais sont partis."
        ])
    }

    // MARK: - A verb form after être

    // A verb of movement after être becomes a past participle; other bare verbs only warn.
    func testBareVerbAfterEtre() throws {
        XCTAssertEqual(try report("Je suis aller au marché."), ["aller → allé (error)"])
        XCTAssertEqual(try report("Elle est aller au parc."), ["aller → allée (error)"])
        XCTAssertEqual(try report("Ils sont venir ce soir."), ["venir → venus (error)"])
        XCTAssertEqual(try report("Je suis travailler ce soir."), ["travailler → no fix (warning)"])
        XCTAssertEqual(try applying("Je suis aller au marché."), "Je suis allé au marché.")
    }

    // Adjectives, participles, nouns and c'est with an infinitive stay clean.
    func testEtreWithOtherWordsStaysClean() throws {
        try assertClean([
            "C'est partir qui est difficile.",
            "Partir, c'est mourir un peu.",
            "Il est fort.",
            "Elle est pilote.",
            "Il est parti.",
            "Je suis content.",
            "Il est tard.",
            "Nous sommes ensemble.",
            "Elle est là pour aider."
        ])
    }
}
