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
import FoundationModels

/// Explains the phrases worth knowing in the learner's French, for the Explain dialog.
///
/// Like `StoryTitler`, it uses Apple's on-device language model, so it needs Apple
/// Intelligence. It only ever sees French with no errors, so it can't explain a mistake
/// as if it were right. Its notes are the model's, not the linter's rules.
enum PassageExplainer {

    /// The phrases worth knowing in a passage.
    @Generable
    struct Explanation {
        @Guide(description: "The phrases in the passage most worth explaining to an English speaker learning French, in the order they appear in the passage.", .maximumCount(4))
        let phrases: [Phrase]
    }

    /// One phrase from the passage and what it means.
    @Generable
    struct Phrase {
        @Guide(description: "The French phrase as it appears in the passage, or a verb idiom in its dictionary form, such as avoir hâte de. At most five words.")
        let french: String
        @Guide(description: "What the phrase means in natural English, in a few words, with no final punctuation.")
        let meaning: String
        @Guide(description: "One short sentence on why it's worth noticing, such as an idiom or a tense.")
        let note: String
    }

    /// The most words a phrase can have and still be shown.
    static let maximumWords = 5

    /// What came of asking the model to explain a passage.
    enum Outcome {
        case explained([Phrase])
        /// The passage is longer than the model can read at once.
        case tooLong
        case failed
    }

    /// Whether the on-device model is ready to explain French on this device.
    static var isAvailable: Bool {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return false }
        return model.supportsLocale(Locale(identifier: "fr"))
    }

    /// Explains the phrases worth knowing in correct French.
    static func explain(_ text: String) async -> Outcome {
        guard isAvailable else { return .failed }
        let session = LanguageModelSession(instructions: """
            An English speaker learning French wrote this passage, and its French is \
            correct. Pick the phrases most worth explaining: idioms, tenses, and words \
            whose meaning differs from English. Keep each phrase to five words or fewer. \
            Explain each in plain English. French has one present tense, so je mange \
            means both I eat and I'm eating. Call something a contraction only when two \
            words have merged in the passage, such as du for de + le. Never say where a \
            word comes from or what it is short for. Never correct, rewrite or translate \
            the whole passage.
            """)
        do {
            let response = try await session.respond(to: text, generating: Explanation.self)
            let short = shortPhrases(response.content.phrases, french: \.french)
            return .explained(inPassageOrder(short, french: \.french, in: text))
        } catch LanguageModelError.contextSizeExceeded {
            return .tooLong
        } catch {
            return .failed
        }
    }

    /// Keeps only the items whose French is `maximumWords` words or fewer, since the
    /// model doesn't always follow its guide.
    ///
    /// Words are split on spaces, so an elision such as "j'ai" counts as one word.
    static func shortPhrases<Item>(_ items: [Item], french: (Item) -> String) -> [Item] {
        items.filter { french($0).split(whereSeparator: \.isWhitespace).count <= maximumWords }
    }

    /// Puts `items` in the order their French first appears in `text`, so the bullets
    /// read in the same order as the passage.
    ///
    /// A phrase in its dictionary form, such as "avoir hâte de" for "j'ai hâte de", is
    /// placed by its longest word that's in the text. One that can't be found at all goes
    /// last, and ties keep the model's order.
    static func inPassageOrder<Item>(_ items: [Item], french: (Item) -> String, in text: String) -> [Item] {
        items.enumerated()
            .map { (index: $0.offset, item: $0.element, position: position(of: french($0.element), in: text) ?? .max) }
            .sorted { ($0.position, $0.index) < ($1.position, $1.index) }
            .map(\.item)
    }

    /// The character offset where `phrase` first appears in `text`, ignoring case and
    /// accents, or where its longest findable word of three or more letters does.
    private static func position(of phrase: String, in text: String) -> Int? {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let offset = { (range: Range<String.Index>) in text.distance(from: text.startIndex, to: range.lowerBound) }
        if let range = text.range(of: phrase, options: options) {
            return offset(range)
        }
        let words: [Substring] = phrase.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 3 }
        let longestFirst = words.sorted { $0.count > $1.count }
        for word in longestFirst {
            if let range = text.range(of: word, options: options) {
                return offset(range)
            }
        }
        return nil
    }
}
