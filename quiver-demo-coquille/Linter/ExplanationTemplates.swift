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
    case contraction
    case agreementGender
    case agreementNumber
    case agreementGenderAndNumber
    case spelling
    case unknownWord
    case negation
    case idiom
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

    private let entries: [ExplanationKey: Entry]

    /// Decodes the templates and checks that every key has an entry.
    ///
    /// - Throws: `MissingEntry` when a key has no template, or a decoding error.
    init(data: Data) throws {
        let decoded = try JSONDecoder().decode([String: Entry].self, from: data)
        var entries: [ExplanationKey: Entry] = [:]
        for key in ExplanationKey.allCases {
            guard let entry = decoded[key.rawValue] else {
                throw MissingEntry(key: key.rawValue)
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

    /// Replaces each `{name}` in `text` with its value.
    private static func fill(_ text: String, _ values: [String: String]) -> String {
        var text = text
        for (name, value) in values {
            text = text.replacingOccurrences(of: "{\(name)}", with: value)
        }
        return text
    }
}
