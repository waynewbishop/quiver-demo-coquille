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

/// Checks the bundled phrasebook against the real lexicon and rules, and its search.
final class PhrasebookTests: XCTestCase {

    private static let pack: LanguagePack? = try? LanguagePack.french()

    /// Returns the bundled pack, failing the test if it didn't load.
    private func pack() throws -> LanguagePack {
        try XCTUnwrap(Self.pack, "The French language pack failed to load")
    }

    // MARK: - The bundled phrases

    // A phrase the learner copies must never be flagged once they type it: no error,
    // suggestion or question of any kind. The phrasebook is the golden French learners copy.
    func testEveryPhraseLintsClean() throws {
        let pack = try pack()
        for phrase in pack.phrases {
            let issues = pack.grammar.check(phrase.french).map { "\($0.original) → \($0.replacement ?? "")" }
            XCTAssertEqual(issues, [], phrase.french)
        }
    }

    // Every word is one the lexicon knows, so spellcheck has nothing to flag either.
    // An inverted form such as allez-vous is checked one part at a time.
    func testEveryWordIsKnown() throws {
        let pack = try pack()
        for phrase in pack.phrases {
            for token in FrenchTokenizer.tokens(in: phrase.french) {
                let word = token.normalized
                // Elided forms such as j' and qu' aren't dictionary entries of their own.
                let isElision = word.hasSuffix("'") && FrenchTokenizer.elisionPrefixes.contains(String(word.dropLast()))
                let known = isElision || pack.lexicon.contains(word)
                    || word.split(separator: "-").allSatisfy { pack.lexicon.contains(String($0)) }
                XCTAssertTrue(known, "\(word) in \(phrase.french)")
            }
        }
    }

    // The real system spellchecker, run through the whole linter, accepts every phrase too:
    // apostrophes (aujourd'hui, s'il) and hyphens (allez-vous) are where it could disagree.
    @MainActor
    func testWholeLinterAcceptsEveryPhrase() throws {
        let pack = try pack()
        let linter = Linter(
            spellChecker: SystemSpellChecker(language: pack.spellCheckerLanguage),
            grammar: pack.grammar,
            lexicon: pack.lexicon,
            explanations: pack.explanations
        )
        for phrase in pack.phrases {
            let issues = linter.lint(phrase.french).map { "\($0.original) → \($0.replacement ?? "")" }
            XCTAssertEqual(issues, [], phrase.french)
        }
    }

    // Each situation has phrases, and no phrase is listed twice.
    func testSituationsAreFilledWithoutDuplicates() throws {
        let phrases = try pack().phrases
        for situation in Situation.allCases {
            XCTAssertFalse(phrases.filter { $0.situation == situation }.isEmpty, situation.title)
        }
        XCTAssertEqual(Set(phrases.map(\.id)).count, phrases.count)
    }

    // MARK: - Search

    // An empty search lists everything in the phrasebook's order.
    func testEmptyQueryReturnsEverything() throws {
        let phrases = try pack().phrases
        XCTAssertEqual(PhraseSearch.matches(for: "  ", in: phrases), phrases)
    }

    // A typo still finds the phrase, through letter-pair cosine similarity.
    func testSearchForgivesTypos() throws {
        let phrases = try pack().phrases
        XCTAssertEqual(PhraseSearch.matches(for: "bonjur", in: phrases).first?.french, "Bonjour !")
    }

    // Accents are optional, and a word still being typed matches the words it starts.
    func testSearchIgnoresAccentsAndMatchesPrefixes() throws {
        let phrases = try pack().phrases
        XCTAssertTrue(PhraseSearch.matches(for: "cafe", in: phrases).contains { $0.french == "Un café, s'il vous plaît." })
        XCTAssertTrue(PhraseSearch.matches(for: "addi", in: phrases).contains { $0.french == "L'addition, s'il vous plaît." })
    }

    // English words find their French phrase.
    func testSearchFindsEnglish() throws {
        let phrases = try pack().phrases
        XCTAssertEqual(PhraseSearch.matches(for: "passport", in: phrases).first?.french, "J'ai perdu mon passeport.")
    }

    // A word unlike anything in the phrasebook finds nothing.
    func testSearchWithNoMatchIsEmpty() throws {
        let phrases = try pack().phrases
        XCTAssertEqual(PhraseSearch.matches(for: "zyzzyva", in: phrases), [])
    }
}
