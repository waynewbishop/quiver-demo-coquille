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
        original: "une fromage", replacement: "un fromage", reason: "", hint: "", source: ""
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
        XCTAssertEqual(stats.wordMistakes["fromage"], 1)
    }

    // A missed noun becomes a tricky word, and the most missed words come first.
    func testTrickyWords() throws {
        var stats = LearnerStats()
        stats.record(text: "Un une fromage.", issues: [genderIssue], on: try day(27), calendar: calendar)
        XCTAssertEqual(stats.trickyWords, ["fromage"])

        let spellingIssue = Issue(
            kind: .spelling, severity: .error, offset: 4, length: 7,
            original: "gentile", replacement: "gentille", reason: "", hint: "", source: ""
        )
        stats.record(text: "Oh une fromage.", issues: [genderIssue], on: try day(27), calendar: calendar)
        stats.record(text: "Il gentile.", issues: [spellingIssue], on: try day(27), calendar: calendar)
        XCTAssertEqual(stats.trickyWords, ["fromage", "gentille"])
    }

    // Spelling, agreement and accent misses count under the correct word; look-alikes don't count.
    func testMissedWordKinds() {
        let agreement = Issue(kind: .agreement, severity: .error, offset: 0, length: 5, original: "rouge", replacement: "rouges", reason: "", hint: "", source: "")
        let unknown = Issue(kind: .spelling, severity: .warning, offset: 0, length: 4, original: "Ahdo", replacement: nil, reason: "", hint: "", source: "")
        let lookAlike = Issue(kind: .lookAlike, severity: .error, offset: 0, length: 4, original: "cava", replacement: "ça va", reason: "", hint: "", source: "")
        XCTAssertEqual(LearnerStats.missedWord(in: genderIssue), "fromage")
        XCTAssertEqual(LearnerStats.missedWord(in: agreement), "rouges")
        let accent = Issue(kind: .accent, severity: .error, offset: 0, length: 1, original: "a", replacement: "à", reason: "", hint: "", source: "")
        XCTAssertEqual(LearnerStats.missedWord(in: accent), "à")
        XCTAssertNil(LearnerStats.missedWord(in: unknown))
        XCTAssertNil(LearnerStats.missedWord(in: lookAlike))
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

    // Stats saved before fixedByLearner existed still load, starting it at zero.
    func testDecodesStatsWithoutFixedByLearner() throws {
        let json = #"{"days":{},"issueCounts":{"gender":2},"nounMistakes":{},"errorsFixed":3,"countedIssues":[]}"#
        let stats = try JSONDecoder().decode(LearnerStats.self, from: Data(json.utf8))
        XCTAssertEqual(stats.errorsFixed, 3)
        XCTAssertEqual(stats.fixedByLearner, 0)
        XCTAssertEqual(stats.issueCounts["gender"], 2)
    }

    // Saved tricky words survive the rename from nouns to words.
    func testDecodesSavedNounMistakes() throws {
        let json = #"{"days":{},"issueCounts":{},"nounMistakes":{"fromage":2},"errorsFixed":0,"countedIssues":[]}"#
        let stats = try JSONDecoder().decode(LearnerStats.self, from: Data(json.utf8))
        XCTAssertEqual(stats.trickyWords, ["fromage"])
        XCTAssertTrue(try String(decoding: JSONEncoder().encode(stats), as: UTF8.self).contains("nounMistakes"))
    }
}
