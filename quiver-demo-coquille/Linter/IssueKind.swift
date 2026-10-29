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

/// The rule family that raised an issue. Learner stats are counted per kind.
nonisolated enum IssueKind: String, CaseIterable, Codable, Equatable, Sendable {
    case spelling
    case gender
    case contraction
    case agreement
    case lookAlike
    case negation
    case idiom

    /// The short uppercase label shown at the top of an issue card.
    var label: String {
        switch self {
        case .spelling: "SPELLING"
        case .gender: "GENDER"
        case .contraction: "CONTRACTION"
        case .agreement: "AGREEMENT"
        case .lookAlike: "LOOK-ALIKE"
        case .negation: "NEGATION"
        case .idiom: "IDIOM"
        }
    }

    /// The name used for this kind in the learner's weak spots.
    var displayName: String {
        switch self {
        case .spelling: "Spelling"
        case .gender: "Noun gender"
        case .contraction: "Contractions (à + le)"
        case .agreement: "Adjective agreement"
        case .lookAlike: "Look-alike words (ça va)"
        case .negation: "Negation (ne… plus)"
        case .idiom: "Idioms"
        }
    }
}
