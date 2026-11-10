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

        // A clean sentence relinted with a mistake stops being clean, and starts again once fixed.
        var relinted = LearnerStats()
        relinted.record(text: "Un une fromage.", issues: [], on: try day(27), calendar: calendar)
        XCTAssertEqual(relinted.cleanFraction(lastSevenDaysFrom: try day(27), calendar: calendar), 1.0)
        relinted.record(text: "Un une fromage.", issues: [genderIssue], on: try day(27), calendar: calendar)
        relinted.record(text: "Un une fromage.", issues: [genderIssue], on: try day(27), calendar: calendar)
        XCTAssertEqual(relinted.cleanFraction(lastSevenDaysFrom: try day(27), calendar: calendar), 0.0)
        relinted.record(text: "Un une fromage.", issues: [], on: try day(27), calendar: calendar)
        XCTAssertEqual(relinted.cleanFraction(lastSevenDaysFrom: try day(27), calendar: calendar), 1.0)
    }

    // Relinting the same text never counts the same mistake twice.
    func testRelintDoesNotDoubleCount() throws {
        var stats = LearnerStats()
        for _ in 0..<3 {
            stats.record(text: "Un une fromage.", issues: [genderIssue], on: try day(27), calendar: calendar)
        }
        XCTAssertEqual(stats.issueCounts[IssueKind.gender.rawValue], 1)
        // Being flagged isn't enough to make a tricky word; only a fix is.
        XCTAssertEqual(stats.trickyWords, [])
    }

    // A sentence the caret is inside isn't logged, so going back to finish a word counts only the finished version.
    func testSentenceBeingEditedIsSkipped() throws {
        let issue = Issue(kind: .spelling, severity: .error, offset: 21, length: 3, original: "dem", replacement: "demi", reason: "", hint: "", source: "")
        let text = "Parlez vous français à dem?"
        var stats = LearnerStats()
        stats.record(text: text, issues: [issue], on: try day(27), calendar: calendar, editingAt: 24)
        XCTAssertEqual(stats.sentencesChecked, 0)
        XCTAssertEqual(stats.issueCounts, [:])

        // With the caret after the question mark, the sentence is finished and counts.
        stats.record(text: "Parlez vous français à demain?", issues: [], on: try day(27), calendar: calendar, editingAt: 30)
        XCTAssertEqual(stats.sentencesChecked, 1)
    }

    // A corrected word becomes a tricky word, and the most corrected words come first.
    func testTrickyWords() {
        var stats = LearnerStats()
        stats.recordFix(byLearner: true, issue: genderIssue)
        XCTAssertEqual(stats.trickyWords, ["fromage"])

        let spellingIssue = Issue(
            kind: .spelling, severity: .error, offset: 4, length: 7,
            original: "gentile", replacement: "gentille", reason: "", hint: "", source: ""
        )
        stats.recordFix(byLearner: false, issue: genderIssue)
        stats.recordFix(byLearner: true, issue: spellingIssue)
        XCTAssertEqual(stats.trickyWords, ["fromage", "gentille"])
        XCTAssertEqual(stats.errorsFixed, 3)
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

    // Older files still load, but their flag-based word counts are left behind.
    func testOlderNounMistakesAreLeftBehind() throws {
        let json = #"{"days":{},"issueCounts":{"gender":2},"nounMistakes":{"demi":1},"errorsFixed":3,"countedIssues":[]}"#
        let stats = try JSONDecoder().decode(LearnerStats.self, from: Data(json.utf8))
        XCTAssertEqual(stats.trickyWords, [])
        XCTAssertEqual(stats.errorsFixed, 3)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(stats), as: UTF8.self).contains("nounMistakes"))
    }

    // A fix lands in the corrections list with the sentence as it read before the fix.
    func testFixIsLoggedWithItsSentence() throws {
        var stats = LearnerStats()
        let text = "Il pleut. Un une fromage. Bonsoir"
        let issue = Issue(kind: .gender, severity: .error, offset: 13, length: 11, original: "une fromage", replacement: "un fromage", reason: "", hint: "", source: "")
        stats.recordFix(byLearner: true, issue: issue, in: text, on: try day(27))
        let correction = try XCTUnwrap(stats.corrections.first)
        XCTAssertEqual(correction.original, "une fromage")
        XCTAssertEqual(correction.corrected, "un fromage")
        XCTAssertEqual(correction.sentence, "Un une fromage.")
        XCTAssertEqual(correction.kind, IssueKind.gender.rawValue)
        XCTAssertTrue(correction.byLearner)
    }

    // The corrections list keeps only the newest `correctionLimit` fixes.
    func testCorrectionsAreCapped() throws {
        var stats = LearnerStats()
        for _ in 0..<(LearnerStats.correctionLimit + 5) {
            stats.recordFix(byLearner: false, issue: genderIssue, in: "Un une fromage.")
        }
        XCTAssertEqual(stats.corrections.count, LearnerStats.correctionLimit)
        XCTAssertEqual(stats.errorsFixed, LearnerStats.correctionLimit + 5)
    }

    // Stats saved before the corrections list existed still load, with an empty list.
    func testDecodesStatsWithoutCorrections() throws {
        let json = #"{"days":{},"issueCounts":{},"correctedWords":{},"errorsFixed":1,"fixedByLearner":1,"countedIssues":[]}"#
        let stats = try JSONDecoder().decode(LearnerStats.self, from: Data(json.utf8))
        XCTAssertEqual(stats.corrections, [])
    }

    // Reset starts the stats over, as on first launch.
    @MainActor
    func testResetClearsEverything() throws {
        let store = StatsStore(fileURL: nil)
        store.record(text: "Un une fromage.", issues: [genderIssue])
        store.recordFix(byLearner: true, issue: genderIssue, in: "Un une fromage.")
        XCTAssertNotEqual(store.stats, LearnerStats())
        store.reset()
        XCTAssertEqual(store.stats, LearnerStats())
    }
}
