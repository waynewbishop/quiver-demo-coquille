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

/// Hand-checked explanations of false friends and idioms, from `fr.explain-notes.json`.
///
/// Explain shows these in place of the model's notes, so a phrase on the list is always
/// explained the same, checked way. A match uses the pattern words of `fr.patterns.json`:
/// `@poser un lapin` matches "m'a posé un lapin" through Lexique's forms of poser.
nonisolated struct CheckedNotes: Sendable {

    /// One checked note and the wordings that call for it.
    struct Entry: Decodable, Sendable {
        /// The pattern words that match it, such as "@avoir hâte de".
        let match: [String]
        /// The phrase as the panel shows it, usually in its dictionary form.
        let french: String
        let meaning: String
        let note: String
    }

    /// A checked note found in a passage, with where its words are.
    struct Found: Equatable, Sendable {
        let french: String
        let meaning: String
        let note: String
        /// The character offset of the first matched word.
        let offset: Int
        /// The character offset just past the last matched word.
        let end: Int
    }

    /// Words before which a verb form is read as a noun, as reste in "le reste".
    static let determiners: Set<String> = [
        "le", "la", "les", "l'", "un", "une", "des", "du", "ce", "cet", "cette", "ces",
        "mon", "ma", "mes", "ton", "ta", "tes", "son", "sa", "ses",
        "notre", "nos", "votre", "vos", "leur", "leurs"
    ]

    private let entries: [Entry]
    /// The entry index of each pattern in the trie, in trie order.
    private let entryOfPattern: [Int]
    private let trie: PhraseTrie
    private let lexicon: Lexicon

    /// Builds the matcher for `entries`, using `lexicon` for the forms of each `@verb`.
    init(entries: [Entry], lexicon: Lexicon) {
        var patterns: [[String]] = []
        var owners: [Int] = []
        for (index, entry) in entries.enumerated() {
            for pattern in entry.match {
                patterns.append(PhrasePattern.words(of: pattern))
                owners.append(index)
            }
        }
        self.entries = entries
        self.entryOfPattern = owners
        self.trie = PhraseTrie(phrases: patterns)
        self.lexicon = lexicon
    }

    /// Loads the checked notes bundled with the app, or returns `nil` if the file is missing.
    static func french(lexicon: Lexicon, in bundle: Bundle = .main) throws -> CheckedNotes? {
        guard let url = bundle.url(forResource: "fr.explain-notes", withExtension: "json") else { return nil }
        let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
        return CheckedNotes(entries: entries, lexicon: lexicon)
    }

    /// Returns each checked note whose wording appears in `text`, once per entry, in passage order.
    func notes(in text: String) -> [Found] {
        let tokens = FrenchTokenizer.tokens(in: text)
        let matches = trie.matches(in: tokens, keys: { keys(at: $0, in: tokens) })
            .sorted { ($0.start, $0.entry) < ($1.start, $1.entry) }
        var seen = Set<Int>()
        var found: [Found] = []
        for match in matches {
            let index = entryOfPattern[match.entry]
            guard seen.insert(index).inserted else { continue }
            let entry = entries[index]
            let last = tokens[match.start + match.length - 1]
            found.append(Found(
                french: entry.french, meaning: entry.meaning, note: entry.note,
                offset: tokens[match.start].offset, end: last.offset + last.text.count
            ))
        }
        return found
    }

    /// Returns every pattern word the token at `index` can stand for: itself, and `@verb` for
    /// each verb Lexique says it's a form of, unless a determiner just before makes it a noun.
    private func keys(at index: Int, in tokens: [Token]) -> [String] {
        let word = tokens[index].normalized
        var keys = [word]
        if index > 0, Self.determiners.contains(tokens[index - 1].normalized) { return keys }
        keys += lexicon.conjugations(word).map { "@" + $0.verb }
        keys += lexicon.participles(word).map { "@" + $0.verb }
        if lexicon.isInfinitive(word) { keys.append("@" + word) }
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }
}
