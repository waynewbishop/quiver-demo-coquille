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

// Builds the French lexicon slice the app bundles, from the full Lexique 3.83 table.
//
// Usage:
//   swift Tools/BuildLexicon.swift /path/to/Lexique383.tsv quiver-demo-coquille/LanguagePacks/French/fr.lexicon.json [Tools/fr.noun-gender-overrides.json]
//
// The optional third file sets the gender of common nouns Lexique leaves blank,
// such as maison; it defaults to Tools/fr.noun-gender-overrides.json when present.
// Tools/fr.adjective-overrides.json, when present, completes adjectives Lexique
// splits or leaves incomplete, such as nouveau and nouvelle.
//
// The raw table (about 142,000 rows, 26 MB) never ships in the app. The slice keeps
// only what the linter's rules read: each noun's gender and number, each adjective's
// four forms, every verb form, and every other known spelling. The output is derived
// from Lexique and so carries Lexique's CC BY-SA 4.0 license.

import Foundation

// MARK: - Output shape

/// The bundled lexicon file, mirrored by `Lexicon` in the app.
struct LexiconFile: Codable {
    let source: String
    let license: String
    let generatedBy: String
    /// Noun spelling → gender (`m`, `f`, or `x` for both) followed by number (`s`, `p`, or `x`).
    let nouns: [String: String]
    /// Adjective lemma → its forms in the order masculine singular, feminine singular,
    /// masculine plural, feminine plural. An empty string means Lexique lists no such form.
    let adjectives: [String: [String]]
    /// Every spelling Lexique tags as a verb or auxiliary.
    let verbs: [String]
    /// Every remaining spelling: adverbs, prepositions, pronouns, determiners and so on.
    let otherWords: [String]
}

// MARK: - Reading Lexique

let arguments = CommandLine.arguments
guard arguments.count == 3 || arguments.count == 4 else {
    FileHandle.standardError.write(Data("usage: swift BuildLexicon.swift <Lexique383.tsv> <output.json> [overrides.json]\n".utf8))
    exit(1)
}

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
let numberColumn = column("nombre")

var nounGenders: [String: Set<Character>] = [:]
var nounNumbers: [String: Set<Character>] = [:]
// Lemma → slot ("ms", "fs", "mp", "fp") → form. Specific rows win over blank-field rows.
var adjectiveSlots: [String: [String: String]] = [:]
var adjectiveSlotIsSpecific: [String: [String: Bool]] = [:]
var verbs: Set<String> = []
var others: Set<String> = []

for line in lines {
    let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    guard fields.count == header.count else { continue }
    let form = fields[orthoColumn]
    // Multiword entries ("a capella") are never a single token in the editor.
    guard !form.isEmpty, !form.contains(" ") else { continue }

    let gender = fields[genderColumn]
    let number = fields[numberColumn]
    // A blank gender or number in Lexique means the form serves both.
    let genders: [Character] = gender.isEmpty ? ["m", "f"] : Array(gender.prefix(1))
    let numbers: [Character] = number.isEmpty ? ["s", "p"] : Array(number.prefix(1))

    switch fields[categoryColumn] {
    case "NOM":
        nounGenders[form, default: []].formUnion(genders)
        nounNumbers[form, default: []].formUnion(numbers)
    case "ADJ":
        let lemma = fields[lemmaColumn]
        let isSpecific = !gender.isEmpty && !number.isEmpty
        for g in genders {
            for n in numbers {
                let slot = "\(g)\(n)"
                let existingIsSpecific = adjectiveSlotIsSpecific[lemma]?[slot] ?? false
                if adjectiveSlots[lemma]?[slot] == nil || (isSpecific && !existingIsSpecific) {
                    adjectiveSlots[lemma, default: [:]][slot] = form
                    adjectiveSlotIsSpecific[lemma, default: [:]][slot] = isSpecific
                }
            }
        }
    case "VER", "AUX":
        verbs.insert(form)
    default:
        others.insert(form)
    }
}

// MARK: - Gender overrides

/// The hand-checked genders in `fr.noun-gender-overrides.json`.
struct GenderOverrides: Codable {
    let note: String
    /// Singular noun → "m" or "f".
    let nouns: [String: String]
}

