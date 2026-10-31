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

// Measures how much of the A1 word list the phrasebook covers, and prints the A1 words
// no phrase uses yet, grouped by theme.
//
// Usage:
//   swift Tools/A1Coverage.swift /path/to/Lexique383.tsv [Tools/fr.a1-themes.json] [quiver-demo-coquille/LanguagePacks/French/fr.phrases.json]
//
// The A1 list has two parts. The frequency core is the 1,000 most frequent Lexique lemmas,
// ranked by the average of their film and book frequencies, minus the exclude list in the
// theme file.
// The theme lists are the hand-kept words in the theme file, which frequency alone misses
// (lundi ranks near 2,170). Each phrase word is reduced to its dictionary form with Lexique,
// so appelez counts as appeler and j' as je. A form with several lemmas counts for each
// reading that makes up at least a tenth of the form's uses, so porte counts as both
// porte and porter, while est counts as être and never as the noun.
//
// Run on authors' machines only. The tool never ships in the app.

import Foundation

let coreSize = 1_000

let arguments = CommandLine.arguments
guard (2...4).contains(arguments.count) else {
    FileHandle.standardError.write(Data("usage: swift A1Coverage.swift <Lexique383.tsv> [themes.json] [phrases.json]\n".utf8))
    exit(1)
}
let themesPath = arguments.count > 2 ? arguments[2] : "Tools/fr.a1-themes.json"
let phrasesPath = arguments.count > 3 ? arguments[3] : "quiver-demo-coquille/LanguagePacks/French/fr.phrases.json"

/// Lowercases a word and folds the spellings Lexique writes differently, such as sœur as soeur.
func fold(_ word: String) -> String {
    word.lowercased()
        .replacingOccurrences(of: "œ", with: "oe")
        .replacingOccurrences(of: "æ", with: "ae")
        .replacingOccurrences(of: "’", with: "'")
}

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
let lemmaFilmsColumn = column("freqlemfilms2")
let lemmaBooksColumn = column("freqlemlivres")
let formFilmsColumn = column("freqfilms2")
let formBooksColumn = column("freqlivres")

/// One lemma in one part of speech, as Lexique ranks it.
struct RankedLemma {
    let lemma: String
    let category: String
    let frequency: Double
}

// "lemma|category" → average of film and book lemma frequency.
var lemmaFrequencies: [String: RankedLemma] = [:]
// Folded form → folded lemma → how often Lexique sees the form as that lemma.
var readings: [String: [String: Double]] = [:]
var categoriesByLemma: [String: Set<String>] = [:]

for line in lines {
    let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    guard fields.count == header.count else { continue }
    let lemma = fields[lemmaColumn]
    let category = fields[categoryColumn]
    let lemmaFrequency = ((Double(fields[lemmaFilmsColumn]) ?? 0) + (Double(fields[lemmaBooksColumn]) ?? 0)) / 2
    lemmaFrequencies[lemma + "|" + category] = RankedLemma(lemma: lemma, category: category, frequency: lemmaFrequency)
    categoriesByLemma[fold(lemma), default: []].insert(category)

    let form = fold(fields[orthoColumn])
    let formFrequency = (Double(fields[formFilmsColumn]) ?? 0) + (Double(fields[formBooksColumn]) ?? 0)
    readings[form, default: [:]][fold(lemma), default: 0] += formFrequency
}

/// The share of a form's uses a reading needs before the form counts for its lemma.
let readingShare = 0.1

/// Returns the lemmas a form counts for, most frequent first, or nil when Lexique lacks the form.
func lemmas(ofForm form: String) -> [String]? {
    guard let byLemma = readings[form], let top = byLemma.values.max() else { return nil }
    return byLemma.filter { $0.value >= top * readingShare || top == 0 }
        .sorted { $0.value > $1.value }
        .map(\.key)
}

// MARK: - The A1 list

/// The hand-kept half of the A1 list in `fr.a1-themes.json`.
struct ThemeFile: Codable {
    let note: String
    /// Frequency-core lemmas to leave out of A1.
    let exclude: [String]
    /// Theme name → its words, as dictionary forms.
    let themes: [String: [String]]
}

