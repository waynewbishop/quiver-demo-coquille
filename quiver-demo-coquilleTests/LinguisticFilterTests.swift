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

@MainActor
final class LinguisticFilterTests: XCTestCase {

    /// Reports no misspellings, so a test sees only the grammar filters.
    private struct SilentSpellChecker: SpellChecker {
        func misspellings(in text: String) -> [Misspelling] { [] }
    }

    /// Builds the default pipeline over the bundled pack with no spelling issues.
    private func linter() throws -> Linter {
        let pack = try LanguagePack.french()
        return Linter(
            spellChecker: SilentSpellChecker(),
            grammar: pack.grammar,
            lexicon: pack.lexicon,
            explanations: pack.explanations
        )
    }

    // The default pipeline runs spelling first, then each grammar rule as its own filter.
    func testDefaultPipelineDescribesItsFilters() throws {
        let filters = try linter().filters
        XCTAssertEqual(filters.map(\.identifier), [
            "orthography.spelling",
            "grammar.gender", "grammar.gender.predicted", "grammar.contraction", "grammar.elision", "grammar.accent",
            "grammar.auxiliary", "grammar.subjunctive", "grammar.objectPronoun", "grammar.relativePronoun", "grammar.conjugation", "grammar.siClause", "grammar.participle",
            "grammar.article", "grammar.articleNumber", "grammar.agreement", "grammar.lookAlike", "grammar.wordChoice",
            "grammar.negation", "grammar.idiom", "grammar.meaning", "grammar.etOrEst",
            "grammar.preposition", "grammar.sentenceCapital", "grammar.lowercase", "grammar.number"
        ])
        XCTAssertEqual(Set(filters.map(\.layer)), Set(LinguisticLayer.allCases))
    }

    // Levels order from beginner to mastery, as declared.
    func testCefrLevelsAreOrdered() {
        XCTAssertEqual(CefrLevel.allCases.sorted(), CefrLevel.allCases)
        XCTAssertLessThan(CefrLevel.a1, .b1)
        XCTAssertGreaterThan(CefrLevel.c2, .c1)
    }

    // An A1 learner sees article gender but not the B2 idiom suggestion.
    func testLintSkipsFiltersAboveTheLearnersLevel() throws {
        let linter = try linter()
        let text = "Une fromage. Ça fait du sens."
        XCTAssertEqual(linter.lint(text, through: .a1).map(\.kind), [.gender])
        XCTAssertEqual(linter.lint(text).map(\.kind), [.gender, .idiom])
    }

    // Running the rules as separate filters finds the same issues as the grammar's own check.
    func testRuleFiltersMatchTheGrammar() throws {
        let pack = try LanguagePack.french()
        let text = "Nous avons acheté une fromage et des pommes rouge à le marché."
        XCTAssertEqual(try linter().lint(text), ResolutionMatrix.resolve(pack.grammar.check(text)))
    }

    // Every filter in a pass sees the same source text and token snapshot.
    func testLintContextKeepsSourceAndTokensTogether() {
        let context = LintContext(text: "Une fromage.")
        XCTAssertEqual(context.text, "Une fromage.")
        XCTAssertEqual(context.tokens.map(\.normalized), ["une", "fromage"])
    }
}