let overridesPath = arguments.count == 4 ? arguments[3] : "Tools/fr.noun-gender-overrides.json"
var overridden = 0
if let overridesData = FileManager.default.contents(atPath: overridesPath) {
    let overrides = try JSONDecoder().decode(GenderOverrides.self, from: overridesData)
    for (noun, gender) in overrides.nouns {
        guard let letter = gender.first, gender.count == 1, "mf".contains(letter), nounGenders[noun] != nil else {
            FileHandle.standardError.write(Data("bad override \(noun): \(gender)\n".utf8))
            exit(1)
        }
        nounGenders[noun] = [letter]
        overridden += 1
        // The regular plural shares the gender, as in maisons; souris and pas are their own plural.
        let plural = noun + "s"
        if !noun.hasSuffix("s"), nounGenders[plural] != nil {
            nounGenders[plural] = [letter]
        }
    }
} else if arguments.count == 4 {
    FileHandle.standardError.write(Data("missing overrides file \(overridesPath)\n".utf8))
    exit(1)
}

// MARK: - Writing the slice

/// Collapses a set of gender or number codes into one letter, `x` when both apply.
func code(_ values: Set<Character>) -> String {
    values.count == 1 ? String(values.first ?? "x") : "x"
}

var nouns: [String: String] = [:]
for (form, genders) in nounGenders {
    nouns[form] = code(genders) + code(nounNumbers[form] ?? [])
}

var adjectives: [String: [String]] = [:]
for (lemma, slots) in adjectiveSlots {
    adjectives[lemma] = ["ms", "fs", "mp", "fp"].map { slots[$0] ?? "" }
}

// MARK: - Adjective overrides

/// The hand-checked adjectives in `fr.adjective-overrides.json`.
struct AdjectiveOverrides: Codable {
    let note: String
    /// Lemma → its four forms, replacing whatever Lexique lists.
    let forms: [String: [String]]
    /// Partial or stray lemmas whose forms all belong to another adjective.
    let remove: [String]
}

var adjectiveOverrides = 0
if let overridesData = FileManager.default.contents(atPath: "Tools/fr.adjective-overrides.json") {
    let overrides = try JSONDecoder().decode(AdjectiveOverrides.self, from: overridesData)
    for (lemma, forms) in overrides.forms {
        guard adjectives[lemma] != nil, forms.count == 4, !forms.contains("") else {
            FileHandle.standardError.write(Data("bad adjective override \(lemma): \(forms)\n".utf8))
            exit(1)
        }
        adjectives[lemma] = forms
        adjectiveOverrides += 1
    }
    for lemma in overrides.remove {
        guard let forms = adjectives.removeValue(forKey: lemma) else {
            FileHandle.standardError.write(Data("unknown adjective to remove: \(lemma)\n".utf8))
            exit(1)
        }
        // Removing a lemma must never drop a spelling the app knows.
        let remaining = Set(adjectives.values.flatMap { $0 })
        for form in forms where !form.isEmpty && !remaining.contains(form) {
            FileHandle.standardError.write(Data("removing \(lemma) would drop \(form)\n".utf8))
            exit(1)
        }
        adjectiveOverrides += 1
    }
}

let adjectiveForms = Set(adjectives.values.flatMap { $0 })
let otherWords = others.subtracting(nouns.keys).subtracting(adjectiveForms).subtracting(verbs)

let file = LexiconFile(
    source: "Lexique 3.83, Boris New & Christophe Pallier, http://www.lexique.org",
    license: "CC BY-SA 4.0, https://creativecommons.org/licenses/by-sa/4.0/",
    generatedBy: "Tools/BuildLexicon.swift",
    nouns: nouns,
    adjectives: adjectives,
    verbs: verbs.sorted(),
    otherWords: otherWords.sorted()
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
let data = try encoder.encode(file)
try data.write(to: URL(fileURLWithPath: arguments[2]))

print("nouns \(nouns.count) (\(overridden) gender overrides) · adjective lemmas \(adjectives.count) (\(adjectiveOverrides) overrides) · verb forms \(verbs.count) · other words \(otherWords.count) · \(data.count / 1024) KB")
