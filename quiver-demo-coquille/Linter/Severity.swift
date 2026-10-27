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

/// How serious a linter issue is, modeled on the layers of compiler and linter feedback.
///
/// An error is French that would not "compile" and blocks playback and translation
/// until it is fixed or ignored. A warning is valid but risky or ambiguous French.
/// A suggestion is correct French with a more idiomatic alternative.
nonisolated enum Severity: String, CaseIterable, Codable, Equatable, Sendable {
    case error
    case warning
    case suggestion

    /// Whether an unresolved issue of this severity keeps playback and translation locked.
    var blocksPlayback: Bool {
        self == .error
    }
}
