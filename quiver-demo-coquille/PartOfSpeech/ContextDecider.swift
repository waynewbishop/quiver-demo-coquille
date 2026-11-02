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

/// A Quiver logistic regression that settles one two-way ambiguity from the five words
/// around a word: two before it, the word itself, and two after.
///
/// Every decider shares one feature recipe, so a new ambiguity is a new JSON file, not new
/// code. The file lists the word lists the features are built from, and the app rebuilds
/// the feature names from them and checks them against the names saved at training time,
/// so a file trained with a different recipe is refused instead of mis-read.
///
/// The deciders are trained in the Quiver Notebook (`coquille-part-of-speech-model.swift`)
/// on Universal Dependencies French. Class 1 is `positive`, class 0 is `negative`.
nonisolated struct ContextDecider: Decodable, Sendable {

    /// A set of words checked at one place in the window, such as determiners just before.
    struct Group: Decodable, Equatable, Sendable {
        let name: String
        /// Where in the window the word sits: -2 and -1 before, 1 and 2 after.
        let offset: Int
        let words: [String]
    }

    /// The ambiguity this decider settles, such as "adjective-or-noun".
    let name: String
    let source: String
    let license: String
    /// What class 1 means, such as "adjective".
    let positive: String
    /// What class 0 means, such as "noun".
    let negative: String
    /// Words frequent enough in training to carry a feature of their own.
    let targets: [String]
    let groups: [Group]
    /// Frequent words just before a target, each its own feature.
    let previousWords: [String]
    /// Frequent words just after a target, each its own feature.
    let nextWords: [String]
    /// Pairs of base features that also count together, such as a determiner before and a noun after.
    let pairs: [[String]]
    let model: LogisticRegression

    /// For each pair, the positions of its two base features in the row.
    private let pairIndices: [(Int, Int)]
    private let groupSets: [Set<String>]

    /// The names of the six Lexique readings each window word contributes.
    private static let readingNames = ["verb", "infinitive", "noun", "adjective", "participle", "other"]
    /// The window positions and the names their features carry.
    private static let positions = [(-2, "prev2"), (-1, "prev"), (0, "word"), (1, "next"), (2, "next2")]

    private enum CodingKeys: String, CodingKey {
        case name, source, license, positive, negative, targets, groups, previousWords, nextWords, pairs, featureNames, model
    }

    /// Decodes a decider, refusing a file whose saved feature names differ from the ones its
    /// word lists produce here.
    ///
    /// - Throws: `DecodingError.dataCorrupted` on a mismatch, or any decoding error.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        source = try container.decode(String.self, forKey: .source)
        license = try container.decode(String.self, forKey: .license)
        positive = try container.decode(String.self, forKey: .positive)
        negative = try container.decode(String.self, forKey: .negative)
        targets = try container.decode([String].self, forKey: .targets)
        groups = try container.decode([Group].self, forKey: .groups)
        previousWords = try container.decode([String].self, forKey: .previousWords)
        nextWords = try container.decode([String].self, forKey: .nextWords)
        pairs = try container.decode([[String]].self, forKey: .pairs)
        model = try container.decode(LogisticRegression.self, forKey: .model)
        groupSets = groups.map { Set($0.words) }

        let baseNames = targets.map { "word=" + $0 }
            + Self.positions.flatMap { position in Self.readingNames.map { position.1 + "." + $0 } }
            + groups.map { "group." + $0.name }
            + previousWords.map { "prev=" + $0 }
            + nextWords.map { "next=" + $0 }
        var indices: [(Int, Int)] = []
        for pair in pairs {
            guard pair.count == 2,
                  let left = baseNames.firstIndex(of: pair[0]),
                  let right = baseNames.firstIndex(of: pair[1]) else {
                throw DecodingError.dataCorruptedError(forKey: .pairs, in: container, debugDescription: "Unknown pair \(pair)")
            }
            indices.append((left, right))
        }
        pairIndices = indices
        let names = baseNames + pairs.map { "pair." + $0[0] + "*" + $0[1] }
        let saved = try container.decode([String].self, forKey: .featureNames)
        guard names == saved, names.count == model.featureCount else {
            throw DecodingError.dataCorruptedError(
                forKey: .featureNames,
                in: container,
                debugDescription: "The \(name) file was trained with different features"
            )
        }
    }

    /// Returns the probability of `positive` for the word in the middle of `window`.
    ///
    /// The window holds five normalized words, offsets -2 through 2. A punctuation mark is a
    /// word of its own, and `nil` marks the edge of the sentence.
    func probability(of window: [String?], lexicon: Lexicon) -> Double {
        model.predictProbabilities([features(of: window, lexicon: lexicon)]).first ?? 0.5
    }

    /// Returns the 0-or-1 features for one window, in the trained order.
    func features(of window: [String?], lexicon: Lexicon) -> [Double] {
        let word = { (offset: Int) -> String? in window.indices.contains(offset + 2) ? window[offset + 2] : nil }
        let target = word(0)
        var row: [Double] = targets.map { target == $0 ? 1 : 0 }
        for position in Self.positions {
            row += Self.readings(of: word(position.0), lexicon: lexicon)
        }
        for (group, words) in zip(groups, groupSets) {
            row.append(word(group.offset).map(words.contains) == true ? 1 : 0)
        }
        let previous = word(-1)
        let next = word(1)
        row += previousWords.map { previous == $0 ? 1 : 0 }
        row += nextWords.map { next == $0 ? 1 : 0 }
        for (left, right) in pairIndices {
            row.append(row[left] * row[right])
        }
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
        return [
            isVerb ? 1 : 0,
            isInfinitive ? 1 : 0,
            isNoun ? 1 : 0,
            isAdjective ? 1 : 0,
            lexicon.participles(word).isEmpty ? 0 : 1,
            isPunctuation || !(isVerb || isNoun || isAdjective) ? 1 : 0
        ]
    }
}
