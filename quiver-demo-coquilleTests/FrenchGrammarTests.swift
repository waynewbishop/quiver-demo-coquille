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

/// Exercises the French rules against the real bundled lexicon.
final class FrenchGrammarTests: XCTestCase {

    private static let pack: LanguagePack? = try? LanguagePack.french()

    /// Returns the bundled grammar, failing the test if the pack didn't load.
    private func grammar() throws -> any Grammar {
        try XCTUnwrap(Self.pack, "The French language pack failed to load").grammar
    }

    /// Returns each issue as "original → replacement".
    private func fixes(_ text: String) throws -> [String] {
        try grammar().check(text).map { "\($0.original) → \($0.replacement ?? "")" }
    }

    // MARK: - The mockup sentence

    // The design's example paragraph: every grammar error it shows, known nouns as errors.
    func testMockupSentence() throws {
        let text = "Nous avons acheté une fromage et des pommes rouge. Le boulangère était très gentille, et la pain sentait bon."
        let issues = try grammar().check(text)
        XCTAssertEqual(issues.map { "\($0.original) → \($0.replacement ?? "")" }, [
            "une fromage → un fromage",
            "rouge → rouges",
            "Le boulangère → La boulangère",
            "la pain → le pain"
        ])
        XCTAssertTrue(issues.allSatisfy { $0.severity == .error })
        XCTAssertEqual(issues[0].reason, "fromage is masculine, so the article is un.")
        XCTAssertEqual(issues[1].reason, "The adjective must agree with pommes, which is plural.")
        // The hint names the rule but leaves the fix to the learner.
        XCTAssertEqual(issues[0].hint, "fromage is masculine.")
    }

    // The corrected paragraph raises nothing.
    func testCorrectFrenchPasses() throws {
        let text = "Nous avons acheté un fromage et des pommes rouges. La boulangère était très gentille, et le pain sentait bon."
        XCTAssertEqual(try fixes(text), [])
    }

    // MARK: - Article gender

    // Le and la before a verb are object pronouns, not articles.
    func testObjectPronounsAreNotArticles() throws {
        XCTAssertEqual(try fixes("Je le porte tous les jours."), [])
        XCTAssertEqual(try fixes("Il a décidé de le faire."), [])
        XCTAssertEqual(try fixes("Je viens pour la voir."), [])
    }

    // A noun Lexique lists with both genders is never flagged.
    func testAmbiguousGenderIsSkipped() throws {
        XCTAssertEqual(try fixes("Le livre coûte une livre."), [])
    }

    // An adjective between article and noun takes the noun's gender, so the article isn't judged on it.
    func testAdjectiveBeforeNounIsSkipped() throws {
        XCTAssertEqual(try fixes("Une petite maison."), [])
    }

    // Before a vowel the article elides, which is outside the gender rule.
    func testElisionContextIsSkipped() throws {
        XCTAssertEqual(try fixes("Je vois la arbre."), [])
    }

    // MARK: - Contractions

    // à + le and de + les contract before a noun.
    func testContractions() throws {
        XCTAssertEqual(try fixes("Je vais à le marché."), ["à le → au"])
        XCTAssertEqual(try fixes("Il parle de les enfants."), ["de les → des"])
    }

    // Le and les before a verb are pronouns and never contract.
    func testNoContractionBeforeVerb() throws {
        XCTAssertEqual(try fixes("Il essaie de les voir."), [])
    }

    // MARK: - Agreement

    // Adjectives agree in gender as well as number.
    func testGenderAgreement() throws {
        let issues = try grammar().check("C'est une maison grand.")
        XCTAssertEqual(issues.map(\.replacement), ["grande"])
        XCTAssertEqual(issues.first?.reason, "The adjective must agree with maison, which is feminine.")
    }

    // Invariable colour adjectives such as marron never change form.
    func testInvariableAdjectivesPass() throws {
        XCTAssertEqual(try fixes("J'aime les chaussures marron."), [])
    }

    // MARK: - Negation

    // A clause-final "il dort plus" is a warning that restores ne.
    func testMissingNeIsAWarning() throws {
        let issues = try grammar().check("Lui, il dort plus.")
        XCTAssertEqual(issues.map { "\($0.original) → \($0.replacement ?? "")" }, ["dort plus → ne dort plus"])
        XCTAssertEqual(issues.first?.severity, .warning)
        XCTAssertEqual(issues.first.map { $0.severity.blocksPlayback }, false)
    }

