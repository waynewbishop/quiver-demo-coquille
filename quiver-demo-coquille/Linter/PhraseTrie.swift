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

/// A trie keyed by words rather than letters, holding every phrase in one list so a
/// single walk through the text finds all of them.
///
/// It follows the trie in Chapter 14 of Swift Algorithms & Data Structures, with two
/// changes. Each level is a whole word, so "je suis faim" and "je suis tard" share
/// the path je → suis and split only at their last word. And each node keeps its
/// children in a dictionary instead of an array, because the root branches once
/// for every distinct first word in the list, which runs to dozens for the
/// word-choice list, where a letter trie branches at most 26 ways.
///
/// Matching costs one dictionary lookup per word, per starting position, for as
/// many words as the longest phrase that keeps matching. Scanning the list instead
/// tries every phrase at every position.
nonisolated struct PhraseTrie: Sendable {

    /// One word in a phrase path.
    private struct Node: Sendable {
        /// The next word in each phrase that passes through this node, and its node.
        var children: [String: Int] = [:]
        /// The list positions of the phrases that end at this node.
        var entries: [Int] = []
    }

    /// A phrase found in the text.
    struct Match: Equatable, Sendable {
        /// The phrase's position in the list the trie was built from.
        let entry: Int
        /// The index of the phrase's first token.
        let start: Int
        /// The number of tokens the phrase covers.
        let length: Int
    }

    /// Every node, with the root at index 0, so the trie stays a value type.
    private var nodes = [Node()]

    /// Builds a trie from phrases already split into normalized words, in list order.
    init(phrases: [[String]]) {
        for (entry, words) in phrases.enumerated() {
            insert(words, entry: entry)
        }
    }

    /// Adds one phrase, sharing the nodes of any phrase that starts with the same words.
    private mutating func insert(_ words: [String], entry: Int) {
        guard !words.isEmpty else { return }
        var current = 0
        for word in words {
            if let next = nodes[current].children[word] {
                current = next
            } else {
                nodes.append(Node())
                let next = nodes.count - 1
                nodes[current].children[word] = next
                current = next
            }
        }
        nodes[current].entries.append(entry)
    }

    /// Returns every phrase in `tokens` whose words are adjacent, ordered by list
    /// position and then by where it starts, the order a scan of the list produces.
    func matches(in tokens: [Token]) -> [Match] {
        var found: [Match] = []
        for start in tokens.indices {
            var current = 0
            var index = start
            while index < tokens.count, let next = nodes[current].children[tokens[index].normalized] {
                current = next
                for entry in nodes[current].entries {
                    found.append(Match(entry: entry, start: start, length: index - start + 1))
                }
                // A phrase's words can't span punctuation, as in "comment, cava".
                guard tokens[index].isAdjacentToNext else { break }
                index += 1
            }
        }
        return found.sorted { ($0.entry, $0.start) < ($1.entry, $1.start) }
    }
}
