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

final class LearnerStatsTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    /// Returns noon on a fixed October 2026 day.
    private func day(_ number: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: number, hour: 12)))
    }

    /// A gender error covering "une fromage" in the sample sentence.
    private let genderIssue = Issue(
        kind: .gender, severity: .error, offset: 3, length: 11,
        original: "une fromage", replacement: "un fromage", reason: "", source: ""
    )

    // Only completed sentences count, and a flagged sentence isn't clean.
    func testRecordsCompletedSentences() throws {
        var stats = LearnerStats()
        stats.record(text: "Un chat. Un une fromage. Un chi", issues: [], on: try day(27), calendar: calendar)
        XCTAssertEqual(stats.sentencesChecked, 2)

        var flagged = LearnerStats()
        flagged.record(text: "Un une fromage.", issues: [genderIssue], on: try day(27), calendar: calendar)
        XCTAssertEqual(flagged.cleanFraction(lastSevenDaysFrom: try day(27), calendar: calendar), 0.0)
        XCTAssertEqual(flagged.weakSpots.first?.kind, .gender)
    }

    // Relinting the same text never counts the same mistake twice.
    func testRelintDoesNotDoubleCount() throws {
        var stats = LearnerStats()
        for _ in 0..<3 {
            stats.record(text: "Un une fromage.", issues: [genderIssue], on: try day(27), calendar: calendar)
        }
        XCTAssertEqual(stats.issueCounts[IssueKind.gender.rawValue], 1)
        XCTAssertEqual(stats.trickyWords, [])
    }

    // A noun missed in two different sentences becomes a tricky word.
    func testTrickyWords() throws {
        var stats = LearnerStats()
        stats.record(text: "Un une fromage.", issues: [genderIssue], on: try day(27), calendar: calendar)
        stats.record(text: "Oh une fromage.", issues: [genderIssue], on: try day(27), calendar: calendar)
        XCTAssertEqual(stats.trickyWords, ["fromage"])
    }

    // The streak counts back from today, or from yesterday before today's first sentence.
    func testStreak() throws {
        var stats = LearnerStats()
        for number in [24, 25, 26] {
            stats.record(text: "Un chat.", issues: [], on: try day(number), calendar: calendar)
        }
        XCTAssertEqual(stats.streak(asOf: try day(26), calendar: calendar), 3)
        XCTAssertEqual(stats.streak(asOf: try day(27), calendar: calendar), 3)
        XCTAssertEqual(stats.streak(asOf: try day(28), calendar: calendar), 0)
    }
}
