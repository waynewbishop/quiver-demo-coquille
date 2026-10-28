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

/// The bundled slice of Lexique: gender and number for nouns, the four forms of each
/// adjective, and every verb and other known spelling.
///
/// The file is produced by `Tools/BuildLexicon.swift` and is derived from Lexique 3.83,
/// licensed CC BY-SA 4.0.
nonisolated struct Lexicon: Sendable {

    // MARK: - File format

    /// The on-disk shape of `fr.lexicon.json`.
    struct File: Codable, Sendable {
        let source: String
        let license: String
        let generatedBy: String
        /// Noun → gender code (`m`, `f`, `x` for both) then number code (`s`, `p`, `x`).
        let nouns: [String: String]
        /// Adjective lemma → forms as masculine singular, feminine singular, masculine plural, feminine plural.
        let adjectives: [String: [String]]
        let verbs: [String]
        let otherWords: [String]
    }

    /// A noun's gender and number; `nil` means the noun serves both.
    struct Noun: Equatable, Sendable {
        let gender: Gender?
        let number: GrammaticalNumber?
    }

    // MARK: - Contents

    let source: String
    let license: String
    private let nouns: [String: Noun]
    private let adjectiveForms: [String: [String]]
    private let adjectiveLemmasByForm: [String: [String]]
    private let verbs: Set<String>
    private let otherWords: Set<String>

    /// Builds a lexicon from its decoded file.
    init(file: File) {
        source = file.source
        license = file.license

        var nouns: [String: Noun] = [:]
        nouns.reserveCapacity(file.nouns.count)
        for (word, code) in file.nouns {
            let letters = Array(code)
            guard letters.count == 2 else { continue }
            let gender: Gender? = switch letters[0] {
            case "m": .masculine
            case "f": .feminine
            default: nil
            }
            let number: GrammaticalNumber? = switch letters[1] {
            case "s": .singular
            case "p": .plural
            default: nil
            }
            nouns[word] = Noun(gender: gender, number: number)
        }
        self.nouns = nouns

        var lemmasByForm: [String: [String]] = [:]
        for (lemma, forms) in file.adjectives where forms.count == 4 {
            for form in Set(forms) where !form.isEmpty {
                lemmasByForm[form, default: []].append(lemma)
            }
        }
        adjectiveForms = file.adjectives.filter { $0.value.count == 4 }
        adjectiveLemmasByForm = lemmasByForm
        verbs = Set(file.verbs)
        otherWords = Set(file.otherWords)
    }

    /// Loads and decodes a lexicon file.
    ///
    /// - Throws: An error when the file is missing or is not a valid lexicon.
    init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        self.init(file: try JSONDecoder().decode(File.self, from: data))
    }

    // MARK: - Lookups

    /// Returns the noun reading of a normalized word, if Lexique lists one.
    func noun(_ word: String) -> Noun? {
        nouns[word]
    }

    /// Whether Lexique lists the word as a verb or auxiliary form.
    func isVerb(_ word: String) -> Bool {
        verbs.contains(word)
    }

    /// Whether the word appears anywhere in the lexicon.
    func contains(_ word: String) -> Bool {
        nouns[word] != nil || adjectiveLemmasByForm[word] != nil || verbs.contains(word) || otherWords.contains(word)
    }

    /// Returns the adjective lemmas a form belongs to, such as `["rouge"]` for "rouges".
    func adjectiveLemmas(of form: String) -> [String] {
        adjectiveLemmasByForm[form] ?? []
    }

    /// Returns an adjective's form for a gender and number, or `nil` if Lexique lists none.
    func adjective(lemma: String, gender: Gender, number: GrammaticalNumber) -> String? {
        guard let forms = adjectiveForms[lemma] else { return nil }
        let form = forms[Self.slot(gender: gender, number: number)]
        return form.isEmpty ? nil : form
    }

    /// Returns every gender and number a form of the lemma can serve.
    func readings(of form: String, lemma: String) -> [(gender: Gender, number: GrammaticalNumber)] {
        guard let forms = adjectiveForms[lemma] else { return [] }
        var readings: [(gender: Gender, number: GrammaticalNumber)] = []
        for number in GrammaticalNumber.allCases {
            for gender in Gender.allCases where forms[Self.slot(gender: gender, number: number)] == form {
                readings.append((gender, number))
            }
        }
        return readings
    }

    /// The position of a gender and number in an adjective's four-form list.
    private static func slot(gender: Gender, number: GrammaticalNumber) -> Int {
        (number == .plural ? 2 : 0) + (gender == .feminine ? 1 : 0)
    }
}
