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
import WidgetKit

/// One day of the week strip on the large and extra-large widgets.
struct TableauDay: Identifiable {
    let date: Date
    /// The French weekday initial: L M M J V S D.
    let initial: String
    let tableau: Tableau?
    let isToday: Bool

    var id: Date { date }
}

/// Today's prompt and painting, and this week's days.
struct TableauEntry: TimelineEntry {
    let date: Date
    let prompt: WritingPrompt
    let tableau: Tableau?
    /// Monday to Sunday of the current week.
    let week: [TableauDay]

    /// Builds the entry for `date`'s local day from the prompt rotation.
    static func make(on date: Date, calendar: Calendar = .current) -> TableauEntry {
        let prompt = PromptCatalog.prompt(on: date, calendar: calendar)
        return TableauEntry(
            date: date,
            prompt: prompt,
            tableau: TableauCatalog.tableau(for: prompt),
            week: week(around: date, calendar: calendar)
        )
    }

    /// A fixed entry for the widget gallery and previews.
    static var sample: TableauEntry {
        let prompt = PromptCatalog.prompt(withID: "weather-outside") ?? PromptCatalog.fallback
        let today = Date.now
        return TableauEntry(
            date: today,
            prompt: prompt,
            tableau: TableauCatalog.tableau(for: prompt),
            week: week(around: today, calendar: .current)
        )
    }

    /// The seven days of `date`'s week, always starting on Monday.
    private static func week(around date: Date, calendar: Calendar) -> [TableauDay] {
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        let today = calendar.startOfDay(for: date)
        guard let monday = mondayFirst.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        let initials = ["L", "M", "M", "J", "V", "S", "D"]
        return initials.enumerated().compactMap { offset, initial in
            guard let day = calendar.date(byAdding: .day, value: offset, to: monday) else { return nil }
            let prompt = PromptCatalog.prompt(on: day, calendar: calendar)
            return TableauDay(
                date: day,
                initial: initial,
                tableau: TableauCatalog.tableau(for: prompt),
                isToday: calendar.isDate(day, inSameDayAs: today)
            )
        }
    }
}
