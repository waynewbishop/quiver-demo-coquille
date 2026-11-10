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

/// Why a translation couldn't be shown.
nonisolated enum TranslationUnavailable: Error, Equatable {
    /// The language pair is supported but its on-device pack isn't downloaded.
    case notInstalled
    /// The device can't translate this language pair at all.
    case unsupported
}

/// Translates the learner's French into English.
protocol Translator {
    /// Returns the translation of `text`.
    ///
    /// - Throws: `TranslationUnavailable` when the on-device language pack is missing,
    ///   or the framework's own error if translation fails.
    func translate(_ text: String) async throws -> String
}

/// Translates on-device with Apple's Translation framework, using an installed language pack.
struct AppleTranslator: Translator {

    let source: Locale.Language
    let target: Locale.Language

    /// Returns the translation of `text`, asking about the pack only if translating fails,
    /// so a momentarily wrong availability answer can't block a translation that would work.
    func translate(_ text: String) async throws -> String {
        do {
            let translated = try await Self.translate(text, from: source, to: target)
            return Self.matchingLineBreaks(of: text, in: translated)
        } catch {
            switch await LanguageAvailability().status(from: source, to: target) {
            case .installed:
                throw error
            case .supported:
                throw TranslationUnavailable.notInstalled
            default:
                throw TranslationUnavailable.unsupported
            }
        }
    }

    /// Returns `translation` laid out line for line like `source`.
    ///
    /// The Translation framework puts a blank line after every line of its output, whether
    /// the source had a blank line there or not, so the two panes would drift apart. The
    /// text is still translated whole, to keep the context between lines, and only the
    /// layout is rebuilt. If the line counts differ, the translation is returned untouched.
    nonisolated static func matchingLineBreaks(of source: String, in translation: String) -> String {
        let sourceLines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let translatedLines = translation.split(whereSeparator: \.isNewline).filter { !$0.allSatisfy(\.isWhitespace) }
        guard sourceLines.filter({ !$0.allSatisfy(\.isWhitespace) }).count == translatedLines.count else { return translation }
        var remaining = translatedLines.makeIterator()
        return sourceLines.map { line in
            line.allSatisfy(\.isWhitespace) ? "" : String(remaining.next() ?? "")
        }.joined(separator: "\n")
    }

    /// Runs one translation off the main actor. The session isn't Sendable, so it is
    /// created and used entirely inside this function rather than shared.
    @concurrent
    private nonisolated static func translate(
        _ text: String,
        from source: Locale.Language,
        to target: Locale.Language
    ) async throws -> String {
        let session = TranslationSession(installedSource: source, target: target)
        return try await session.translate(text).targetText
    }
}
