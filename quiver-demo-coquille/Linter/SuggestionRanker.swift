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

/// Ranks spelling suggestions by how closely their letters match the misspelled word.
///
/// Each word becomes a vector of letter-pair counts, with `^` and `$` marking the
/// start and end, so "gentile" is ^g, ge, en, nt, ti, il, le, e$. Candidates are
/// ordered by the cosine of their vector with the misspelled word's vector.
///
/// Accents are ignored when comparing, because a missing accent is the most common
/// slip: "tete" matches "tête" exactly, where comparing accented letters would rank
/// "tette" first. Candidates that differ only by accent keep the spellchecker's order.
nonisolated enum SuggestionRanker {

    /// Returns the candidates ordered from most to least similar to `word`.
    ///
    /// Ties keep the spellchecker's original order.
    /// - Complexity: O(*c*·*v*) for *c* candidates over a letter-pair vocabulary of size *v*.
    static func ranked(_ candidates: [String], for word: String) -> [String] {
        guard candidates.count > 1 else { return candidates }

        let target = letterPairs(of: word)
        let rows = candidates.map(letterPairs)
        let vocabulary = Array(Set(target + rows.flatMap { $0 })).sorted()
        let position = Dictionary(uniqueKeysWithValues: vocabulary.enumerated().map { ($1, $0) })

        let targetVector = counts(of: target, in: position)
        let candidateVectors = rows.map { counts(of: $0, in: position) }
        let similarities = candidateVectors.cosineSimilarities(to: targetVector)

        let order = candidates.indices.sorted { left, right in
            similarities[left] != similarities[right] ? similarities[left] > similarities[right] : left < right
        }
        return order.map { candidates[$0] }
    }

    /// Returns a word's letter pairs without accents, including the start and end markers.
    static func letterPairs(of word: String) -> [String] {
        let folded = word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr"))
        let letters = ["^"] + folded.map(String.init) + ["$"]
        return zip(letters, letters.dropFirst()).map { $0 + $1 }
    }

    /// Counts each letter pair into a vector laid out by `position`.
    static func counts(of pairs: [String], in position: [String: Int]) -> [Double] {
        var vector = [Double](repeating: 0.0, count: position.count)
        for pair in pairs {
            if let index = position[pair] {
                vector[index] += 1.0
            }
        }
        return vector
    }
}
