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

/// The learner's history: which sentences they checked, what the linter flagged,
/// and the nouns they keep getting wrong. Stored only on the device.
nonisolated struct LearnerStats: Codable, Equatable, Sendable {

    /// The sentences checked on one day.
    struct Day: Codable, Equatable, Sendable {
        var checked: Set<String> = []
        var clean: Set<String> = []
    }

    /// Day key ("2026-10-27") → that day's sentences.
    var days: [String: Day] = [:]
    /// Issue kind raw value → times flagged.
    var issueCounts: [String: Int] = [:]
    /// Noun → times its gender was wrong.
    var nounMistakes: [String: Int] = [:]
    var errorsFixed = 0
    /// Errors the learner fixed by typing, out of `errorsFixed`.
    var fixedByLearner = 0
    /// Sentence + issue pairs already counted, so relinting the same text never double-counts.
    var countedIssues: Set<String> = []

    // MARK: - Recording

    /// Logs every completed sentence in `text` and the issues inside it.
    ///
    /// A sentence counts once it ends in . ! or ?, so half-typed sentences are skipped.
    /// Suggestions never make a sentence unclean.
    mutating func record(text: String, issues: [Issue], on date: Date, calendar: Calendar = .current) {
        let key = Self.dayKey(for: date, calendar: calendar)
        var day = days[key] ?? Day()

        for sentence in Self.completedSentences(in: text) {
            let flagged = issues.filter { $0.severity != .suggestion && sentence.range.overlaps($0.range) }
            day.checked.insert(sentence.text)
            if flagged.isEmpty {
                day.clean.insert(sentence.text)
            }
            for issue in flagged where !countedIssues.contains(sentence.text + "|" + issue.ignoreKey) {
                countedIssues.insert(sentence.text + "|" + issue.ignoreKey)
                issueCounts[issue.kind.rawValue, default: 0] += 1
                if issue.kind == .gender, let noun = issue.original.split(separator: " ").last {
                    nounMistakes[noun.lowercased(), default: 0] += 1
                }
            }
        }
        days[key] = day
    }

    /// Counts one fixed error, and whether the learner typed the fix rather than applying it.
    mutating func recordFix(byLearner: Bool) {
        errorsFixed += 1
        if byLearner {
            fixedByLearner += 1
        }
    }

    // MARK: - Summaries

    /// Consecutive days with at least one checked sentence, ending today (or yesterday,
    /// so a streak isn't lost before the learner has written anything today).
    func streak(asOf date: Date, calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: date)
        if days[Self.dayKey(for: day, calendar: calendar)]?.checked.isEmpty ?? true {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while !(days[Self.dayKey(for: day, calendar: calendar)]?.checked.isEmpty ?? true) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// Every distinct sentence checked, across all days.
    var sentencesChecked: Int {
        days.values.reduce(0) { $0 + $1.checked.count }
    }

    /// The share of sentences checked in the last seven days that had no errors or warnings,
    /// or `nil` when none were checked.
    func cleanFraction(lastSevenDaysFrom date: Date, calendar: Calendar = .current) -> Double? {
        var checked = 0
        var clean = 0
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date),
                  let record = days[Self.dayKey(for: day, calendar: calendar)] else { continue }
            checked += record.checked.count
            clean += record.clean.count
        }
        return checked > 0 ? Double(clean) / Double(checked) : nil
    }

    /// Issue kinds ranked by how often they were flagged, most frequent first.
    var weakSpots: [(kind: IssueKind, count: Int)] {
        issueCounts.compactMap { raw, count in IssueKind(rawValue: raw).map { ($0, count) } }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.kind.rawValue < $1.kind.rawValue }
    }

    /// Nouns missed more than once, most missed first.
    var trickyWords: [String] {
        nounMistakes.filter { $0.value > 1 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map(\.key)
    }

    // MARK: - Helpers

    /// Returns the calendar day of `date` as "yyyy-MM-dd".
    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Returns each sentence ending in . ! or ?, trimmed, with its character range.
    static func completedSentences(in text: String) -> [(text: String, range: Range<Int>)] {
        var sentences: [(text: String, range: Range<Int>)] = []
        var start = 0
        for (offset, character) in text.enumerated() where ".!?".contains(character) {
            let range = start..<(offset + 1)
            let slice = text.dropFirst(range.lowerBound).prefix(range.count)
            let trimmed = slice.trimmingCharacters(in: .whitespacesAndNewlines)
            // A lone punctuation mark, as in "…?!", isn't a sentence.
            if trimmed.contains(where: \.isLetter) {
                sentences.append((trimmed, range))
            }
            start = offset + 1
        }
        return sentences
    }
}

nonisolated extension LearnerStats {

    /// Decodes saved stats, including files written before `fixedByLearner` existed.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        days = try container.decode([String: Day].self, forKey: .days)
        issueCounts = try container.decode([String: Int].self, forKey: .issueCounts)
        nounMistakes = try container.decode([String: Int].self, forKey: .nounMistakes)
        errorsFixed = try container.decode(Int.self, forKey: .errorsFixed)
        fixedByLearner = try container.decodeIfPresent(Int.self, forKey: .fixedByLearner) ?? 0
        countedIssues = try container.decode(Set<String>.self, forKey: .countedIssues)
    }
}
