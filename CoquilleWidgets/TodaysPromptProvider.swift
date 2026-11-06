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

import WidgetKit

/// Supplies the local daily prompt without networking or app-container state.
struct TodaysPromptProvider: TimelineProvider {

    func placeholder(in context: Context) -> TodaysPromptEntry {
        TodaysPromptEntry(date: .now, prompt: PromptCatalog.bundled().first ?? PromptCatalog.fallback)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodaysPromptEntry) -> Void) {
        completion(TodaysPromptEntry(date: .now, prompt: PromptCatalog.prompt()))
    }

    /// Refreshes just after the next local midnight rather than after a fixed 24 hours.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodaysPromptEntry>) -> Void) {
        let now = Date.now
        let calendar = Calendar.current
        let entry = TodaysPromptEntry(date: now, prompt: PromptCatalog.prompt(on: now, calendar: calendar))
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
              let refresh = calendar.date(byAdding: .minute, value: 1, to: tomorrow) else {
            completion(Timeline(entries: [entry], policy: .atEnd))
            return
        }
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}
