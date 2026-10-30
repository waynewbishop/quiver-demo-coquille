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

import Foundation

/// Runs a small, ordered collection of linguistic filters and resolves their issues.
struct Linter {

    let filters: [any LinguisticFilter]

    /// Keeps the existing app and test setup while introducing the filter pipeline.
    init(
        spellChecker: any SpellChecker,
        grammar: any Grammar,
        lexicon: Lexicon,
        explanations: ExplanationTemplates
    ) {
        filters = [
            OrthographicFilter(spellChecker: spellChecker, lexicon: lexicon, explanations: explanations),
            LocalGrammarFilter(grammar: grammar)
        ]
    }

    init(filters: [any LinguisticFilter]) {
        self.filters = filters
    }

    /// Returns every issue in `text`, ordered by position, with no two issues overlapping.
    func lint(_ text: String) -> [Issue] {
        let context = LintContext(text: text)
        return ResolutionMatrix.resolve(filters.flatMap { $0.evaluate(context) })
    }
}
