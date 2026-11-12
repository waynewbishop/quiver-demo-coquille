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

/// Every listed phrase Coquille checks, from `fr.patterns.json`: look-alikes, word choices,
/// idioms and meaning questions in one format, matched by one trie.
///
/// A pattern word is one of three things:
///
/// - a plain word, matched as written: `cava`, `une`, `décision`;
/// - `@verb`, any form of that verb, as Lexique lists it: `@faire` matches faire, fais,
///   fait and faisons, so one entry covers every person and tense. `@aimer:ip` matches only
///   the present indicative, so "j'aimerais du café" stays correct;
/// - `$class`, any word in one of the file's classes: `$month` matches janvier through décembre.
///
/// In a fix, `@verb` stands for the learner's verb in the same person and tense, so
/// "@faire une décision" → "@prendre une décision" turns "fait" into "prend", or "pris"
/// after avoir. `$class` repeats the learner's own word.
nonisolated struct PhrasePatterns: Decodable, Sendable {

    /// Named word lists that `$class` pattern words refer to.
    var classes: [String: [String]] = [:]
    var entries: [PhrasePattern] = []
    /// Each country's name and the article it takes, such as "Canada": "le", which settles
    /// its preposition: au Canada, en France, aux États-Unis, en Iran.
    var countries: [String: String] = [:]

    /// The entries of one kind, in file order.
    func entries(of kind: PhrasePattern.Kind) -> [PhrasePattern] {
        entries.filter { $0.kind == kind }
    }

    /// Returns the classes that contain `word`, as `$class` keys.
    func classKeys(of word: String) -> [String] {
        classes.compactMap { name, words in words.contains(word) ? "$" + name : nil }
    }
}

/// One listed phrase and what to do when the learner writes it.
nonisolated struct PhrasePattern: Decodable, Equatable, Sendable {

    /// What the phrase is, which decides the issue's kind, severity and card.
    enum Kind: String, Decodable, Sendable {
        /// Each word is French, but together they're wrong ("comment cava"): an error.
        case lookAlike
        /// An English pattern that is wrong in French ("je suis faim"): an error.
        case wordChoice
        /// Correct French with a more natural wording ("ça fait du sens"): a suggestion.
        case idiom
        /// Correct French that may not mean what the learner meant ("pas encore"): a question.
        case meaning
        /// The wrong preposition, or a missing one ("dépend sur", "téléphone ma mère"): an error.
        case preposition
    }

    let kind: Kind
    /// The pattern words as the learner writes them, such as "@faire une décision".
    let match: String
    /// The wording to offer, with the same pattern words; `nil` for a meaning question.
    var fix: String? = nil
    /// Every wording a meaning question offers, the phrase itself included.
    var choices: [Choice]? = nil
    /// Words after which the phrase is correct French, as "il cava".
    var unlessAfter: [String]? = nil
    /// Words that must come right before the phrase; `nil` means any.
    var onlyAfter: [String]? = nil
    /// Words that make the phrase correct French when they follow it, as in "cava un trou".
    var unlessBefore: [String]? = nil
    /// Whether the phrase is wrong only at the end of a clause, as in "et tu ?".
    var onlyAtClauseEnd: Bool? = nil
    /// Whether to stay silent before a past participle, as in "je n'ai pas encore fini".
    var unlessBeforeParticiple: Bool? = nil
    /// Whether the phrase is wrong only before an infinitive, as in "essaie à faire".
    var onlyBeforeInfinitive: Bool? = nil
    /// Whether to stay silent before an infinitive, as in "j'attends pour voir".
    var unlessBeforeInfinitive: Bool? = nil
    /// Why the phrase is flagged, without the answer.
    let note: String

    /// Whether the phrase swaps être for avoir, as "@être $avoirNoun" → "@avoir $avoirNoun"
    /// does, so its card teaches the avoir expression rather than a general word choice.
    var swapsEtreForAvoir: Bool {
        match.hasPrefix("@être ") && fix?.hasPrefix("@avoir ") == true
    }

    /// The pattern words of `match`, split as the tokenizer splits text.
    var matchWords: [String] {
        Self.words(of: match)
    }

    /// Splits a pattern into words, keeping `@verb:ip` and `$class` words whole.
    static func words(of pattern: String) -> [String] {
        pattern.split(separator: " ").flatMap { part -> [String] in
            let word = String(part)
            if word.hasPrefix("@") || word.hasPrefix("$") { return [word] }
            return FrenchTokenizer.tokens(in: word).map(\.normalized)
        }
    }
}
