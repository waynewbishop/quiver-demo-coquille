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
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// A word the system spellchecker doesn't recognize, with its guesses.
nonisolated struct Misspelling: Equatable, Sendable {
    /// Character offset of the word.
    let offset: Int
    /// The word as typed.
    let word: String
    /// The spellchecker's suggestions, in its own order.
    let guesses: [String]
}

/// Finds misspelled words. iOS and macOS each supply their own system spellchecker,
/// which is the main platform difference in this universal app.
protocol SpellChecker {
    /// Returns every misspelled word in `text`, in order.
    func misspellings(in text: String) -> [Misspelling]
}

/// The system spellchecker for the active language: `UITextChecker` on iOS and
/// `NSSpellChecker` on macOS.
struct SystemSpellChecker: SpellChecker {

    /// The spellchecker language, such as "fr" or "fr_FR".
    let language: String

    /// Returns every misspelled word in `text`, in order.
    func misspellings(in text: String) -> [Misspelling] {
        let string = text as NSString
        var misspellings: [Misspelling] = []
        var location = 0
        while location < string.length {
            let range = nextMisspelledRange(in: text, from: location)
            guard range.location != NSNotFound, range.length > 0,
                  let wordRange = Range(range, in: text) else { break }
            misspellings.append(Misspelling(
                offset: text.distance(from: text.startIndex, to: wordRange.lowerBound),
                word: String(text[wordRange]),
                guesses: guesses(for: range, in: text)
            ))
            location = range.location + range.length
        }
        return misspellings
    }

    #if os(iOS)
    private let checker = UITextChecker()

    /// Finds the next misspelled word at or after a UTF-16 location.
    private func nextMisspelledRange(in text: String, from location: Int) -> NSRange {
        let length = (text as NSString).length
        return checker.rangeOfMisspelledWord(
            in: text, range: NSRange(location: 0, length: length),
            startingAt: location, wrap: false, language: language
        )
    }

    /// Returns the system's guesses for a misspelled word.
    private func guesses(for range: NSRange, in text: String) -> [String] {
        checker.guesses(forWordRange: range, in: text, language: language) ?? []
    }
    #elseif os(macOS)
    /// Finds the next misspelled word at or after a UTF-16 location.
    private func nextMisspelledRange(in text: String, from location: Int) -> NSRange {
        NSSpellChecker.shared.checkSpelling(
            of: text, startingAt: location, language: language,
            wrap: false, inSpellDocumentWithTag: 0, wordCount: nil
        )
    }

    /// Returns the system's guesses for a misspelled word.
    private func guesses(for range: NSRange, in text: String) -> [String] {
        NSSpellChecker.shared.guesses(
            forWordRange: range, in: text, language: language, inSpellDocumentWithTag: 0
        ) ?? []
    }
    #endif
}
