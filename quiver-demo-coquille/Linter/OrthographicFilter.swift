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

/// The orthographic layer: system spelling, Lexique validation and Quiver suggestion ranking.
struct OrthographicFilter: LinguisticFilter {
    let identifier = "orthography.spelling"
    let layer = LinguisticLayer.orthography
    let targetLevel = CefrLevel.a1

    let spellChecker: any SpellChecker
    let lexicon: Lexicon
    let explanations: ExplanationTemplates

    /// Turns misspellings into issues, skipping any word the lexicon knows.
    ///
    /// Only guesses the lexicon knows are offered: the Mac's French spellchecker also
    /// returns English words, so "fro" would otherwise become "from". A misspelling
    /// with no French guess is still underlined, as a warning with no fix: seeing the
    /// mistake comes first, and a name the system doesn't know never blocks play.
    func evaluate(_ context: LintContext) -> [Issue] {
        spellChecker.misspellings(in: context.text).compactMap { misspelling in
            let normalized = FrenchTokenizer.normalize(misspelling.word)
            guard !lexicon.contains(normalized) else { return nil }
            let frenchGuesses = misspelling.guesses.filter { lexicon.contains(FrenchTokenizer.normalize($0)) }
            // Quiver ranks the French guesses by letter-pair similarity to the typo.
            guard let best = SuggestionRanker.ranked(frenchGuesses, for: misspelling.word).first else {
                return unknownWordIssue(misspelling)
            }
            let explanation = explanations.render(.spelling, ["word": misspelling.word, "suggestion": best])
            return Issue(
                kind: .spelling,
                severity: .error,
                offset: misspelling.offset,
                length: misspelling.word.count,
                original: misspelling.word,
                replacement: best,
                reason: explanation.reason,
                hint: explanation.hint,
                source: "System spellcheck · ranked by Quiver"
            )
        }
    }

    /// A misspelling with no French guess: the word is flagged and the learner finds the fix.
    private func unknownWordIssue(_ misspelling: Misspelling) -> Issue {
        let explanation = explanations.render(.unknownWord, ["word": misspelling.word])
        return Issue(
            kind: .spelling,
            severity: .warning,
            offset: misspelling.offset,
            length: misspelling.word.count,
            original: misspelling.word,
            replacement: nil,
            reason: explanation.reason,
            hint: explanation.hint,
            source: "System spellcheck"
        )
    }
}
