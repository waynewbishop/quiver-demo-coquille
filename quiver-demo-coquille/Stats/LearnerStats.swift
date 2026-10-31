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
/// and the words they keep getting wrong. Stored only on the device.
nonisolated struct LearnerStats: Codable, Equatable, Sendable {

    /// The sentences checked on one day.
    struct Day: Codable, Equatable, Sendable {
        var checked: Set<String> = []
        var clean: Set<String> = []
    }

    /// One fixed error for the corrections list: what was written, what it became, and where.
    struct Correction: Codable, Equatable, Sendable, Identifiable {
        var id = UUID()
        let date: Date
        /// The issue kind's raw value, kept as text so a renamed kind never breaks old files.
        let kind: String
        /// The flagged text as the learner wrote it.
        let original: String
        /// The fix, or `nil` when the learner retyped a word the linter had no fix for.
        let corrected: String?
        /// The sentence the mistake sat in, as it read before the fix.
        let sentence: String?
        /// Whether the learner typed the fix rather than applying it.
        let byLearner: Bool
    }

    /// Day key ("2026-10-27") → that day's sentences.
    var days: [String: Day] = [:]
    /// Issue kind raw value → times flagged.
    var issueCounts: [String: Int] = [:]
    /// Word → times the learner corrected an error to it, by typing the fix or applying it.
    var correctedWords: [String: Int] = [:]
    var errorsFixed = 0
    /// Errors the learner fixed by typing, out of `errorsFixed`.
    var fixedByLearner = 0
    /// Sentence + issue pairs already counted, so relinting the same text never double-counts.
    var countedIssues: Set<String> = []
    /// Fixed errors, oldest first, up to `correctionLimit`.
    var corrections: [Correction] = []

    /// The most corrections kept; older ones drop off the front.
    static let correctionLimit = 500

    // MARK: - Recording

    /// Logs every completed sentence in `text` and the issues inside it.
    ///
    /// A sentence counts once it ends in . ! or ?, so half-typed sentences are skipped.
    /// Suggestions never make a sentence unclean.
    ///
    /// A sentence the caret is inside (`editingAt`) is skipped until the learner leaves it,
    /// so going back to finish a word ("à dem?") never logs the half-typed version.
    mutating func record(text: String, issues: [Issue], on date: Date, calendar: Calendar = .current, editingAt caret: Int? = nil) {
        let key = Self.dayKey(for: date, calendar: calendar)
        var day = days[key] ?? Day()

        for sentence in Self.completedSentences(in: text) {
            // A caret right after the closing punctuation means the sentence is finished.
            if let caret, sentence.range.lowerBound < caret, caret < sentence.range.upperBound { continue }
            let flagged = issues.filter { $0.severity != .suggestion && sentence.range.overlaps($0.range) }
            day.checked.insert(sentence.text)
            if flagged.isEmpty {
                day.clean.insert(sentence.text)
            }
            for issue in flagged where !countedIssues.contains(sentence.text + "|" + issue.ignoreKey) {
                countedIssues.insert(sentence.text + "|" + issue.ignoreKey)
                issueCounts[issue.kind.rawValue, default: 0] += 1
            }
        }
        days[key] = day
    }

    /// Counts one fixed error, whether the learner typed the fix rather than applying it,
    /// and the corrected word behind it for the tricky words.
    ///
    /// Words are counted here rather than when an issue is flagged: a flag can come from a
    /// half-typed word, and its suggested fix is only a guess, but a fix that now stands
    /// in the text is a word the learner really meant.
    ///
    /// With an issue, the fix is also added to the corrections list, along with its
    /// sentence from `text`, the French as it read before the fix.
    mutating func recordFix(byLearner: Bool, issue: Issue? = nil, in text: String? = nil, on date: Date = .now) {
        errorsFixed += 1
        if byLearner {
            fixedByLearner += 1
        }
        guard let issue else { return }
        if let word = Self.missedWord(in: issue) {
            correctedWords[word, default: 0] += 1
        }
        corrections.append(Correction(
            date: date,
            kind: issue.kind.rawValue,
            original: issue.original,
            corrected: issue.replacement,
            sentence: text.flatMap { Self.sentence(around: issue.range, in: $0) },
            byLearner: byLearner
        ))
        if corrections.count > Self.correctionLimit {
            corrections.removeFirst(corrections.count - Self.correctionLimit)
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

    /// The most tricky words shown at once.
    static let trickyWordLimit = 12

    /// Words the learner has corrected at least once, most often first, up to `trickyWordLimit`.
    var trickyWords: [String] {
        correctedWords.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(Self.trickyWordLimit)
            .map(\.key)
    }

    // MARK: - Helpers

    /// Returns the correct word behind a word-level mistake, such as "fromage" for
    /// "une fromage", "gentille" for "gentile", or "à" for "a", or `nil` for other kinds.
    ///
    /// A spelling fix that only adds an accent, such as "tete" to "tête", counts here too.
    ///
    /// The correct spelling is kept rather than the typo, so "gentile" and "gentil"
    /// both count toward "gentille".
    static func missedWord(in issue: Issue) -> String? {
        guard let replacement = issue.replacement else { return nil }
        switch issue.kind {
        case .gender:
            return replacement.split(separator: " ").last.map { $0.lowercased() }
        case .agreement, .spelling, .accent, .participle, .conjugation:
            return replacement.lowercased()
        default:
            return nil
        }
    }

    /// Returns the calendar day of `date` as "yyyy-MM-dd".
    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Returns the trimmed sentence holding `range`, from the previous . ! ? or line break
    /// to the next one, or `nil` when the range falls outside `text`.
    static func sentence(around range: Range<Int>, in text: String) -> String? {
        let characters = Array(text)
        guard range.lowerBound >= 0, range.upperBound <= characters.count else { return nil }
        let ends: Set<Character> = [".", "!", "?", "\n"]
        var start = range.lowerBound
        while start > 0, !ends.contains(characters[start - 1]) { start -= 1 }
        var end = range.upperBound
        while end < characters.count, !ends.contains(characters[end]) { end += 1 }
        if end < characters.count, characters[end] != "\n" { end += 1 }
        let sentence = String(characters[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return sentence.isEmpty ? nil : sentence
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

    /// Older files' "nounMistakes" counted every flagged word, half-typed ones and
    /// guesses included, so it is left behind rather than decoded.
    private enum CodingKeys: String, CodingKey {
        case days, issueCounts, correctedWords, errorsFixed, fixedByLearner, countedIssues, corrections
    }

    /// Decodes saved stats, including files written before `fixedByLearner`, `correctedWords`
    /// or `corrections` existed.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        days = try container.decode([String: Day].self, forKey: .days)
        issueCounts = try container.decode([String: Int].self, forKey: .issueCounts)
        correctedWords = try container.decodeIfPresent([String: Int].self, forKey: .correctedWords) ?? [:]
        errorsFixed = try container.decode(Int.self, forKey: .errorsFixed)
        fixedByLearner = try container.decodeIfPresent(Int.self, forKey: .fixedByLearner) ?? 0
        countedIssues = try container.decode(Set<String>.self, forKey: .countedIssues)
        corrections = try container.decodeIfPresent([Correction].self, forKey: .corrections) ?? []
    }
}
