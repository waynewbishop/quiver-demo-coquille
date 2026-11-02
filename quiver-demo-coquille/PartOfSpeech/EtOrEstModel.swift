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

/// A Quiver logistic regression that decides whether et ("and") or est ("is")
/// belongs in a sentence, from the words around it.
///
/// None of the features is the word itself, so the verdict is the same whichever
/// of the two the learner wrote: it judges the context, not the spelling. Every
/// feature is 1.0 or 0.0, and class 1 is est. The feature order is fixed by
/// `features(_:lexicon:)` and must match the Notebook script that trained it.
///
/// The model is trained in the Quiver Notebook on Universal Dependencies French
/// and bundled as `fr.et-est-model.json`.
nonisolated struct EtOrEstModel: Codable, Equatable, Sendable {

    /// The words around one et or est, as the model saw them in training: punctuation
    /// is a word of its own, and nothing comes before a sentence's first word.
    struct Context: Equatable, Sendable {
        /// Every word in the sentence before this one, from the sentence's start.
        let earlier: [String]
        /// Whether the clause starts right before `beforePrevious`: the sentence's
        /// start, or right after punctuation.
        let clauseStartsTwoBefore: Bool
        let beforePrevious: String?
        let previous: String?
        let next: String?
        let afterNext: String?
    }

    /// Where the training data came from, and its licence.
    let source: String
    let license: String
    /// Words that open a question, after which est usually comes before its subject.
    let questionWords: [String]
    /// Subject pronouns; one earlier in the sentence has usually had its verb already.
    let subjectPronouns: [String]
    /// Words that start a clause of their own, such as que and qui.
    let clauseWords: [String]
    /// Words that often come right before est as its subject, such as il and c'.
    let subjectWords: [String]
    /// Determiners, which start a noun phrase.
    let determiners: [String]
    /// Frequent words before et or est, each its own feature.
    let previousWords: [String]
    /// Frequent words after et or est, each its own feature.
    let nextWords: [String]
    /// The trained classifier.
    let model: LogisticRegression

    /// The number of features each Lexique reading set contributes.
    private static let readingCount = 6

    /// The feature count the word lists imply, which must equal the model's.
    private var expectedFeatureCount: Int {
        4 * Self.readingCount + 10 + previousWords.count + nextWords.count
    }

    private enum CodingKeys: String, CodingKey {
        case source, license, questionWords, subjectPronouns, clauseWords, subjectWords, determiners, previousWords, nextWords, model
    }

    /// Decodes a bundled model, rejecting a file whose word lists don't match its features.
    ///
    /// - Throws: `DecodingError.dataCorrupted` on a mismatch, or any decoding error.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(String.self, forKey: .source)
        license = try container.decode(String.self, forKey: .license)
        questionWords = try container.decode([String].self, forKey: .questionWords)
        subjectPronouns = try container.decode([String].self, forKey: .subjectPronouns)
        clauseWords = try container.decode([String].self, forKey: .clauseWords)
        subjectWords = try container.decode([String].self, forKey: .subjectWords)
        determiners = try container.decode([String].self, forKey: .determiners)
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

    /// Whether a noun stands before the word and a determiner after it, as in "un chat
    /// ? un chien". A noun phrase on each side can take either word ("un chat et un
    /// chien", "le chat est un animal"), so the app may ask here but never correct.
    func canOnlyAsk(_ context: Context, lexicon: Lexicon) -> Bool {
        let nounBefore = context.previous.map { lexicon.noun($0) != nil } ?? false
        return nounBefore && (context.next.map(determiners.contains) ?? false)
    }

    /// Whether the word comes in a question that hasn't had its verb yet, as in "à quelle
    /// heure est le départ ?". The training treebanks hold only 26 of these, 24 with est,
    /// too few for the model to learn, so a written est here is always left alone.
    func isOpenQuestion(_ context: Context, lexicon: Lexicon) -> Bool {
        context.earlier.contains(where: questionWords.contains)
            && !context.earlier.contains(where: subjectPronouns.contains)
            && !context.earlier.contains { Self.canOnlyBeVerb($0, lexicon: lexicon) }
    }

    /// Whether Lexique lists a word only as a verb, never as a noun or adjective.
    private static func canOnlyBeVerb(_ word: String, lexicon: Lexicon) -> Bool {
        lexicon.isVerb(word) && lexicon.noun(word) == nil && lexicon.adjectiveLemmas(of: word).isEmpty
    }

    /// Returns the probability that est, not et, belongs in this context.
    func estProbability(_ context: Context, lexicon: Lexicon) -> Double {
        model.predictProbabilities([features(context, lexicon: lexicon)]).first ?? 0.5
    }

    /// Returns the binary features for one context, in the trained order.
    func features(_ context: Context, lexicon: Lexicon) -> [Double] {
        var row = Self.readings(of: context.beforePrevious, lexicon: lexicon)
        row += Self.readings(of: context.previous, lexicon: lexicon)
        row += Self.readings(of: context.next, lexicon: lexicon)
        row += Self.readings(of: context.afterNext, lexicon: lexicon)
        row.append(context.previous.map(subjectWords.contains) ?? false ? 1.0 : 0.0)
        row.append(context.next.map(determiners.contains) ?? false ? 1.0 : 0.0)
        // "la maison est grande": a noun, then an adjective. Each weight adds on its
        // own, so this one feature fires only for the pair.
        let nounBefore = context.previous.map { lexicon.noun($0) != nil } ?? false
        let adjectiveAfter = context.next.map { !lexicon.adjectiveLemmas(of: $0).isEmpty } ?? false
        row.append(nounBefore && adjectiveAfter ? 1.0 : 0.0)
        // "La maison ? belle": a determiner and noun that open the clause are its subject.
        let opensWithSubject = context.clauseStartsTwoBefore
            && (context.beforePrevious.map(determiners.contains) ?? false) && nounBefore
        row.append(opensWithSubject ? 1.0 : 0.0)
        // "un chat et un chien" or "le chat est un animal": a noun phrase on each side.
        row.append(nounBefore && (context.next.map(determiners.contains) ?? false) ? 1.0 : 0.0)
        // What came earlier in the sentence: a question word asks for est, and a subject
        // that already has its verb leaves room only for et.
        let beforeLast = context.earlier.dropLast()
        row.append(context.earlier.contains(where: questionWords.contains) ? 1.0 : 0.0)
        row.append(beforeLast.contains(where: subjectPronouns.contains) ? 1.0 : 0.0)
        let onlyVerb = beforeLast.contains { Self.canOnlyBeVerb($0, lexicon: lexicon) }
        row.append(onlyVerb ? 1.0 : 0.0)
        // "La station de métro ? au bout de la rue": everything so far is one noun phrase
        // with no verb, still waiting for its verb.
        let onlyNounPhrase = context.earlier.contains(where: determiners.contains)
            && !context.earlier.contains(where: subjectPronouns.contains)
            && !context.earlier.contains(where: clauseWords.contains)
            && !context.earlier.contains(where: Self.isMark)
            && !onlyVerb
        row.append(onlyNounPhrase ? 1.0 : 0.0)
        // "Le fromage que j'aime ? bon": a noun phrase, then a relative clause about it,
        // then the main verb. The je belongs to the relative clause.
        let relativeIndex = context.earlier.firstIndex(where: clauseWords.contains) ?? 0
        let opensWithRelative = (context.earlier.first.map(determiners.contains) ?? false)
            && relativeIndex >= 2
            && !context.earlier.contains(where: Self.isMark)
        row.append(opensWithRelative ? 1.0 : 0.0)
        row += previousWords.map { context.previous == $0 ? 1.0 : 0.0 }
        row += nextWords.map { context.next == $0 ? 1.0 : 0.0 }
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
        let isPunctuation = isMark(word)
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

    /// Whether a word is punctuation, which ends a clause.
    static func isMark(_ word: String) -> Bool {
        word.unicodeScalars.allSatisfy(CharacterSet.punctuationCharacters.union(.symbols).contains)
    }
}
