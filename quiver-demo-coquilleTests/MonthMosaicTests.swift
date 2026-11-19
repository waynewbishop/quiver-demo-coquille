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

/// Covers the journal's month of paintings.
@MainActor
final class MonthMosaicTests: XCTestCase {

    private let paris: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return calendar
    }()

    /// Noon on a November 2026 day in Paris.
    private func november(_ day: Int) throws -> Date {
        try XCTUnwrap(paris.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 12)))
    }

    /// An entry on a November day, with a painting line when `painting` is given.
    private func entry(_ day: Int, _ painting: String?, name: String? = nil) throws -> Journal.Entry {
        let text = (painting.map { "//: tableau \($0)\n" } ?? "") + "Bonjour."
        return Journal.Entry(url: URL(filePath: "/tmp/2026-11-\(day)\(name ?? "").txt"), date: try november(day),
                             modified: try november(day), title: nil, text: text)
    }

    /// The summary of November 2026 seen from the 16th.
    private func summary(_ entries: [Journal.Entry]) throws -> MonthSummary {
        MonthSummary(entries: entries, month: try november(10), today: try november(16), calendar: paris)
    }

    /// November 2026 starts on a Sunday, so a Monday-first grid starts with six blanks.
    func testMonthStartsOnMonday() throws {
        let month = try summary([])
        XCTAssertEqual(month.leadingBlanks, 6)
        XCTAssertEqual(month.days.count, 30)
        XCTAssertEqual(month.frenchTitle(calendar: paris), "Novembre 2026")
    }

    /// Days show their painting, a dot without one, and nothing without an entry; later days are future.
    func testDays() throws {
        let month = try summary([try entry(2, "Le thé du matin"), try entry(8, nil), try entry(16, "Le parc")])
        XCTAssertEqual(month.days[1].tableau?.id, "le-the-du-matin")
        XCTAssertNotNil(month.days[7].entryURL)
        XCTAssertNil(month.days[7].tableau)
        XCTAssertNil(month.days[2].entryURL)
        XCTAssertFalse(month.days[15].isFuture)
        XCTAssertTrue(month.days[16].isFuture)
    }

    /// Two entries on one day: the one with a painting is the day's.
    func testADayPrefersTheEntryWithAPainting() throws {
        let month = try summary([try entry(5, nil, name: "a"), try entry(5, "La pluie", name: "b")])
        XCTAssertEqual(month.days[4].tableau?.id, "la-pluie")
        XCTAssertEqual(month.days[4].entryURL?.lastPathComponent, "2026-11-5b.txt")
        XCTAssertEqual(month.entryCount, 2)
    }

    /// The counts line, the words once each in date order, and entries from other months left out.
    func testCountsAndWords() throws {
        let october = Journal.Entry(url: URL(filePath: "/tmp/2026-10-30.txt"),
                                    date: try XCTUnwrap(paris.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 12))),
                                    modified: .now, title: nil, text: "//: tableau La neige\nBonjour.")
        let month = try summary([
            try entry(9, "Le parc"), try entry(3, "Le marché"), try entry(12, "Le parc"), try entry(8, nil), october,
        ])
        XCTAssertEqual(month.countsLine, "4 entries · 3 with a painting")
        XCTAssertEqual(month.words, ["le marché", "le parc"])
    }

    /// The calendar runs from the oldest entry's month to this month, or further to a future-dated entry.
    func testMonthRange() throws {
        let month = { (year: Int, number: Int) in
            try XCTUnwrap(self.paris.date(from: DateComponents(year: year, month: number, day: 1)))
        }
        let today = try november(16)
        let august = Journal.Entry(url: URL(filePath: "/tmp/a.txt"), date: try XCTUnwrap(paris.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 12))),
                                   modified: today, title: nil, text: "Bonjour.")
        let christmas = Journal.Entry(url: URL(filePath: "/tmp/c.txt"), date: try XCTUnwrap(paris.date(from: DateComponents(year: 2026, month: 12, day: 25, hour: 12))),
                                      modified: today, title: nil, text: "Joyeux Noël.")

        XCTAssertEqual(MonthSummary.monthRange(of: [], today: today, calendar: paris), try month(2026, 11)...month(2026, 11))
        XCTAssertEqual(MonthSummary.monthRange(of: [august, try entry(3, nil)], today: today, calendar: paris),
                       try month(2026, 8)...month(2026, 11))
        XCTAssertEqual(MonthSummary.monthRange(of: [august, christmas], today: today, calendar: paris),
                       try month(2026, 8)...month(2026, 12))
    }
}
