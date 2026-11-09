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

/// A validated destination in Coquille. Links carry English prompts, never French answers.
nonisolated enum CoquilleRoute: Equatable, Sendable {
    case today(WritingPrompt)
    case exercise(ExercisePrompt)
    case write
    case phrasebook
    case journal
    case corrections

    /// The links behind the widget's buttons.
    static let writeLink = "coquille://write"
    static let phrasebookLink = "coquille://phrasebook"
    static let journalLink = "coquille://journal"
    static let correctionsLink = "coquille://corrections"

    /// Destinations that take no fields at all.
    private static let destinations: [String: CoquilleRoute] = [
        "write": .write, "phrasebook": .phrasebook, "journal": .journal, "corrections": .corrections,
    ]

    private static let maximumURLLength = 2_048
    private static let maximumPromptCount = 10
    private static let maximumPromptLength = 300
    private static let maximumTitleLength = 120
    private static let maximumHintLength = 300

    /// Builds the widget link for a stable prompt ID without force-unwrapping.
    static func widgetURL(for prompt: WritingPrompt) -> URL? {
        var components = URLComponents()
        components.scheme = "coquille"
        components.host = "today"
        components.queryItems = [URLQueryItem(name: "prompt", value: prompt.id)]
        return components.url
    }

    /// Parses an untrusted custom-scheme URL, returning `nil` for anything unexpected.
    static func parse(_ url: URL, catalog: [WritingPrompt]? = nil) -> CoquilleRoute? {
        guard url.absoluteString.utf8.count <= maximumURLLength,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "coquille",
              components.path.isEmpty,
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.fragment == nil,
              let host = components.host else {
            return nil
        }
        if let destination = destinations[host] {
            return components.query == nil ? destination : nil
        }
        guard let items = components.queryItems else { return nil }

        switch host {
        case "today":
            return parseToday(items: items, catalog: catalog ?? PromptCatalog.bundled())
        case "new":
            return parseExercise(items: items)
        default:
            return nil
        }
    }

    /// Validates exactly one known catalog ID and no other query fields.
    private static func parseToday(items: [URLQueryItem], catalog: [WritingPrompt]) -> CoquilleRoute? {
        guard items.allSatisfy({ $0.name == "prompt" }), items.count == 1,
              let id = items.first?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty,
              let prompt = catalog.first(where: { $0.id == id }) else {
            return nil
        }
        return .today(prompt)
    }

    /// Validates a complete exercise before the learner is asked to confirm it.
    private static func parseExercise(items: [URLQueryItem]) -> CoquilleRoute? {
        let allowedFields = Set(["title", "prompt", "hint"])
        guard items.allSatisfy({ allowedFields.contains($0.name) && $0.value != nil }) else {
            return nil
        }

        let promptItems = items.filter { $0.name == "prompt" }
        guard (1...maximumPromptCount).contains(promptItems.count) else { return nil }
        let prompts = promptItems.map { $0.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        guard prompts.allSatisfy({
            !$0.isEmpty && $0.count <= maximumPromptLength && $0.allSatisfy { !$0.isNewline }
        }) else { return nil }

        let titleItems = items.filter { $0.name == "title" }
        let hintItems = items.filter { $0.name == "hint" }
        guard titleItems.count <= 1, hintItems.count <= 1 else { return nil }

        let title = titleItems.first?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hint = hintItems.first?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard title.count <= maximumTitleLength, hint.count <= maximumHintLength else { return nil }

        return .exercise(ExercisePrompt(
            title: title.isEmpty ? "Exercise" : title,
            prompts: prompts,
            hint: hint.isEmpty ? nil : hint
        ))
    }
}
