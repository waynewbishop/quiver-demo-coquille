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

/// Checks Explain against the 60 sentences in `ExplainCases.json`, each picked because
/// it's easy to explain wrongly.
///
/// Every sentence is correct French, so the checker must stay silent on all of them, or
/// Explain stays locked. That part always runs.
///
/// The model part runs only when asked, since it takes minutes and needs Apple
/// Intelligence: set `COQUILLE_EXPLAIN_EVAL=1` (with xcodebuild,
/// `TEST_RUNNER_COQUILLE_EXPLAIN_EVAL=1`). It explains each sentence three times, scores
/// each run with the keyword hints in `ExplainKeywords.json`, and attaches a report to the
/// test result for review by hand. Keyword matching only points at the runs to read; it never fails the test.
@MainActor
final class ExplainEvaluationTests: XCTestCase {

    /// One case from the grading key.
    private struct EvaluationCase: Decodable {
        let id: String
        let category: String
        let french: String
        let referenceEnglish: String
        let mustMention: [String]
        let mustNotSay: [String]
        let note: String?

        private enum CodingKeys: String, CodingKey {
            case id, category, french, note
            case referenceEnglish = "reference_english"
            case mustMention = "must_mention"
            case mustNotSay = "must_not_say"
        }
    }

    /// The grading key's top level.
    private struct EvaluationSet: Decodable {
        let count: Int
        let cases: [EvaluationCase]
    }

    /// Keyword hints for one case: every group needs one hit somewhere in the explanation;
    /// `notInMeaning` words mustn't appear in a phrase's English meaning, where a false
    /// friend would show; `notAnywhere` phrases mustn't appear at all.
    private struct Keywords: Decodable {
        let mention: [[String]]
        let notInMeaning: [String]
        let notAnywhere: [String]?
    }

    /// Words that suggest the model called correct French wrong, a release blocker.
    private static let correctionWords = ["incorrect", "mistake", "typo", "should be", "is wrong", "error", "misspell", "misspelling"]

    /// How many times each sentence is explained, since the model's answers vary.
    private static let runs = 3

    /// Reports no misspellings, so only grammar decides whether Explain unlocks.
    private struct SilentSpellChecker: SpellChecker {
        func misspellings(in text: String) -> [Misspelling] { [] }
    }

    private func resource<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let bundle = Bundle(for: ExplainEvaluationTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"), "\(name).json isn't in the test bundle")
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    /// Lowercased, without accents or curly apostrophes, so keywords match loosely.
    private static func folded(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2019}", with: "'")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
    }

    /// Whether `phrase` appears in `text` as whole words.
    private static func contains(_ phrase: String, in text: String) -> Bool {
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: folded(phrase)) + "(?![\\p{L}\\p{N}])"
        return folded(text).range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Tests

    // The key and the keyword hints agree, so a later failure is about the app.
    func testCasesAreWellFormed() throws {
        let set = try resource("ExplainCases", as: EvaluationSet.self)
        let keywords = try resource("ExplainKeywords", as: [String: Keywords].self)
        XCTAssertEqual(set.cases.count, set.count)
        XCTAssertEqual(Set(set.cases.map(\.id)).count, set.cases.count, "Case ids must be unique")
        for item in set.cases {
            XCTAssertFalse(item.mustMention.isEmpty, "\(item.id): needs something to mention")
            let hints = try XCTUnwrap(keywords[item.id], "\(item.id): no keyword hints")
            XCTAssertFalse(hints.mention.isEmpty, "\(item.id): needs mention keywords")
        }
        XCTAssertEqual(Set(keywords.keys), Set(set.cases.map(\.id)), "Keyword hints for a case that isn't in the key")
    }

    // Every sentence is correct French, so none may lock Explain with an error or warning.
    func testEveryCaseUnlocksExplain() throws {
        let pack = try LanguagePack.french()
        let linter = Linter(spellChecker: SilentSpellChecker(), grammar: pack.grammar, lexicon: pack.lexicon, explanations: pack.explanations)
        for item in try resource("ExplainCases", as: EvaluationSet.self).cases {
            let issues = linter.lint(item.french).filter { $0.severity != .suggestion }
            let described = issues.map { "\($0.severity.rawValue) on \"\($0.original)\" → \"\($0.replacement ?? "no fix")\"" }.joined(separator: "; ")
            XCTAssertTrue(issues.isEmpty, "\(item.id) \"\(item.french)\" would lock Explain: \(described)")
        }
    }