let themeFile = try JSONDecoder().decode(ThemeFile.self, from: Data(contentsOf: URL(fileURLWithPath: themesPath)))
let excluded = Set(themeFile.exclude.map(fold))

/// Groups a Lexique part of speech into the buckets the report prints.
func group(_ category: String) -> String {
    switch category {
    case "NOM": "nouns"
    case "VER", "AUX": "verbs"
    case "ADJ": "adjectives"
    case "ADV": "adverbs"
    default: "function words"
    }
}

// Folded lemma → the group it is reported under. Theme words claim their lemma first.
var a1Group: [String: String] = [:]
var spelling: [String: String] = [:]
var unknownThemeWords: [String] = []
for (theme, words) in themeFile.themes {
    for word in words {
        var key = fold(word)
        // A plural-only noun such as vacances is filed under Lexique's singular lemma, as
        // the phrase words are; cousine joins cousin the same way.
        if categoriesByLemma[key] == nil, let lemma = lemmas(ofForm: key)?.first {
            key = lemma
        }
        // Multiword entries such as salle de bain, and compounds Lexique lacks such as
        // après-midi, are matched against the phrase text instead.
        if categoriesByLemma[key] == nil && !key.contains(" ") && !key.contains("-") {
            unknownThemeWords.append("\(word) (\(theme))")
        }
        a1Group[key] = "theme: " + theme
        spelling[key] = word
    }
}

/// Elided forms and the word each one stands for. Lexique lists d' and l' as lemmas of their own.
let elisions = ["j'": "je", "l'": "le", "d'": "de", "n'": "ne", "m'": "me", "t'": "te", "s'": "se",
                "c'": "ce", "qu'": "que", "jusqu'": "jusque", "lorsqu'": "lorsque", "puisqu'": "puisque"]

// A lemma Lexique lists under several parts of speech, such as avoir (AUX and VER),
// fills one core place, under its most frequent part of speech.
var topLemmas: [String] = []
var seen: Set<String> = []
for entry in lemmaFrequencies.values.sorted(by: { $0.frequency > $1.frequency }) {
    let folded = fold(entry.lemma)
    let key = elisions[folded] ?? folded
    guard seen.insert(key).inserted else { continue }
    topLemmas.append(key)
    if a1Group[key] == nil {
        a1Group[key] = "core: " + group(entry.category)
        spelling[key] = elisions[folded] ?? entry.lemma
    }
    if topLemmas.count == coreSize { break }
}
let excludedCore = Set(topLemmas).intersection(excluded)
let coreLemmas = Set(topLemmas).subtracting(excluded)
for key in excludedCore where !(a1Group[key]?.hasPrefix("theme") ?? false) {
    a1Group[key] = nil
}

let unusedExcludes = themeFile.exclude.filter { !topLemmas.contains(fold($0)) }

// MARK: - Reading the phrases

/// The fields of `fr.phrases.json` this tool reads.
struct PhraseEntry: Codable {
    let french: String
}

let phrases = try JSONDecoder().decode([PhraseEntry].self, from: Data(contentsOf: URL(fileURLWithPath: phrasesPath)))

var unknownTokens: [String: Int] = [:]

/// Returns the dictionary forms of one token, splitting elisions and hyphens Lexique doesn't list whole.
func lemmas(of token: String) -> [String] {
    if let found = lemmas(ofForm: token) {
        return found.map { elisions[$0] ?? $0 }
    }
    if let apostrophe = token.firstIndex(of: "'") {
        let head = String(token[...apostrophe])
        let rest = String(token[token.index(after: apostrophe)...])
        // S'il and s'ils elide si, not se.
        let headLemma = head == "s'" && rest.hasPrefix("il") ? "si" : elisions[head]
        if let headLemma {
            return [headLemma] + lemmas(of: rest)
        }
    }
    if token.contains("-") {
        // The -t- in a-t-il only joins sounds.
        return token.split(separator: "-").map(String.init).filter { $0 != "t" }.flatMap(lemmas(of:))
    }
    if !token.isEmpty, token.allSatisfy(\.isLetter) {
        unknownTokens[token, default: 0] += 1
    }
    return []
}