    // Before a vowel, ne elides, and j' becomes je.
    func testMissingNeElides() throws {
        XCTAssertEqual(try fixes("J'aime plus."), ["J'aime plus → Je n'aime plus"])
    }

    // Written negation, comparatives and "plus tard" pass.
    func testValidPlusPasses() throws {
        XCTAssertEqual(try fixes("Il ne dort plus."), [])
        XCTAssertEqual(try fixes("Il dort plus tard."), [])
        XCTAssertEqual(try fixes("Il dort plus que moi."), [])
    }

    // MARK: - Look-alikes

    // Words that are each French but wrong together are errors, fixed to ça va.
    func testCaVaLookAlikes() throws {
        XCTAssertEqual(try fixes("Bonjour, comment cava?"), ["cava → ça va"])
        XCTAssertEqual(try fixes("Sa va bien."), ["Sa va → Ça va"])
        XCTAssertEqual(try fixes("Ça vas bien?"), ["Ça vas → Ça va"])
        XCTAssertEqual(try fixes("Comment sava?"), ["sava → ça va"])
        let issue = try XCTUnwrap(grammar().check("Comment cava?").first)
        XCTAssertEqual(issue.severity, .error)
        XCTAssertEqual(issue.hint, "cava is a past form of caver, “to dig,” as in il cava un trou.")
    }

    // After a subject pronoun, cava is the verb caver, which is correct French.
    func testCavaAfterSubjectIsTheVerb() throws {
        XCTAssertEqual(try fixes("Il cava un trou."), [])
        XCTAssertEqual(try fixes("Ça va bien, merci."), [])
    }

    // MARK: - Idioms

    // A correct but unidiomatic phrase gets a suggestion, never an error.
    func testIdiomSuggestion() throws {
        let issues = try grammar().check("C'est bon pour ta santé.")
        XCTAssertEqual(issues.map(\.replacement), ["bon pour la santé"])
        XCTAssertEqual(issues.first?.severity, .suggestion)
    }

    // MARK: - Model predictions

    /// Always predicts one gender for any word, so the warning path can be tested without a trained model.
    private struct FixedPredictor: GenderPredictor {
        let prediction: GenderPrediction
        func gender(of noun: String) -> GenderPrediction? { prediction }
    }

    // A confident model guess on an unknown noun is a warning, never an error.
    func testPredictionOnUnknownNounIsAWarning() throws {
        let pack = try XCTUnwrap(Self.pack)
        let predictor = FixedPredictor(prediction: GenderPrediction(gender: .feminine, probability: 0.93, ending: "tion"))
        let grammar = FrenchGrammar(lexicon: pack.lexicon, idioms: [], lookAlikes: [], explanations: pack.explanations, genderPredictor: predictor)

        let issues = grammar.check("C'est un frobnication.")
        XCTAssertEqual(issues.map { "\($0.original) → \($0.replacement ?? "")" }, ["un frobnication → une frobnication"])
        XCTAssertEqual(issues.first?.severity, .warning)
        XCTAssertEqual(issues.first?.source, "Quiver prediction · ending -tion")
    }

    // Known nouns are answered by the lexicon, so the model is never consulted for them.
    func testPredictionNeverOverridesLexicon() throws {
        let pack = try XCTUnwrap(Self.pack)
        let predictor = FixedPredictor(prediction: GenderPrediction(gender: .feminine, probability: 0.99, ending: "ette"))
        let grammar = FrenchGrammar(lexicon: pack.lexicon, idioms: [], lookAlikes: [], explanations: pack.explanations, genderPredictor: predictor)
        XCTAssertEqual(grammar.check("Un squelette.").count, 0)
    }

    // An unsure guess raises nothing.
    func testLowConfidencePredictionIsSilent() throws {
        let pack = try XCTUnwrap(Self.pack)
        let predictor = FixedPredictor(prediction: GenderPrediction(gender: .feminine, probability: 0.6, ending: "e"))
        let grammar = FrenchGrammar(lexicon: pack.lexicon, idioms: [], lookAlikes: [], explanations: pack.explanations, genderPredictor: predictor)
        XCTAssertEqual(grammar.check("Un frobnication.").count, 0)
    }
}