    // Explains every sentence three times and writes a scored report for review by hand.
    func testExplanationsAgainstTheKey() async throws {
        guard ProcessInfo.processInfo.environment["COQUILLE_EXPLAIN_EVAL"] == "1" else {
            throw XCTSkip("Set COQUILLE_EXPLAIN_EVAL=1 to run the Explain evaluation.")
        }
        guard PassageExplainer.isAvailable else {
            throw XCTSkip("Explain needs Apple Intelligence with French.")
        }
        let set = try resource("ExplainCases", as: EvaluationSet.self)
        let keywords = try resource("ExplainKeywords", as: [String: Keywords].self)

        var report = ["# Explain evaluation", "", "\(set.cases.count) sentences × \(Self.runs) runs. Keyword scores point at runs to read; they aren't the verdict.", ""]
        var summary: [String] = []
        var flaggedRuns = 0
        var blockerRuns = 0

        for item in set.cases {
            let hints = try XCTUnwrap(keywords[item.id])
            report += ["## \(item.id) · \(item.category)", "", "*\(item.french)*  ", "Reference: \(item.referenceEnglish)  ", "Must mention: \(item.mustMention.joined(separator: "; "))  ", "Must not say: \(item.mustNotSay.joined(separator: "; "))", ""]
            var caseFlags: [String] = []

            for run in 1...Self.runs {
                let outcome = await PassageExplainer.explain(item.french)
                guard case .explained(let phrases) = outcome else {
                    report += ["**Run \(run): no explanation** (\(outcome))", ""]
                    caseFlags.append("run \(run) no answer")
                    flaggedRuns += 1
                    continue
                }
                let text = phrases.map { "\($0.french) means \($0.meaning). \($0.note)" }.joined(separator: "\n")
                let meanings = phrases.map(\.meaning).joined(separator: " | ")

                var problems: [String] = []
                for group in hints.mention where !group.contains(where: { Self.contains($0, in: text) }) {
                    problems.append("missing one of: \(group.joined(separator: " / "))")
                }
                for word in hints.notInMeaning where Self.contains(word, in: meanings) {
                    problems.append("meaning says \"\(word)\"")
                }
                for phrase in hints.notAnywhere ?? [] where Self.contains(phrase, in: text) {
                    problems.append("says \"\(phrase)\"")
                }
                let corrections = Self.correctionWords.filter { Self.contains($0, in: text) }
                if !corrections.isEmpty {
                    problems.append("BLOCKER? may call the French wrong: \(corrections.joined(separator: ", "))")
                    blockerRuns += 1
                }

                report += ["**Run \(run): \(problems.isEmpty ? "keywords pass" : "check")**", ""]
                report += phrases.map { "- **\($0.french)** means **\($0.meaning)**. \($0.note)" }
                if !problems.isEmpty {
                    report += [""] + problems.map { "  - ⚠︎ \($0)" }
                    caseFlags.append("run \(run): " + problems.joined(separator: "; "))
                    flaggedRuns += 1
                }
                report.append("")
            }
            if !caseFlags.isEmpty {
                summary.append("- **\(item.id)** \(item.french): " + caseFlags.joined(separator: " · "))
            }
        }

        let total = set.cases.count * Self.runs
        let header = ["## Summary", "", "\(total - flaggedRuns) of \(total) runs pass the keyword checks. \(blockerRuns) runs may call correct French wrong.", ""] + summary + [""]
        report.insert(contentsOf: header, at: 4)

        // Attached to the test result, since the sandboxed test runner can't write
        // outside its own container. Export it with `xcresulttool export attachments`.
        let attachment = XCTAttachment(string: report.joined(separator: "\n"))
        attachment.name = "ExplainEvaluation.md"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
