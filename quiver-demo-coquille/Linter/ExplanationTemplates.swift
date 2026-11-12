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

/// The explanation each rule fills in, one per verdict.
nonisolated enum ExplanationKey: String, CaseIterable, Codable, Sendable {
    case articleGender
    case articleGenderPredicted
    case contractedGender
    case articleNumberPlural
    case articleNumberSingular
    case contraction
    case agreementGender
    case agreementNumber
    case agreementGenderAndNumber
    case spelling
    case unknownWord
    case runTogether
    case lookAlike
    case enArticle
    case wordChoice
    case negation
    case idiom
    case accentAfterVerb
    case accentAfterJusqu
    case accentAfterDans
    case accentAfterAdjective
    case graveAfterSubject
    case graveInIlYA
    case auxiliaryChoice
    case participleWithAvoir
    case participleWithEtre
    case generalArticle
    case subjectVerb
    case nearFutureInfinitive
    case siClause
    case subjunctive
    case meaning
    case etOrEst
    case preposition
    case placePreposition
    case elision
    case elisionContraction
    case possessiveGender
    case possessiveBeforeVowel
    case reflexiveAuxiliary
    case sentenceCapital
    case lowercaseDayOrMonth
    case lowercaseLanguage
    case lowercaseNationality
    case lowercaseJe

    /// The placeholders the rule fills for this key. A template may use any of them and no others.
    var placeholders: Set<String> {
        switch self {
        case .articleGender: ["noun", "gender", "article"]
        case .articleGenderPredicted: ["noun", "gender", "reason", "article"]
        case .contractedGender: ["noun", "gender", "preposition", "article"]
        case .articleNumberPlural: ["noun", "article"]
        case .articleNumberSingular: ["article", "fix"]
        case .contraction: ["preposition", "article", "contraction"]
        case .agreementGender, .agreementNumber, .agreementGenderAndNumber: ["noun", "gender", "number"]
        case .spelling: ["word", "suggestion", "where"]
        case .unknownWord: ["word"]
        case .runTogether: ["word", "fix"]
        case .lookAlike, .wordChoice, .preposition: ["note", "fix"]
        case .placePreposition: ["place", "reason", "fix"]
        case .enArticle: ["fix"]
        case .negation: ["corrected"]
        case .idiom: ["suggestion", "note"]
        case .accentAfterVerb: ["verb"]
        case .accentAfterJusqu, .accentAfterDans, .graveInIlYA: []
        case .accentAfterAdjective: ["adjective"]
        case .graveAfterSubject: ["subject"]
        case .auxiliaryChoice: ["verb", "fix"]
        case .participleWithAvoir: ["fix"]
        case .participleWithEtre: ["subject", "fix"]
        case .generalArticle: ["verb", "fix"]
        case .subjectVerb: ["subject", "verb", "fix"]
        case .nearFutureInfinitive: ["fix"]
        case .siClause: ["tense", "fix"]
        case .subjunctive: ["trigger", "fix"]
        case .meaning: ["note"]
        case .etOrEst: ["fix"]
        case .elision, .elisionContraction: ["word", "fix"]
        case .sentenceCapital, .lowercaseDayOrMonth, .lowercaseLanguage, .lowercaseNationality, .lowercaseJe: ["word", "fix"]
        case .possessiveGender: ["noun", "gender", "fix"]
        case .possessiveBeforeVowel, .reflexiveAuxiliary: ["fix"]
        }
    }
}

/// A verdict worded twice: a hint that names the rule without the answer, and the
/// full reason shown once the learner asks for the fix.
nonisolated struct Explanation: Equatable, Sendable {
    let hint: String
    let reason: String
}

/// The bundled explanation templates, such as "{noun} is {gender}, so the article is {article}."
///
/// The rules decide every verdict; a template only words it. Editing the JSON file
/// changes the explanations without touching code.
nonisolated struct ExplanationTemplates: Sendable {

    /// One template, its hint, and a worked example, as stored in `fr.explanations.json`.
    struct Entry: Codable, Sendable {
        /// The rule without the answer, so the learner can try the fix first. Falls back to `template`.
        let hint: String?
        let template: String
        let example: String
    }

    /// Thrown when the templates file lacks an entry a rule needs.
    struct MissingEntry: Error, Equatable {
        let key: String
    }

    /// Thrown when a template names a placeholder its rule never fills, which would
    /// otherwise show the learner a raw "{name}".
    struct UnknownPlaceholder: Error, Equatable {
        let key: String
        let placeholder: String
    }

    private let entries: [ExplanationKey: Entry]

    /// Decodes the templates and checks that every key has an entry whose placeholders its rule fills.
    ///
    /// - Throws: `MissingEntry` when a key has no template, `UnknownPlaceholder` when a
    ///   hint or template names a value its rule never supplies, or a decoding error.
    init(data: Data) throws {
        let decoded = try JSONDecoder().decode([String: Entry].self, from: data)
        var entries: [ExplanationKey: Entry] = [:]
        for key in ExplanationKey.allCases {
            guard let entry = decoded[key.rawValue] else {
                throw MissingEntry(key: key.rawValue)
            }
            for text in [entry.template, entry.hint ?? ""] {
                if let unknown = Self.placeholders(in: text).subtracting(key.placeholders).sorted().first {
                    throw UnknownPlaceholder(key: key.rawValue, placeholder: unknown)
                }
            }
            entries[key] = entry
        }
        self.entries = entries
    }

    /// Fills the hint's and the template's `{placeholders}` with the given values.
    func render(_ key: ExplanationKey, _ values: [String: String]) -> Explanation {
        guard let entry = entries[key] else {
            preconditionFailure("Explanation templates were validated at load; \(key.rawValue) is missing")
        }
        let reason = Self.fill(entry.template, values)
        return Explanation(hint: entry.hint.map { Self.fill($0, values) } ?? reason, reason: reason)
    }

    /// Returns the `{name}` placeholders in `text`.
    static func placeholders(in text: String) -> Set<String> {
        Set(text.matches(of: /\{([A-Za-z]+)\}/).map { String($0.output.1) })
    }

    /// Replaces each `{name}` in `text` with its value.
    private static func fill(_ text: String, _ values: [String: String]) -> String {
        var text = text
        for (name, value) in values {
            text = text.replacingOccurrences(of: "{\(name)}", with: value)
        }
        return text
    }
}