var phraseLemmas: Set<String> = []
var newWordsPerPhrase: [Int] = []
var tokenCount = 0
let foldedPhrases = phrases.map { fold($0.french) }
for text in foldedPhrases {
    let tokens = text.split { !$0.isLetter && $0 != "'" && $0 != "-" }.map(String.init)
    tokenCount += tokens.count
    // A theme word typed exactly as listed counts too, so été the season isn't lost to
    // être and fils the sons isn't lost to fil.
    let exact = tokens.filter { a1Group[$0]?.hasPrefix("theme") ?? false }
    let found = Set(tokens.flatMap(lemmas(of:))).union(exact)
    newWordsPerPhrase.append(found.subtracting(phraseLemmas).filter { a1Group[$0] != nil }.count)
    phraseLemmas.formUnion(found)
}
// Each word of a multiword entry may take a plural s or x, so pommes de terre counts.
for key in a1Group.keys where key.contains(" ") || key.contains("-") {
    let words = key.split(whereSeparator: { $0 == " " || $0 == "-" }).map { NSRegularExpression.escapedPattern(for: String($0)) + "[sx]?" }
    let separators = key.filter { $0 == " " || $0 == "-" }.map { $0 == " " ? " " : "-" }
    var pattern = "(^|[^\\p{L}])" + words[0]
    for (separator, word) in zip(separators, words.dropFirst()) {
        pattern += separator + word
    }
    pattern += "($|[^\\p{L}])"
    if foldedPhrases.contains(where: { $0.range(of: pattern, options: .regularExpression) != nil }) {
        phraseLemmas.insert(key)
    }
}

// MARK: - Report

let covered = a1Group.keys.filter(phraseLemmas.contains)
let percent = Double(covered.count) / Double(a1Group.count) * 100
let themeCount = a1Group.keys.count - a1Group.keys.filter(coreLemmas.contains).count
print("A1 list: \(a1Group.count) words (\(coreLemmas.count) frequency core, \(themeCount) theme-only)")
print("Phrases: \(phrases.count), averaging \(String(format: "%.1f", Double(tokenCount) / Double(phrases.count))) words")
print("Covered: \(covered.count) of \(a1Group.count) (\(String(format: "%.1f", percent))%)")
let addingPhrases = newWordsPerPhrase.filter { $0 > 0 }.count
print("New A1 words per phrase: \(String(format: "%.1f", Double(covered.count) / Double(phrases.count))) on average; \(addingPhrases) of \(phrases.count) phrases add at least one")
print("Missing: \(a1Group.count - covered.count)")

var missingByGroup: [String: [String]] = [:]
for (key, groupName) in a1Group where !phraseLemmas.contains(key) {
    missingByGroup[groupName, default: []].append(spelling[key] ?? key)
}
// Themes first, then the core groups, each list alphabetical.
for groupName in missingByGroup.keys.sorted(by: { ($0.hasPrefix("core") ? 1 : 0, $0) < ($1.hasPrefix("core") ? 1 : 0, $1) }) {
    let words = missingByGroup[groupName, default: []].sorted { $0.compare($1, locale: Locale(identifier: "fr")) == .orderedAscending }
    print("\n\(groupName) (\(words.count)): " + words.joined(separator: ", "))
}

if !unknownThemeWords.isEmpty {
    print("\nTheme words Lexique doesn't know (check the spelling): " + unknownThemeWords.sorted().joined(separator: ", "))
}
if !unusedExcludes.isEmpty {
    print("\nExcluded words outside the top \(coreSize) (remove them): " + unusedExcludes.joined(separator: ", "))
}
if !unknownTokens.isEmpty {
    print("\nPhrase words Lexique doesn't know: " + unknownTokens.keys.sorted().joined(separator: ", "))
}
