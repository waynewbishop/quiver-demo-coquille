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

/// Finds phrases by their French or English words, forgiving typos and missing accents.
///
/// Each word becomes the same letter-pair vector `SuggestionRanker` uses for spelling,
/// so "bonjur" finds "bonjour" and "cafe" finds "café". A query word scores its best
/// cosine against the phrase's words, and a word still being typed scores 1.0 when it
/// starts one ("bonj"). A phrase's score is the mean over the query's words.
nonisolated enum PhraseSearch {

    /// The score a phrase needs to be shown.
    static let threshold = 0.6

    /// Returns the phrases matching `query`, best first, or all of them in order when the query is empty.
    ///
    /// Ties keep the phrasebook's order.
    /// - Complexity: O(*p*·*q*·*w*) for *p* phrases, *q* query words and *w* words per phrase.
    static func matches(for query: String, in phrases: [Phrase]) -> [Phrase] {
        let queryWords = words(in: query)
        guard !queryWords.isEmpty else { return phrases }

        let scored = phrases.enumerated().compactMap { index, phrase -> (index: Int, score: Double)? in
            let phraseWords = words(in: phrase.french + " " + phrase.english)
            let total = queryWords.reduce(0.0) { $0 + bestScore(for: $1, among: phraseWords) }
            let score = total / Double(queryWords.count)
            return score >= threshold ? (index, score) : nil
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
            .map { phrases[$0.index] }
    }

    /// Returns the lowercased, accent-free words of `text`.
    static func words(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr"))
            .split { !$0.isLetter }
            .map(String.init)
    }

    /// Returns how closely `word` matches its nearest word in `candidates`, from 0 to 1.
    private static func bestScore(for word: String, among candidates: [String]) -> Double {
        guard !candidates.isEmpty else { return 0 }
        // A word still being typed matches the words it starts.
        if word.count >= 2, candidates.contains(where: { $0.hasPrefix(word) }) {
            return 1.0
        }

        let target = SuggestionRanker.letterPairs(of: word)
        let rows = candidates.map(SuggestionRanker.letterPairs)
        let vocabulary = Array(Set(target + rows.flatMap { $0 })).sorted()
        let position = Dictionary(uniqueKeysWithValues: vocabulary.enumerated().map { ($1, $0) })

        let targetVector = SuggestionRanker.counts(of: target, in: position)
        let candidateVectors = rows.map { SuggestionRanker.counts(of: $0, in: position) }
        return candidateVectors.cosineSimilarities(to: targetVector).max() ?? 0
    }
}
