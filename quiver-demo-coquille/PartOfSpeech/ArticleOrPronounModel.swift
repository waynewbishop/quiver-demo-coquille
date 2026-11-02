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
import Quiver

/// A Quiver logistic regression that decides whether le, la, les or l' is an
/// article ("la porte est ouverte") or an object pronoun ("je la porte").
///
/// Lexique says what each neighbouring word can be; the model decides what the
/// target word is from those neighbours. Every feature is 1.0 or 0.0, and class 1
/// is pronoun. The feature order is fixed by `features(word:previous:next:afterNext:lexicon:)`
/// and must match the Notebook script that trained it.
///
/// The model is trained in the Quiver Notebook on Universal Dependencies French
/// and bundled as `fr.article-model.json`. Retraining and replacing that file
/// changes predictions without code changes.
nonisolated struct ArticleOrPronounModel: Codable, Equatable, Sendable {

    /// Where the training data came from, and its licence.
    let source: String
    let license: String
    /// The words the model decides about, in feature order.
    let targets: [String]
    /// Subject pronouns, grouped into one feature so je and tu share what il and elle teach.
    let subjectPronouns: [String]
    /// Ne, me, te, se and y, grouped into one feature.
    let objectMarkers: [String]
    /// Frequent words before a target, each its own feature.
    let previousWords: [String]
    /// Frequent words after a target, each its own feature.
    let nextWords: [String]
    /// The trained classifier.
    let model: LogisticRegression

    /// The number of features each Lexique reading set contributes.
    private static let readingCount = 6

    /// The feature count the word lists imply, which must equal the model's.
    private var expectedFeatureCount: Int {
        targets.count + 3 * Self.readingCount + 3 + previousWords.count + nextWords.count
    }

    private enum CodingKeys: String, CodingKey {
        case source, license, targets, subjectPronouns, objectMarkers, previousWords, nextWords, model
    }

    /// Decodes a bundled model, rejecting a file whose word lists don't match its features.
    ///
    /// - Throws: `DecodingError.dataCorrupted` on a mismatch, or any decoding error.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(String.self, forKey: .source)
        license = try container.decode(String.self, forKey: .license)
        targets = try container.decode([String].self, forKey: .targets)
        subjectPronouns = try container.decode([String].self, forKey: .subjectPronouns)
        objectMarkers = try container.decode([String].self, forKey: .objectMarkers)
        previousWords = try container.decode([String].self, forKey: .previousWords)
        nextWords = try container.decode([String].self, forKey: .nextWords)
        model = try container.decode(LogisticRegression.self, forKey: .model)
        guard expectedFeatureCount == model.featureCount else {
            throw DecodingError.dataCorruptedError(
                forKey: .model,
                in: container,
                debugDescription: "Word lists imply \(expectedFeatureCount) features; the model has \(model.featureCount)"
            )
        }
    }

    /// Whether the model has an opinion on `word`; un and une are never pronouns here.
    func decides(_ word: String) -> Bool {
        targets.contains(word)
    }

    /// Returns the probability that `word` is a pronoun, given the words around it.
    ///
    /// Each neighbour is a normalized word, a punctuation mark such as "," or "?",
    /// or `nil` at the start or end of the text.
    func pronounProbability(
        of word: String,
        previous: String?,
        next: String?,
        afterNext: String?,
        lexicon: Lexicon
    ) -> Double {
        let row = features(word: word, previous: previous, next: next, afterNext: afterNext, lexicon: lexicon)
        return model.predictProbabilities([row]).first ?? 0.5
    }

    /// Returns the binary features for one target word, in the trained order.
    func features(
        word: String,
        previous: String?,
        next: String?,
        afterNext: String?,
        lexicon: Lexicon
    ) -> [Double] {
        var row: [Double] = targets.map { word == $0 ? 1.0 : 0.0 }
        row += Self.readings(of: previous, lexicon: lexicon)
        row += Self.readings(of: next, lexicon: lexicon)
        row += Self.readings(of: afterNext, lexicon: lexicon)
        let afterSubject = previous.map(subjectPronouns.contains) ?? false
        row.append(afterSubject ? 1.0 : 0.0)
        row.append(previous.map(objectMarkers.contains) ?? false ? 1.0 : 0.0)
        // Each weight adds on its own, so "porte" counts as a noun whatever comes
        // before it. This one feature fires only for the pair, as in "il la porte".
        let verbAfter = next.map(lexicon.isVerb) ?? false
        row.append(afterSubject && verbAfter ? 1.0 : 0.0)
        row += previousWords.map { previous == $0 ? 1.0 : 0.0 }
        row += nextWords.map { next == $0 ? 1.0 : 0.0 }
        return row
    }

    /// Returns what Lexique says a word can be: verb, infinitive, noun, adjective,
    /// participle, and whether it is punctuation, unknown or missing.
    private static func readings(of word: String?, lexicon: Lexicon) -> [Double] {
        guard let word else { return [0, 0, 0, 0, 0, 1] }
        let isVerb = lexicon.isVerb(word)
        let isNoun = lexicon.noun(word) != nil
        let isAdjective = !lexicon.adjectiveLemmas(of: word).isEmpty
        let isInfinitive = isVerb && ["er", "ir", "re", "oir"].contains { word.hasSuffix($0) }
        let isPunctuation = word.unicodeScalars.allSatisfy(CharacterSet.punctuationCharacters.union(.symbols).contains)
        let isKnown = isVerb || isNoun || isAdjective
        return [
            isVerb ? 1 : 0,
            isInfinitive ? 1 : 0,
            isNoun ? 1 : 0,
            isAdjective ? 1 : 0,
            lexicon.participles(word).isEmpty ? 0 : 1,
            isPunctuation || !isKnown ? 1 : 0
        ]
    }
}
