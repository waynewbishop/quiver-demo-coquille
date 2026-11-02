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
import Quiver
@testable import quiver_demo_coquille

/// Covers the pieces around the rules: spellcheck merging, suggestion ranking,
/// tokenizing, templates and the gender model's plumbing.
@MainActor
final class LinterTests: XCTestCase {

    /// Reports a fixed list of misspellings, so linting can be tested without the system spellchecker.
    private struct FakeSpellChecker: SpellChecker {
        let results: [Misspelling]
        func misspellings(in text: String) -> [Misspelling] { results }
    }

    /// Builds a linter over the bundled pack with a fake spellchecker.
    private func linter(reporting misspellings: [Misspelling]) throws -> Linter {
        let pack = try LanguagePack.french()
        return Linter(
            spellChecker: FakeSpellChecker(results: misspellings),
            grammar: pack.grammar,
            lexicon: pack.lexicon,
            explanations: pack.explanations
        )
    }

    // MARK: - Spelling

    // A misspelling becomes an error whose fix is the best-ranked guess.
    func testSpellingUsesRankedGuess() throws {
        let text = "Elle est gentile."
        let linter = try linter(reporting: [Misspelling(offset: 9, word: "gentile", guesses: ["gentil", "gentille"])])
        let issues = linter.lint(text)
        XCTAssertEqual(issues.map(\.replacement), ["gentille"])
        XCTAssertEqual(issues.first?.reason, "gentile isn't in the French dictionary. Did you mean gentille?")
    }

    // The spelling hint says where to look, but keeps the fix for Show fix.
    func testSpellingHintPointsWithoutGivingFix() throws {
        let text = "Elle est gentile."
        let linter = try linter(reporting: [Misspelling(offset: 9, word: "gentile", guesses: ["gentil", "gentille"])])
        let hint = try XCTUnwrap(linter.lint(text).first?.hint)
        XCTAssertEqual(hint, "gentile isn't in the French dictionary, but a word close to it is. Look again at the ending.")
        XCTAssertFalse(hint.contains("gentille"))
    }

    // The part of a typo to rework: its accents, start, middle or ending.
    func testChangedPartOfTypo() {
        XCTAssertEqual(OrthographicFilter.changedPart(of: "tres", toReach: "très"), "the accents")
        XCTAssertEqual(OrthographicFilter.changedPart(of: "etait", toReach: "était"), "the accents")
        XCTAssertEqual(OrthographicFilter.changedPart(of: "gentile", toReach: "gentille"), "the ending")
        XCTAssertEqual(OrthographicFilter.changedPart(of: "bomme", toReach: "pomme"), "the start")
        XCTAssertEqual(OrthographicFilter.changedPart(of: "maizon", toReach: "maison"), "the middle")
    }

    // A word Lexique knows is never reported as misspelled, whatever the system says.
    // English guesses from the system spellchecker are never offered.
    func testSpellingDropsGuessesOutsideTheLexicon() throws {
        let text = "Elle est gentile."
        let linter = try linter(reporting: [Misspelling(offset: 9, word: "gentile", guesses: ["gentle", "gentille"])])
        XCTAssertEqual(linter.lint(text).map(\.replacement), ["gentille"])

        let english = try self.linter(reporting: [Misspelling(offset: 9, word: "gentile", guesses: ["gentle"])])
        XCTAssertEqual(english.lint(text).map(\.replacement), [nil])
    }

    // A misspelling with no French guess is still underlined, as a warning with no fix.
    func testUnknownWordIsFlaggedWithoutAFix() throws {
        let linter = try linter(reporting: [Misspelling(offset: 0, word: "Ahdourdui", guesses: [])])
        let issue = try XCTUnwrap(linter.lint("Ahdourdui, il pleut.").first)
        XCTAssertEqual(issue.kind, .spelling)
        XCTAssertEqual(issue.severity, .warning)
        XCTAssertNil(issue.replacement)
        XCTAssertEqual(issue.hint, "Ahdourdui isn't in the French dictionary, and there's no close match to suggest.")
    }

    func testLexiconWordsAreNotMisspelled() throws {
        let linter = try linter(reporting: [Misspelling(offset: 0, word: "boulangère", guesses: ["boulanger"])])
        XCTAssertEqual(linter.lint("boulangère").count, 0)
    }

