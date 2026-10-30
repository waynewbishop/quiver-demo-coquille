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

    /// Builds the pipeline: spelling first, then each of the grammar's rules as its own filter.
    init(
        spellChecker: any SpellChecker,
        grammar: any Grammar,
        lexicon: Lexicon,
        explanations: ExplanationTemplates
    ) {
        let spelling = OrthographicFilter(spellChecker: spellChecker, lexicon: lexicon, explanations: explanations)
        filters = [spelling] + grammar.rules.map { GrammarRuleFilter(rule: $0) }
    }

    /// Builds a pipeline from any filters, in the order they should run.
    init(filters: [any LinguisticFilter]) {
        self.filters = filters
    }

    /// Returns every issue in `text` from the filters at or below `level`, ordered by
    /// position, with no two issues overlapping. The default level runs every filter.
    func lint(_ text: String, through level: CefrLevel = .c2) -> [Issue] {
        let context = LintContext(text: text)
        let active = filters.filter { $0.targetLevel <= level }
        return ResolutionMatrix.resolve(active.flatMap { $0.evaluate(context) })
    }
}
