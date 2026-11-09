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
import Translation

/// Whether Apple's French–English pack can be used, in the terms Settings shows.
nonisolated enum TranslationPackStatus: Equatable, Sendable {
    case installed
    case notInstalled
    case unsupported

    /// Reads the system's availability answer.
    init(_ status: LanguageAvailability.Status) {
        switch status {
        case .installed: self = .installed
        case .supported: self = .notInstalled
        default: self = .unsupported
        }
    }

    /// The status as Settings words it.
    var label: String {
        switch self {
        case .installed: "Installed"
        case .notInstalled: "Not Installed"
        case .unsupported: "Unsupported"
        }
    }

    /// Whether the learner can ask the system to download the pack.
    var canDownload: Bool {
        self == .notInstalled
    }
}

/// The language pair Settings reports on and downloads.
nonisolated enum TranslationPack {
    static let french = Locale.Language(identifier: "fr")
    static let english = Locale.Language(identifier: "en")

    /// Posted after a download request finishes, so the English pane can try again.
    static let didChange = Notification.Name("CoquilleTranslationPackDidChange")

    /// Asks the system whether the pack is installed.
    static func status() async -> TranslationPackStatus {
        TranslationPackStatus(await LanguageAvailability().status(from: french, to: english))
    }
}
