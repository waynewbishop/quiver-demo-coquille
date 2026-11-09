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

import XCTest
@testable import quiver_demo_coquille

/// Checks bundled prompt content and deterministic calendar-day selection.
final class PromptCatalogTests: XCTestCase {

    private let prompts = ["a", "b", "c", "d", "e"].map {
        WritingPrompt(id: $0, text: "Prompt \($0)", level: "A1", topic: "Topic", lesson: "Lesson")
    }

    /// Returns the prompt id for noon on a date, in UTC, as the fixed day to compare against.
    private func id(year: Int, month: Int, day: Int) throws -> String {
        var utc = Calendar.current
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let date = try XCTUnwrap(utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
        return PromptCatalog.prompt(on: date, calendar: utc, from: prompts).id
    }

    func testBundledCatalogHasUniqueIDsAndAuthoredOrder() {
        let prompts = PromptCatalog.bundled()
        XCTAssertGreaterThan(prompts.count, 1)
        XCTAssertEqual(Set(prompts.map(\.id)).count, prompts.count)
        XCTAssertEqual(prompts.first?.id, "daily-life-morning")
        XCTAssertEqual(prompts.count, 14)
        XCTAssertEqual(prompts.compactMap(\.starter), ["Il fait ", "Je suis à ", "Je me sens ", "Je porte "])
    }

    func testDecodePreservesOrderAndRejectsUnusableData() throws {
        let data = try XCTUnwrap("""
        [
          {"id":"z","text":"First written","level":"A1","topic":"A","lesson":"A"},
          {"id":"a","text":"Second written","level":"A1","topic":"B","lesson":"B"}
        ]
        """.data(using: .utf8))
        XCTAssertEqual(PromptCatalog.decode(data).map(\.id), ["z", "a"])
        XCTAssertEqual(PromptCatalog.decode(Data()).map(\.id), [PromptCatalog.fallback.id])
        XCTAssertEqual(PromptCatalog.decode(Data("not json".utf8)).map(\.id), [PromptCatalog.fallback.id])
        XCTAssertEqual(PromptCatalog.prompt(on: .now, calendar: .current, from: []), PromptCatalog.fallback)
    }

    func testPromptHoldsAllDayAndNeverRepeatsOnTheNextDay() throws {
        var calendar = Calendar.current
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 8)))
        let evening = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23)))
        XCTAssertEqual(PromptCatalog.prompt(on: morning, calendar: calendar, from: prompts), PromptCatalog.prompt(on: evening, calendar: calendar, from: prompts))

        var previous: String?
        for offset in -100..<400 {
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: morning))
            let id = PromptCatalog.prompt(on: date, calendar: calendar, from: prompts).id
            XCTAssertNotEqual(id, previous)
            previous = id
        }
    }

    func testEachRoundUsesEveryPromptOnce() throws {
        var calendar = Calendar.current
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12)))
        for round in 0..<20 {
            let ids = try (0..<prompts.count).map { day in
                let date = try XCTUnwrap(calendar.date(byAdding: .day, value: round * prompts.count + day, to: start))
                return PromptCatalog.prompt(on: date, calendar: calendar, from: prompts).id
            }
            XCTAssertEqual(Set(ids).count, prompts.count)
        }
    }

    func testPromptCarriesItsOptionalStarter() throws {
        let data = try XCTUnwrap("""
        [{"id":"z","text":"Q","level":"A1","topic":"A","lesson":"A","starter":"Il fait "},
         {"id":"a","text":"R","level":"A1","topic":"B","lesson":"B"}]
        """.data(using: .utf8))
        XCTAssertEqual(PromptCatalog.decode(data).map(\.starter), ["Il fait ", nil])
    }

    func testDaylightSavingTransitionCountsCalendarDays() throws {
        var calendar = Calendar.current
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let before = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12)))
        let transition = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)))
        let after = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12)))
        XCTAssertEqual(PromptCatalog.prompt(on: before, calendar: calendar, from: prompts).id, try id(year: 2026, month: 3, day: 7))
        XCTAssertEqual(PromptCatalog.prompt(on: transition, calendar: calendar, from: prompts).id, try id(year: 2026, month: 3, day: 8))
        XCTAssertEqual(PromptCatalog.prompt(on: after, calendar: calendar, from: prompts).id, try id(year: 2026, month: 3, day: 9))
    }

    func testTimezoneChangeUsesTheLocalDate() throws {
        var utc = Calendar.current
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        var honolulu = utc
        honolulu.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Honolulu"))
        let instant = try XCTUnwrap(utc.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 1, minute: 30)))
        XCTAssertEqual(PromptCatalog.prompt(on: instant, calendar: utc, from: prompts).id, try id(year: 2026, month: 1, day: 2))
        XCTAssertEqual(PromptCatalog.prompt(on: instant, calendar: honolulu, from: prompts).id, try id(year: 2026, month: 1, day: 1))
    }
}
