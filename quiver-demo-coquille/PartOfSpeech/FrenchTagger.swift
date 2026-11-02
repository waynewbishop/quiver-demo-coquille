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

/// The part-of-speech layer: decides the common two-way ambiguities once per lint pass.
///
/// Measured on Lexique 3.83, about 29% of running French has more than one reading, and
/// 93.5% of that is two-way. The largest cases each get a binary decider: article or
/// pronoun (le, la, les, l'), adjective or noun (difficile, malade), and helper or main
/// verb (the a of "il a mangé" or of "il a faim"). Each decider is optional; without it,
/// its words simply get no verdict.
nonisolated struct FrenchTagger: Sendable {

    let lexicon: Lexicon
    /// Decides whether le, la, les or l' is an article or a pronoun; `nil` leaves the hand rule alone.
    var articleOrPronoun: ContextDecider? = nil
    /// Decides whether a word Lexique lists as both is an adjective or a noun.
    var adjectiveOrNoun: ContextDecider? = nil
    /// Decides whether a form of avoir or être is a helper verb or a main verb.
    var helperOrMain: ContextDecider? = nil
    /// Decides whether a word Lexique lists as both a noun and a verb form is the verb.
    var nounOrVerb: ContextDecider? = nil

    /// How sure the article model must be that a word is an article before a rule
    /// treats it as one. Below this the word may be a pronoun, so the rules stay silent.
    static let articleCertainty = 0.95

    /// The words that can be an article, which every article rule checks first.
    private static let articleWords: Set<String> = ["le", "la", "les", "l'", "un", "une"]

    /// Words after which le or la is an object pronoun, as in "je le porte".
    private static let pronounContext: Set<String> = [
        "je", "j'", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles",
        "ne", "n'", "me", "m'", "te", "t'", "se", "s'", "y"
    ]

    /// Prepositions that take an infinitive, as in "pour le faire".
    private static let infinitivePrepositions: Set<String> = [
        "pour", "de", "d'", "à", "sans", "après", "avant", "par"
    ]

    /// Returns the tokens with every ambiguity the deciders could settle.
    func tag(_ tokens: [Token]) -> TaggedText {
        var text = TaggedText(untagged: tokens)
        for (index, token) in tokens.enumerated() {
            let word = token.normalized
            if Self.articleWords.contains(word) {
                text.mayBePronoun[index] = mayBePronoun(in: text, at: index)
            }
            if let adjectiveOrNoun, lexicon.noun(word) != nil, !lexicon.adjectiveLemmas(of: word).isEmpty {
                text.adjectiveProbability[index] = adjectiveOrNoun.probability(of: text.window(at: index), lexicon: lexicon)
            }
            if let helperOrMain, helperOrMain.targets.contains(word) {
                text.helperProbability[index] = helperOrMain.probability(of: text.window(at: index), lexicon: lexicon)
            }
            if let nounOrVerb, lexicon.noun(word) != nil, lexicon.isVerb(word) {
                text.verbProbability[index] = nounOrVerb.probability(of: text.window(at: index), lexicon: lexicon)
            }
        }
        return text
    }

    /// Whether le or la at `index` may be an object pronoun.
    ///
    /// The hand rule's pronoun verdict always stands. With a model, an article also needs
    /// the model to be sure of it, so "qui le porte ?" stays silent where the hand rule
    /// alone would call "le porte" a gender error.
    private func mayBePronoun(in text: TaggedText, at index: Int) -> Bool {
        if handRuleSaysPronoun(text.tokens, at: index) { return true }
        guard let articleOrPronoun, articleOrPronoun.targets.contains(text.tokens[index].normalized) else { return false }
        let window = text.window(at: index)
        // An object pronoun follows its subject, so a sentence never opens with one:
        // the three training treebanks start 4,604 sentences with le, la, les or l',
        // every one an article. The model is unsure of "Le voiture est rouge" only
        // because Lexique also lists voiture as a form of voiturer.
        guard window[1] != nil else { return false }
        return articleOrPronoun.probability(of: window, lexicon: lexicon) > 1.0 - Self.articleCertainty
    }

    /// The hand rule: le or la before a verb is a pronoun after a subject or object
    /// pronoun, or after a preposition when the verb is an infinitive.
    private func handRuleSaysPronoun(_ tokens: [Token], at index: Int) -> Bool {
        guard index > 0, index + 1 < tokens.count else { return false }
        let word = tokens[index + 1].normalized
        guard lexicon.isVerb(word) else { return false }
        let previous = tokens[index - 1].normalized
        if Self.pronounContext.contains(previous) { return true }
        let isInfinitive = ["er", "ir", "re", "oir"].contains { word.hasSuffix($0) }
        return isInfinitive && Self.infinitivePrepositions.contains(previous)
    }
}
