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

    private let prompts = [
        WritingPrompt(id: "first", text: "First prompt", level: "A1", topic: "One", lesson: "First"),
        WritingPrompt(id: "second", text: "Second prompt", level: "A1", topic: "Two", lesson: "Second")
    ]

    func testBundledCatalogHasUniqueIDsAndAuthoredOrder() {
        let prompts = PromptCatalog.bundled()
        XCTAssertGreaterThan(prompts.count, 1)
        XCTAssertEqual(Set(prompts.map(\.id)).count, prompts.count)
        XCTAssertEqual(prompts.first?.id, "shopping-opening-hours")
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

    func testSameDayAndRolloverUseJSONOrder() throws {
        var calendar = Calendar.current
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 8)))
        let evening = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23)))
        let nextDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 8)))
        let beforeReference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 12)))
        XCTAssertEqual(PromptCatalog.prompt(on: morning, calendar: calendar, from: prompts).id, "first")
        XCTAssertEqual(PromptCatalog.prompt(on: evening, calendar: calendar, from: prompts).id, "first")
        XCTAssertEqual(PromptCatalog.prompt(on: nextDay, calendar: calendar, from: prompts).id, "second")
        XCTAssertEqual(PromptCatalog.prompt(on: beforeReference, calendar: calendar, from: prompts).id, "second")
    }

    func testDaylightSavingTransitionCountsCalendarDays() throws {
        var calendar = Calendar.current
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let before = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12)))
        let transition = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)))
        let after = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12)))
        XCTAssertEqual(PromptCatalog.prompt(on: before, calendar: calendar, from: prompts).id, "second")
        XCTAssertEqual(PromptCatalog.prompt(on: transition, calendar: calendar, from: prompts).id, "first")
        XCTAssertEqual(PromptCatalog.prompt(on: after, calendar: calendar, from: prompts).id, "second")
    }

    func testTimezoneChangeUsesTheLocalDate() throws {
        var utc = Calendar.current
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        var honolulu = utc
        honolulu.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Honolulu"))
        let instant = try XCTUnwrap(utc.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 1, minute: 30)))
        XCTAssertEqual(PromptCatalog.prompt(on: instant, calendar: utc, from: prompts).id, "second")
        XCTAssertEqual(PromptCatalog.prompt(on: instant, calendar: honolulu, from: prompts).id, "first")
    }
}
