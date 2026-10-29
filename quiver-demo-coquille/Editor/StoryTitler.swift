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

/// Names the learner's story in a few French words for the Mac window title.
///
/// A small extra, not part of the linter: it uses Apple's on-device language model,
/// so it needs Apple Intelligence. Without it, the window keeps the app's name. It
/// only ever sees French with no errors, so it can't quietly correct a mistake.
enum StoryTitler {

    /// A short French title for a journal entry.
    @Generable
    struct StoryTitle {
        @Guide(description: "A title in French, two to five words, with no final punctuation.")
        let title: String
    }

    /// Returns a short French title for correct French, or `nil` when the model isn't
    /// available or fails.
    static func title(for text: String) async -> String? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability,
              model.supportsLocale(Locale(identifier: "fr")) else { return nil }
        let session = LanguageModelSession(instructions: """
            Write a short French title for a learner's French journal entry. Use only \
            words and ideas from the entry. Never correct, translate or add to it.
            """)
        do {
            let response = try await session.respond(to: text, generating: StoryTitle.self)
            let title = response.content.title.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            return title.isEmpty ? nil : title
        } catch {
            return nil
        }
    }
}
