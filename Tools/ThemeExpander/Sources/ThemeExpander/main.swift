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

// Suggests words for each A1 theme from the words the theme already holds.
//
// Usage, from the repository root:
//   swift run --package-path Tools/ThemeExpander ThemeExpander /path/to/Lexique383.tsv [Tools/fr.a1-themes.json] [theme]
//
// Every Lexique noun, verb, adjective and adverb among the 15,000 most frequent lemmas goes
// into a Quiver EmbeddingIndex, using Apple's French word embeddings. Each theme's words,
// averaged into one vector, are the query, and the closest lemmas not yet on the A1 list
// are printed with their cosine score, frequency rank and, for nouns, gender. The frequency
// cut drops rare and misspelled neighbours, such as ceinturées next to jupe. Nothing is
// written: an author keeps or cuts each suggestion by editing the theme file.
//
// Run on authors' machines only. The tool never ships in the app.

import Foundation
import NaturalLanguage
import Quiver

let candidateRankLimit = 15_000
let coreSize = 1_000
let suggestionCount = 30

let arguments = CommandLine.arguments
guard (2...4).contains(arguments.count) else {
    FileHandle.standardError.write(Data("usage: ThemeExpander <Lexique383.tsv> [themes.json] [theme]\n".utf8))
    exit(1)
}
let themesPath = arguments.count > 2 ? arguments[2] : "Tools/fr.a1-themes.json"
let onlyTheme = arguments.count > 3 ? arguments[3] : nil

/// Lowercases a word and folds the spellings Lexique writes differently, such as sœur as soeur.
func fold(_ word: String) -> String {
    word.lowercased()
        .replacingOccurrences(of: "œ", with: "oe")
        .replacingOccurrences(of: "æ", with: "ae")
}

// MARK: - Embeddings

/// Embeds French text as the average of Apple's word vectors for the words it knows.
struct FrenchWordEmbedder: Embedder, @unchecked Sendable {
    let embedding: NLEmbedding

    /// Returns the vector for one word, trying the œ spelling Lexique folds to oe.
    func vector(for word: String) -> [Double]? {
        embedding.vector(for: word) ?? embedding.vector(for: word.replacingOccurrences(of: "oe", with: "œ"))
    }

    /// Averages the vectors of the words in the text, or returns nil when it knows none.
    func embed(_ text: String) -> [Double]? {
        text.lowercased().split(separator: " ").compactMap { vector(for: String($0)) }.meanVector()
    }
}

guard let frenchEmbedding = NLEmbedding.wordEmbedding(for: .french) else {
    FileHandle.standardError.write(Data("Apple's French word embeddings aren't installed on this Mac\n".utf8))
    exit(1)
}
let embedder = FrenchWordEmbedder(embedding: frenchEmbedding)

// MARK: - Reading Lexique

let table = try String(contentsOf: URL(fileURLWithPath: arguments[1]), encoding: .utf8)
// Lexique uses CRLF line endings, which Swift reads as one "\r\n" Character,
// so split on any newline rather than on "\n" alone.
var lines = table.split(whereSeparator: \.isNewline)
let header = lines.removeFirst().split(separator: "\t", omittingEmptySubsequences: false).map(String.init)

/// Returns the position of a named Lexique column, stopping if the table layout changed.
func column(_ name: String) -> Int {
    guard let index = header.firstIndex(of: name) else {
        FileHandle.standardError.write(Data("missing column \(name)\n".utf8))
        exit(1)
    }
    return index
}

let orthoColumn = column("ortho")
let lemmaColumn = column("lemme")
let categoryColumn = column("cgram")
let genderColumn = column("genre")
let lemmaFilmsColumn = column("freqlemfilms2")
let lemmaBooksColumn = column("freqlemlivres")

/// One Lexique lemma the index can suggest.
struct Candidate: Codable, Equatable {
    let lemma: String
    let category: String
    /// The noun's gender (`m` or `f`), or empty for other parts of speech and nouns of both.
    let gender: String
    /// The lemma's place in Lexique's frequency ranking, starting at one.
    var rank: Int
}

let contentCategories: Set<String> = ["NOM", "VER", "ADJ", "ADV"]
// Folded lemma → frequency and candidate; the most frequent part of speech wins.
var lemmas: [String: (frequency: Double, candidate: Candidate)] = [:]
var nounGenders: [String: Set<String>] = [:]

for line in lines {
    let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    guard fields.count == header.count else { continue }
    let lemma = fields[lemmaColumn]
    let category = fields[categoryColumn] == "AUX" ? "VER" : fields[categoryColumn]
    let frequency = ((Double(fields[lemmaFilmsColumn]) ?? 0) + (Double(fields[lemmaBooksColumn]) ?? 0)) / 2
    let key = fold(lemma)
    if category == "NOM", fields[orthoColumn] == lemma, !fields[genderColumn].isEmpty {
        nounGenders[key, default: []].insert(fields[genderColumn])
    }
    if frequency > lemmas[key]?.frequency ?? -1 {
        lemmas[key] = (frequency, Candidate(lemma: lemma, category: category, gender: "", rank: 0))
    }
}

let ranked = lemmas.sorted { $0.value.frequency > $1.value.frequency }
let coreLemmas = Set(ranked.prefix(coreSize).map(\.key))

// MARK: - The index

/// The hand-kept half of the A1 list in `fr.a1-themes.json`.
struct ThemeFile: Codable {
    let note: String
    /// Frequency-core lemmas to leave out of A1.
    let exclude: [String]
    /// Theme name → its words, as dictionary forms.
    let themes: [String: [String]]
}

let themeFile = try JSONDecoder().decode(ThemeFile.self, from: Data(contentsOf: URL(fileURLWithPath: themesPath)))
let alreadyListed = coreLemmas
    .union(themeFile.themes.values.flatMap { $0 }.map(fold))
    .union(themeFile.exclude.map(fold))

var index = EmbeddingIndex<Candidate>(embedder: embedder)
for (position, entry) in ranked.prefix(candidateRankLimit).enumerated() {
    var candidate = entry.value.candidate
    guard contentCategories.contains(candidate.category),
          !alreadyListed.contains(entry.key),
          let vector = embedder.vector(for: candidate.lemma) else { continue }
    candidate.rank = position + 1
    if candidate.category == "NOM", let genders = nounGenders[entry.key], genders.count == 1 {
        candidate = Candidate(lemma: candidate.lemma, category: candidate.category, gender: genders.first ?? "", rank: candidate.rank)
    }
    index.add(vector: vector, label: candidate)
}
print("Indexed \(index.count) Lexique lemmas outside the A1 list (frequency ranks up to \(candidateRankLimit))")

// MARK: - Suggestions

for (theme, words) in themeFile.themes.sorted(by: { $0.key < $1.key }) {
    if let onlyTheme, theme != onlyTheme { continue }
    let result = index.retrieve(words.joined(separator: " "), k: suggestionCount)
    print("\n\(theme), from \(words.joined(separator: ", ")):")
    for hit in result.hits {
        let candidate = hit.label
        let detail = candidate.gender.isEmpty ? candidate.category : "\(candidate.category) \(candidate.gender)"
        print("  \(candidate.lemma.padding(toLength: 18, withPad: " ", startingAt: 0)) \(String(format: "%.2f", hit.score))  rank \(candidate.rank)  \(detail)")
    }
}
