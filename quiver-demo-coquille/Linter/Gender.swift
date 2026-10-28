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

/// A noun's grammatical gender.
///
/// Stored as classes rather than a Boolean so a language with a neuter gender can
/// add a case later without changing how genders flow through the linter.
nonisolated enum Gender: String, CaseIterable, Codable, Equatable, Sendable {
    case masculine
    case feminine

    /// The singular definite article for this gender.
    var definiteArticle: String {
        self == .masculine ? "le" : "la"
    }

    /// The singular indefinite article for this gender.
    var indefiniteArticle: String {
        self == .masculine ? "un" : "une"
    }
}

/// Whether a word is singular or plural.
nonisolated enum GrammaticalNumber: String, CaseIterable, Codable, Equatable, Sendable {
    case singular
    case plural
}
