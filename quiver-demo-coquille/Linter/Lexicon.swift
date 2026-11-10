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
/// adjective, each past participle's verb, gender and number, each conjugated form's
/// verb, tense and person, and every verb and other known spelling.
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
        /// Past participle → [verb, gender and number code], as for nouns: "mangée" → [["manger", "fs"]].
        let participles: [String: [[String]]]
        /// Conjugated form → [verb, tense-and-person codes], such as "va" → [["aller", "ip3s"]].
        let conjugations: [String: [[String]]]
        let otherWords: [String]
    }

    /// A noun's gender and number; `nil` means the noun serves both.
    struct Noun: Equatable, Sendable {
        let gender: Gender?
        let number: GrammaticalNumber?
    }

    /// One reading of a conjugated form: its verb and the tense-and-person codes it serves,
    /// such as "ip1s" for present, first person singular.
    struct Conjugation: Equatable, Sendable {
        let verb: String
        let codes: Set<String>
    }

    /// A past participle's verb, gender and number; `nil` means the form serves both.
    struct Participle: Equatable, Sendable {
        let verb: String
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
    private let participlesByForm: [String: [Participle]]
    /// Verb → its participle forms, for finding the one a gender and number need.
    private let participleFormsByVerb: [String: [String]]
    private let conjugationsByForm: [String: [Conjugation]]
    /// "verb|code" → the form for it, such as "aller|ip1s" → "vais".
    private let formsByConjugation: [String: String]
    private let otherWords: Set<String>

    /// Builds a lexicon from its decoded file.
    init(file: File) {
        source = file.source
        license = file.license

        var nouns: [String: Noun] = [:]
        nouns.reserveCapacity(file.nouns.count)
        for (word, code) in file.nouns {
            guard let reading = Self.genderAndNumber(code) else { continue }
            nouns[word] = Noun(gender: reading.gender, number: reading.number)
        }
        self.nouns = nouns

        var participlesByForm: [String: [Participle]] = [:]
        var participleFormsByVerb: [String: [String]] = [:]
        for (form, readings) in file.participles {
            for reading in readings where reading.count == 2 {
                guard let code = Self.genderAndNumber(reading[1]) else { continue }
                participlesByForm[form, default: []].append(Participle(verb: reading[0], gender: code.gender, number: code.number))
                participleFormsByVerb[reading[0], default: []].append(form)
            }
        }
        self.participlesByForm = participlesByForm
        self.participleFormsByVerb = participleFormsByVerb.mapValues { $0.sorted() }

        var conjugationsByForm: [String: [Conjugation]] = [:]
        // "verb|code" → candidate forms with how many codes each serves.
        var candidates: [String: [(form: String, breadth: Int)]] = [:]
        for (form, readings) in file.conjugations {
            for reading in readings where reading.count == 2 {
                let codes = Set(reading[1].split(separator: " ").map(String.init))
                conjugationsByForm[form, default: []].append(Conjugation(verb: reading[0], codes: codes))
                for code in codes {
                    candidates[reading[0] + "|" + code, default: []].append((form, codes.count))
                }
            }
        }
        self.conjugationsByForm = conjugationsByForm
        // Where Lexique gives two forms, as "suis" and "es" for être with tu, the form made
        // for fewer persons is the one that belongs to this one.
        formsByConjugation = candidates.compactMapValues { forms in
            forms.min { $0.breadth != $1.breadth ? $0.breadth < $1.breadth : $0.form < $1.form }?.form
        }

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

    /// Whether the word is an infinitive, such as "faire" or "comprendre": a verb form with
    /// an infinitive ending, no participle reading, and no conjugated reading of another verb.
    ///
    /// "ouvre" ends in -re but is a form of ouvrir, so it isn't one. Lexique lists a few
    /// infinitives under their own verb as conjugated forms ("comprendre", ii3s), and
    /// those still count.
    func isInfinitive(_ word: String) -> Bool {
        guard verbs.contains(word), participlesByForm[word] == nil,
              ["er", "ir", "re", "oir"].contains(where: { word.hasSuffix($0) }) else { return false }
        return conjugationsByForm[word]?.allSatisfy { $0.verb == word } ?? true
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

    /// Returns the past-participle readings of a form, such as manger, feminine singular, for "mangée".
    func participles(_ form: String) -> [Participle] {
        participlesByForm[form] ?? []
    }

    /// Returns a verb's past participle for a gender and number, such as "mangé" for manger,
    /// masculine singular, preferring a form made for exactly that gender and number.
    func participle(of verb: String, gender: Gender, number: GrammaticalNumber) -> String? {
        let forms = participleFormsByVerb[verb] ?? []
        let readings = forms.flatMap { form in participles(form).filter { $0.verb == verb }.map { (form, $0) } }
        let exact = readings.first { $0.1.gender == gender && $0.1.number == number }
        let serves = readings.first { ($0.1.gender ?? gender) == gender && ($0.1.number ?? number) == number }
        return (exact ?? serves)?.0
    }

    /// Returns the conjugated readings of a form, such as aller, present, third person singular, for "va".
    func conjugations(_ form: String) -> [Conjugation] {
        conjugationsByForm[form] ?? []
    }

    /// Returns a verb's form for a tense-and-person code, such as "vais" for aller and "ip1s".
    func conjugate(_ verb: String, _ code: String) -> String? {
        formsByConjugation[verb + "|" + code]
    }

    /// Reads a two-letter gender and number code such as "fs" or "mx"; `x` means both.
    /// Any other letter makes the code unreadable, rather than a word of every gender.
    static func genderAndNumber(_ code: String) -> (gender: Gender?, number: GrammaticalNumber?)? {
        let letters = Array(code)
        guard letters.count == 2 else { return nil }
        let gender: Gender?
        switch letters[0] {
        case "m": gender = .masculine
        case "f": gender = .feminine
        case "x": gender = nil
        default: return nil
        }
        let number: GrammaticalNumber?
        switch letters[1] {
        case "s": number = .singular
        case "p": number = .plural
        case "x": number = nil
        default: return nil
        }
        return (gender, number)
    }

    /// The position of a gender and number in an adjective's four-form list.
    private static func slot(gender: Gender, number: GrammaticalNumber) -> Int {
        (number == .plural ? 2 : 0) + (gender == .feminine ? 1 : 0)
    }
}
