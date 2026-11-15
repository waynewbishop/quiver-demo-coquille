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

/// Supplies today's prompt and painting, changing each local midnight.
struct TableauProvider: TimelineProvider {

    /// Shows a fixed prompt while the widget loads.
    func placeholder(in context: Context) -> TableauEntry {
        .sample
    }

    /// Shows a fixed prompt in the widget gallery, and the real day otherwise.
    func getSnapshot(in context: Context, completion: @escaping (TableauEntry) -> Void) {
        completion(context.isPreview ? .sample : .make(on: .now))
    }

    /// Refreshes just after the next local midnight rather than after a fixed 24 hours.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TableauEntry>) -> Void) {
        let now = Date.now
        let calendar = Calendar.current
        let entry = TableauEntry.make(on: now, calendar: calendar)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
              let refresh = calendar.date(byAdding: .minute, value: 1, to: tomorrow) else {
            completion(Timeline(entries: [entry], policy: .atEnd))
            return
        }
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}
