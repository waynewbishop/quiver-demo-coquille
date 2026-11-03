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
    ///
    /// The system checks an elided word whole, so "l'apres-midi" comes back with the
    /// guess "l'après-midi". The lexicon has neither the article nor every compound, so
    /// words are looked up as `knows(_:)` and `isFrenchGuess(_:)` describe.
    func evaluate(_ context: LintContext) -> [Issue] {
        spellChecker.misspellings(in: context.text).compactMap { misspelling in
            guard !knows(misspelling.word) else { return nil }
            let frenchGuesses = misspelling.guesses.filter(isFrenchGuess)
            // Quiver ranks the French guesses by letter-pair similarity to the typo.
            guard let best = SuggestionRanker.ranked(frenchGuesses, for: misspelling.word).first else {
                return unknownWordIssue(misspelling)
            }
            let explanation = explanations.render(.spelling, [
                "word": misspelling.word,
                "suggestion": best,
                "where": Self.changedPart(of: misspelling.word, toReach: best)
            ])
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

    /// Where `word` must change to become `suggestion`, as the hint names it: "the accents",
    /// "the ending", "the start" or "the middle".
    ///
    /// The hint points the learner at the part to rework without giving the answer,
    /// which stays behind Show fix.
    static func changedPart(of word: String, toReach suggestion: String) -> String {
        let typo = Array(word.lowercased())
        let fix = Array(suggestion.lowercased())
        let unaccented: (String) -> String = { $0.folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr")).lowercased() }
        if typo != fix && unaccented(word) == unaccented(suggestion) {
            return "the accents"
        }

        var sharedStart = 0
        while sharedStart < min(typo.count, fix.count) && typo[sharedStart] == fix[sharedStart] {
            sharedStart += 1
        }
        var sharedEnd = 0
        while sharedEnd < min(typo.count, fix.count) - sharedStart
                && typo[typo.count - 1 - sharedEnd] == fix[fix.count - 1 - sharedEnd] {
            sharedEnd += 1
        }

        // The letters of the typo that differ run from `sharedStart` up to `changeEnd`.
        let changeEnd = typo.count - sharedEnd
        if sharedStart >= typo.count * 2 / 3 {
            return "the ending"
        } else if changeEnd <= (typo.count + 2) / 3 {
            return "the start"
        } else {
            return "the middle"
        }
    }

    /// The articles and pronouns French elides before a vowel, as in l'école and jusqu'ici.
    static let elisions: Set<String> = [
        "l", "d", "j", "m", "t", "s", "n", "c", "qu", "jusqu", "lorsqu", "puisqu", "quoiqu"
    ]

    /// `word`, lowercased, with any elided article or pronoun in front set aside: "L'école" becomes "école".
    static func withoutElision(_ word: String) -> String {
        let normalized = FrenchTokenizer.normalize(word)
        guard let apostrophe = normalized.firstIndex(of: "'") else { return normalized }
        let rest = normalized[normalized.index(after: apostrophe)...]
        guard elisions.contains(String(normalized[..<apostrophe])), !rest.isEmpty else { return normalized }
        return String(rest)
    }

    /// Whether the lexicon knows `word` as written or once its elision is set aside.
    private func knows(_ word: String) -> Bool {
        lexicon.contains(FrenchTokenizer.normalize(word)) || lexicon.contains(Self.withoutElision(word))
    }

    /// Whether a system guess is French: a word the lexicon knows, or a compound whose
    /// every part it knows, as in après-midi, which Lexique leaves out.
    ///
    /// Compounds are accepted part by part only as guesses, which the system already
    /// knows as words; a typed compound is still checked whole.
    private func isFrenchGuess(_ guess: String) -> Bool {
        if knows(guess) { return true }
        let parts = Self.withoutElision(guess).split(separator: "-")
        guard parts.count > 1 else { return false }
        return parts.allSatisfy { lexicon.contains(String($0)) }
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
