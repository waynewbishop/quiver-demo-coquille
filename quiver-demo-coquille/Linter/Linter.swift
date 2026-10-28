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

/// Runs spellcheck and the grammar rules over the learner's text and merges the results.
struct Linter {

    let spellChecker: any SpellChecker
    let grammar: any Grammar
    let lexicon: Lexicon
    let explanations: ExplanationTemplates

    /// Returns every issue in `text`, ordered by position, with no two issues overlapping.
    func lint(_ text: String) -> [Issue] {
        resolveOverlaps(spellingIssues(in: text) + grammar.check(text))
    }

    /// Turns misspellings into issues, skipping any word the lexicon knows.
    ///
    /// Only guesses the lexicon knows are offered: the Mac's French spellchecker also
    /// returns English words, so "fro" would otherwise become "from". A misspelling
    /// with no French guess is still underlined, as a warning with no fix: seeing the
    /// mistake comes first, and a name the system doesn't know never blocks play.
    private func spellingIssues(in text: String) -> [Issue] {
        spellChecker.misspellings(in: text).compactMap { misspelling in
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

    /// Keeps one issue per span: the more severe one, or the earlier-raised one on a tie.
    private func resolveOverlaps(_ issues: [Issue]) -> [Issue] {
        var kept: [Issue] = []
        // Sort by severity, then by input position, since Swift's sort isn't guaranteed stable.
        let ordered = issues.enumerated().sorted { left, right in
            rank(left.element) != rank(right.element) ? rank(left.element) < rank(right.element) : left.offset < right.offset
        }
        for (_, issue) in ordered {
            let overlaps = kept.contains { $0.range.overlaps(issue.range) }
            if !overlaps {
                kept.append(issue)
            }
        }
        return kept.sorted { $0.offset < $1.offset }
    }

    /// Orders issues for overlap resolution: errors before warnings before suggestions.
    private func rank(_ issue: Issue) -> Int {
        switch issue.severity {
        case .error: 0
        case .warning: 1
        case .suggestion: 2
        }
    }
}
