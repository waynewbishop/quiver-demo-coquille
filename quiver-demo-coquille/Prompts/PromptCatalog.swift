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

/// Loads the bundled prompts and chooses one by whole local calendar day.
nonisolated enum PromptCatalog {

    /// A usable prompt when the bundled resource cannot be read.
    static let fallback = WritingPrompt(
        id: "daily-life-today",
        text: "What did you do today?",
        level: "A1",
        topic: "Daily life",
        lesson: "Your day"
    )

    /// Decodes prompts in their authored order, falling back when the data is unusable.
    static func decode(_ data: Data) -> [WritingPrompt] {
        guard let prompts = try? JSONDecoder().decode([WritingPrompt].self, from: data), !prompts.isEmpty else {
            return [fallback]
        }
        return prompts
    }

    /// The main bundle's prompts, decoded once per process.
    private static let mainBundled = load(from: .main)

    /// Loads the prompt list from a target's own bundle, reusing the decoded main bundle.
    static func bundled(in bundle: Bundle = .main) -> [WritingPrompt] {
        bundle == .main ? mainBundled : load(from: bundle)
    }

    /// Reads and decodes `fr.prompts.json` from `bundle`, falling back when it can't be read.
    private static func load(from bundle: Bundle) -> [WritingPrompt] {
        guard let url = bundle.url(forResource: "fr.prompts", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return [fallback]
        }
        return decode(data)
    }

    /// Returns the prompt with a stable catalog ID, or `nil` for an unknown ID.
    static func prompt(withID id: String, in bundle: Bundle = .main) -> WritingPrompt? {
        bundled(in: bundle).first { $0.id == id }
    }

    /// Chooses the bundled prompt for a local calendar day.
    static func prompt(on date: Date = .now, calendar: Calendar = .current, in bundle: Bundle = .main) -> WritingPrompt {
        prompt(on: date, calendar: calendar, from: bundled(in: bundle))
    }

    /// Chooses from `prompts` using calendar-day arithmetic, including across DST changes.
    static func prompt(on date: Date, calendar: Calendar, from prompts: [WritingPrompt]) -> WritingPrompt {
        guard !prompts.isEmpty,
              let reference = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)),
              let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: reference),
                to: calendar.startOfDay(for: date)
              ).day else {
            return fallback
        }
        let remainder = days % prompts.count
        let index = remainder < 0 ? remainder + prompts.count : remainder
        return prompts[index]
    }
}
