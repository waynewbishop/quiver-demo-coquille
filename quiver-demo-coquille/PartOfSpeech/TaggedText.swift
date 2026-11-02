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

/// The learner's words with what the part-of-speech layer decided about the ambiguous ones.
///
/// Most French words have one reading, and Lexique settles them. The tagger decides the
/// common two-way cases once per lint pass, and every rule reads the result instead of
/// working out its neighbours' roles by hand. A word the tagger wasn't asked about, or
/// couldn't settle, has no verdict, and rules treat that as "not sure".
nonisolated struct TaggedText: Sendable {

    /// Where one token sits in `sentences`.
    struct Place: Equatable, Sendable {
        let sentence: Int
        let index: Int
    }

    let tokens: [Token]
    /// The text as the treebank models saw it in training: punctuation is a word of its
    /// own, a sentence keeps its closing mark, and a line break ends a sentence.
    let sentences: [[String]]
    /// Where each token landed in `sentences`.
    let places: [Place]
    /// Whether le, la, les, l', un or une at each index may be an object pronoun, as in
    /// "je le porte", so no rule should treat it as an article.
    var mayBePronoun: [Bool]
    /// The probability that each word Lexique lists as both an adjective and a noun is an
    /// adjective here; `nil` for every other word.
    var adjectiveProbability: [Double?]
    /// The probability that each form of avoir or être is a helper verb, as in "il a
    /// mangé", rather than a main verb, as in "il a faim"; `nil` for every other word.
    var helperProbability: [Double?]
    /// The probability that each word Lexique lists as both a noun and a verb form is the
    /// verb here; `nil` for every other word.
    var verbProbability: [Double?]

    /// Punctuation that ends a sentence, after which the models see nothing before a word.
    static let sentenceEnds: Set<String> = [".", "!", "?", "…"]

    /// Wraps tokens with no verdicts yet.
    init(untagged tokens: [Token]) {
        self.tokens = tokens
        var sentences: [[String]] = []
        var places: [Place] = []
        var current: [String] = []
        for token in tokens {
            places.append(Place(sentence: sentences.count, index: current.count))
            current.append(token.normalized)
            switch Self.mark(in: token.gap) {
            case .none:
                continue
            case .some("\n"):
                sentences.append(current)
                current = []
            case .some(let mark):
                current.append(mark)
                if Self.sentenceEnds.contains(mark) {
                    sentences.append(current)
                    current = []
                }
            }
        }
        sentences.append(current)
        self.sentences = sentences
        self.places = places
        mayBePronoun = Array(repeating: false, count: tokens.count)
        adjectiveProbability = Array(repeating: nil, count: tokens.count)
        helperProbability = Array(repeating: nil, count: tokens.count)
        verbProbability = Array(repeating: nil, count: tokens.count)
    }

    /// Returns the words around token `index` in its sentence, from `before` words back to
    /// `after` words on, with `nil` past either edge of the sentence.
    func window(at index: Int, before: Int = 2, after: Int = 2) -> [String?] {
        let place = places[index]
        let words = sentences[place.sentence]
        return (-before...after).map { offset in
            words.indices.contains(place.index + offset) ? words[place.index + offset] : nil
        }
    }

    /// Whether the tagger is at least `certainty` sure that token `index` is an adjective.
    func isAdjective(_ index: Int, certainty: Double) -> Bool {
        (adjectiveProbability[index] ?? 0) >= certainty
    }

    /// Whether the tagger is at least `certainty` sure that token `index` is a noun.
    func isNoun(_ index: Int, certainty: Double) -> Bool {
        adjectiveProbability[index].map { 1 - $0 >= certainty } ?? false
    }

    /// Whether the tagger is at least `certainty` sure that token `index` is a helper verb.
    func isHelperVerb(_ index: Int, certainty: Double) -> Bool {
        (helperProbability[index] ?? 0) >= certainty
    }

    /// Whether the tagger is at least `certainty` sure that token `index` is a noun, not a verb form.
    func isNounNotVerb(_ index: Int, certainty: Double) -> Bool {
        verbProbability[index].map { 1 - $0 >= certainty } ?? false
    }

    /// Returns the first mark in a gap, "\n" for a line break, or `nil` when only spaces separate the words.
    static func mark(in gap: String) -> String? {
        for character in gap {
            if character.isNewline { return "\n" }
            if character.isWhitespace { continue }
            return String(character)
        }
        return nil
    }
}