    // Where a spelling and a grammar issue overlap, only one survives.
    func testOverlappingIssuesKeepOne() throws {
        let linter = try linter(reporting: [Misspelling(offset: 3, word: "fromag", guesses: ["fromage"])])
        let issues = linter.lint("Un fromag.")
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.kind, .spelling)
    }

    // A look-alike's fix wins over the spellchecker's, which turns "sava" into "cava".
    func testLookAlikeOutranksSpelling() throws {
        let linter = try linter(reporting: [Misspelling(offset: 8, word: "sava", guesses: ["cava"])])
        let issues = linter.lint("Comment sava?")
        XCTAssertEqual(issues.map(\.kind), [.lookAlike])
        XCTAssertEqual(issues.map(\.replacement), ["ça va"])
    }

    // MARK: - Suggestion ranking

    // Quiver's cosine similarity on letter pairs puts the closest guess first.
    func testRankerPrefersClosestLetters() {
        XCTAssertEqual(SuggestionRanker.ranked(["gentil", "gentille"], for: "gentile"), ["gentille", "gentil"])
    }

    // A missing accent outranks a near miss: the Mac's own guesses for "tete", in its order.
    func testRankerIgnoresAccents() {
        let guesses = ["tête", "tète", "tee", "tété", "tente", "teste", "tâte", "tette", "texte"]
        XCTAssertEqual(SuggestionRanker.ranked(guesses, for: "tete").first, "tête")
        XCTAssertEqual(SuggestionRanker.letterPairs(of: "Tête"), ["^t", "te", "et", "te", "e$"])
    }

    // Letter pairs include start and end markers.
    func testLetterPairs() {
        XCTAssertEqual(SuggestionRanker.letterPairs(of: "chat"), ["^c", "ch", "ha", "at", "t$"])
    }

    // MARK: - Tokenizer

    // Elided articles split off; other apostrophes and hyphens stay inside the word.
    func testTokenizer() {
        let words = FrenchTokenizer.tokens(in: "L’école d'aujourd'hui, grand-mère.").map(\.normalized)
        XCTAssertEqual(words, ["l'", "école", "d'", "aujourd'hui", "grand-mère"])
    }

    // Offsets count characters, so accented letters and ligatures don't shift underlines.
    func testTokenOffsets() {
        let tokens = FrenchTokenizer.tokens(in: "ma sœur rit")
        XCTAssertEqual(tokens.map(\.offset), [0, 3, 8])
    }

    // MARK: - Templates

    // A templates file missing a rule's entry fails at load, not mid-lint.
    func testTemplatesRequireEveryKey() {
        let data = Data(#"{"spelling": {"template": "x", "example": "y"}}"#.utf8)
        XCTAssertThrowsError(try ExplanationTemplates(data: data))
    }

    // A template naming a value its rule never fills fails at load, rather than showing "{nuon}".
    func testTemplatesRejectUnknownPlaceholders() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "fr.explanations", withExtension: "json"))
        var entries = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: [String: String]])
        entries["articleGender"]?["template"] = "{nuon} is {gender}."
        let data = try JSONSerialization.data(withJSONObject: entries)
        XCTAssertThrowsError(try ExplanationTemplates(data: data)) { error in
            XCTAssertEqual(error as? ExplanationTemplates.UnknownPlaceholder, .init(key: "articleGender", placeholder: "nuon"))
        }
    }

    // Every bundled template renders with its declared values and leaves no placeholder behind.
    func testBundledTemplatesFillCompletely() throws {
        let templates = try XCTUnwrap(try? LanguagePack.french()).explanations
        for key in ExplanationKey.allCases {
            let values = Dictionary(uniqueKeysWithValues: key.placeholders.map { ($0, "x") })
            let explanation = templates.render(key, values)
            XCTAssertTrue(ExplanationTemplates.placeholders(in: explanation.reason + explanation.hint).isEmpty, key.rawValue)
        }
    }

    // MARK: - Gender model plumbing

    /// Trains a two-ending model: -tion feminine, -ment masculine.
    private func tinyModel() throws -> EndingGenderModel {
        let features: [[Double]] = [[1.0, 0.0], [1.0, 0.0], [1.0, 0.0], [0.0, 1.0], [0.0, 1.0], [0.0, 1.0]]
        let labels = [1, 1, 1, 0, 0, 0]
        let model = try LogisticRegression.fit(features: features, labels: labels, learningRate: 0.5, maxIterations: 2000)
        return EndingGenderModel(endings: ["tion", "ment"], model: model)
    }

    // The model predicts from endings and names the ending that decided it.
    func testEndingModelExplainsItself() throws {
        let model = try tinyModel()
        XCTAssertEqual(model.gender(of: "nation")?.gender, .feminine)
        XCTAssertEqual(model.gender(of: "nation")?.ending, "tion")
        XCTAssertEqual(model.gender(of: "moment")?.gender, .masculine)
        XCTAssertEqual(model.gender(of: "moment")?.ending, "ment")
    }

    // A warning names the longest ending behind the guess, never a single letter.
    func testEndingModelNamesTheLongestEnding() throws {
        let features: [[Double]] = [[1.0, 1.0], [1.0, 1.0], [1.0, 1.0], [0.0, 0.0], [0.0, 0.0], [0.0, 0.0]]
        let labels = [1, 1, 1, 0, 0, 0]
        let fit = try LogisticRegression.fit(features: features, labels: labels, learningRate: 0.5, maxIterations: 2000)
        let model = EndingGenderModel(endings: ["e", "ette"], model: fit)
        XCTAssertEqual(model.gender(of: "glimette")?.ending, "ette")

        let letterOnly = EndingGenderModel(endings: ["e", "ment"], model: try tinyModel().model)
        XCTAssertNil(letterOnly.gender(of: "glime")?.ending)
    }

    // A noun with none of the known endings gets no prediction.
    func testEndingModelSilentWithoutEvidence() throws {
        XCTAssertNil(try tinyModel().gender(of: "chat"))
    }

    // The bundled file format round-trips, and a mismatched ending list is rejected.
    func testEndingModelFileFormat() throws {
        let model = try tinyModel()
        let data = try JSONEncoder().encode(model)
        XCTAssertEqual(try JSONDecoder().decode(EndingGenderModel.self, from: data), model)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["endings"] = ["tion"]
        let broken = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(EndingGenderModel.self, from: broken))
    }
}
