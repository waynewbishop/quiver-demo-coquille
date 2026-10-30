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

    // The default pipeline exposes each filter's role without changing the existing setup.
    func testDefaultPipelineDescribesItsFilters() throws {
        let pack = try LanguagePack.french()
        let linter = Linter(
            spellChecker: SystemSpellChecker(language: pack.spellCheckerLanguage),
            grammar: pack.grammar,
            lexicon: pack.lexicon,
            explanations: pack.explanations
        )
        XCTAssertEqual(linter.filters.map(\.identifier), ["orthography.spelling", "grammar.local"])
        XCTAssertEqual(linter.filters.map(\.layer), [.orthography, .localMorphosyntax])
        XCTAssertEqual(linter.filters.map(\.targetLevel), [.a1, .a2])
    }

    // Every filter in a pass sees the same source text and token snapshot.
    func testLintContextKeepsSourceAndTokensTogether() {
        let context = LintContext(text: "Une fromage.")
        XCTAssertEqual(context.text, "Une fromage.")
        XCTAssertEqual(context.tokens.map(\.normalized), ["une", "fromage"])
    }
}
