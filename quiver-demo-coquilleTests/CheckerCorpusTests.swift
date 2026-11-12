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

/// Runs the two-sentence cases in `CheckerCorpus.json` through the whole checker.
///
/// A case either must pass with no errors or warnings, or must flag one specific
/// mistake. A failing pass case is a false alarm and blocks a release; a failing flag
/// case is a missed mistake and a to-do. Adding a case means adding a JSON object.
///
/// Most tests leave spelling out: the fake spellchecker reports nothing, so results don't
/// depend on which system dictionaries the machine has installed. One test uses the real
/// spellchecker, to catch correct French that the system doesn't recognize.
@MainActor
final class CheckerCorpusTests: XCTestCase {

    /// One case from the corpus.
    private struct CorpusCase: Decodable {
        let id: String
        let level: String
        /// The grammar point in plain words, such as "place-city".
        let topic: String
        /// The rule that must catch a flag case; absent for pass cases and known gaps.
        let rule: String?
        let text: String
        let expect: String
        let flags: [ExpectedFlag]
        let note: String?
        /// Whether this flag case is a mistake no rule catches yet.
        let knownGap: Bool?
    }

    /// One mistake a flag case must report.
    private struct ExpectedFlag: Decodable {
        let find: String
        let fix: String
        let severity: String
    }

    /// Reports no misspellings, so the cases test grammar alone.
    private struct SilentSpellChecker: SpellChecker {
        func misspellings(in text: String) -> [Misspelling] { [] }
    }

    /// Loads the corpus from the test bundle.
    private func corpus() throws -> [CorpusCase] {
        let bundle = Bundle(for: CheckerCorpusTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "CheckerCorpus", withExtension: "json"))
        return try JSONDecoder().decode([CorpusCase].self, from: Data(contentsOf: url))
    }

    /// Builds the full checker over the bundled French pack.
    private func checker(for pack: LanguagePack, spellChecker: any SpellChecker = SilentSpellChecker()) -> Linter {
        Linter(
            spellChecker: spellChecker,
            grammar: pack.grammar,
            lexicon: pack.lexicon,
            explanations: pack.explanations
        )
    }

    /// Returns the errors and warnings in `text`; suggestions are style hints and aren't tested.
    private func blockingIssues(in text: String, using linter: Linter) -> [Issue] {
        linter.lint(text).filter { $0.severity != .suggestion }
    }

    /// Describes issues for a failure message.
    private func describe(_ issues: [Issue]) -> String {
        issues.isEmpty
            ? "nothing"
            : issues.map { "\($0.severity.rawValue) on \"\($0.original)\" → \"\($0.replacement ?? "no fix")\"" }.joined(separator: "; ")
    }

    /// Returns the character offsets of the first occurrence of `find` in `text`, or `nil`.
    private func characterRange(of find: String, in text: String) -> Range<Int>? {
        guard let range = text.range(of: find) else { return nil }
        let lower = text.distance(from: text.startIndex, to: range.lowerBound)
        return lower..<(lower + find.count)
    }

    /// Returns a case's text with every expected fix made.
    private func correctedText(of item: CorpusCase) -> String {
        item.flags.reduce(item.text) { text, flag in
            guard let range = text.range(of: flag.find) else { return text }
            return text.replacingCharacters(in: range, with: flag.fix)
        }
    }

    /// Returns `text` with each issue's replacement applied, or `nil` if an issue has no fix.
    private func applying(_ issues: [Issue], to text: String) -> String? {
        var characters = Array(text)
        // Last issue first, so the earlier offsets stay valid.
        for issue in issues.sorted(by: { $0.offset > $1.offset }) {
            guard let replacement = issue.replacement else { return nil }
            characters.replaceSubrange(issue.range, with: Array(replacement))
        }
        return String(characters)
    }

    /// Asserts a flag case reports exactly its expected mistakes, from its named rule.
    private func assertCaught(_ item: CorpusCase, using linter: Linter, pack: LanguagePack) {
        let issues = blockingIssues(in: item.text, using: linter)
        XCTAssertEqual(issues.count, item.flags.count, "\(item.id): expected \(item.flags.count) flag, got \(describe(issues))")

        for flag in item.flags {
            guard let expected = characterRange(of: flag.find, in: item.text),
                  let issue = issues.first(where: { $0.range.overlaps(expected) }) else {
                XCTFail("\(item.id): expected \"\(flag.fix)\", got \(describe(issues))")
                continue
            }
            XCTAssertEqual(issue.severity.rawValue, flag.severity, "\(item.id): wrong severity on \"\(issue.original)\"")
        }

        XCTAssertEqual(applying(issues, to: item.text), correctedText(of: item), "\(item.id): the fix doesn't give the expected French")

        guard let identifier = item.rule else { return }
        let fired = pack.grammar.rules.filter { rule in
            !Linter(filters: [GrammarRuleFilter(rule: rule)], tag: { pack.grammar.tag($0) }).lint(item.text).isEmpty
        }.map(\.identifier)
        XCTAssertTrue(fired.contains(identifier), "\(item.id): \(identifier) didn't fire; these did: \(fired)")
    }

    // MARK: - Tests

    // The corpus itself is consistent, so a failure below is about the checker.
    func testCorpusIsWellFormed() throws {
        let cases = try corpus()
        let pack = try LanguagePack.french()
        let identifiers = Set(pack.grammar.rules.map(\.identifier))

        XCTAssertFalse(cases.isEmpty)
        XCTAssertEqual(Set(cases.map(\.id)).count, cases.count, "Case ids must be unique")

        for item in cases {
            XCTAssertTrue(["A1", "A2", "B1"].contains(item.level), "\(item.id): unknown level \(item.level)")
            XCTAssertFalse(item.topic.isEmpty, "\(item.id): needs a topic")
            switch item.expect {
            case "pass":
                XCTAssertTrue(item.flags.isEmpty, "\(item.id): a pass case can't have flags")
                XCTAssertNil(item.rule, "\(item.id): a pass case names no rule")
                XCTAssertNil(item.knownGap, "\(item.id): a pass case can't be a known gap")
            case "flag":
                XCTAssertFalse(item.flags.isEmpty, "\(item.id): a flag case needs a flag")
                XCTAssertNotEqual(item.rule != nil, item.knownGap == true, "\(item.id): name a rule or mark a known gap, not both")
            default:
                XCTFail("\(item.id): unknown expectation \(item.expect)")
            }
            if let rule = item.rule {
                XCTAssertTrue(identifiers.contains(rule), "\(item.id): unknown rule \(rule)")
            }
            for flag in item.flags {
                XCTAssertTrue(item.text.contains(flag.find), "\(item.id): \"\(flag.find)\" isn't in the text")
                XCTAssertTrue(["error", "warning"].contains(flag.severity), "\(item.id): unknown severity \(flag.severity)")
            }
        }
    }

    // Correct French gets no errors or warnings. A failure here is a false alarm and blocks a release.
    func testPassCasesStaySilent() throws {
        let pack = try LanguagePack.french()
        let linter = checker(for: pack)
        for item in try corpus() where item.expect == "pass" {
            let issues = blockingIssues(in: item.text, using: linter)
            XCTAssertTrue(issues.isEmpty, "\(item.id) is a false alarm: \(describe(issues))")
        }
    }

    // Each mistake is flagged with the right severity and fix, and nothing else is flagged.
    func testFlagCasesAreCaught() throws {
        let pack = try LanguagePack.french()
        let linter = checker(for: pack)
        for item in try corpus() where item.expect == "flag" {
            if item.knownGap == true {
                // Fails the test once the case passes, as the reminder to name its rule.
                XCTExpectFailure("\(item.id): no rule catches this yet") {
                    assertCaught(item, using: linter, pack: pack)
                }
            } else {
                assertCaught(item, using: linter, pack: pack)
            }
        }
    }

    // Once a mistake is corrected, the checker has nothing left to say about the text.
    func testFixedTextIsClean() throws {
        let linter = checker(for: try LanguagePack.french())
        for item in try corpus() where item.expect == "flag" {
            let fixed = correctedText(of: item)
            let issues = blockingIssues(in: fixed, using: linter)
            XCTAssertTrue(issues.isEmpty, "\(item.id): the corrected text \"\(fixed)\" gets \(describe(issues))")
        }
    }

    // Every correct text stays clean through the app's real spellchecker, names included.
    func testCorrectTextStaysCleanWithSystemSpellChecker() throws {
        let pack = try LanguagePack.french()
        let spellChecker = SystemSpellChecker(language: pack.spellCheckerLanguage)
        // Without a working French dictionary, a clean result would prove nothing.
        try XCTSkipIf(spellChecker.misspellings(in: "Ahdourdui").isEmpty, "The system's French spellchecker isn't available")

        let linter = checker(for: pack, spellChecker: spellChecker)
        for item in try corpus() {
            let text = correctedText(of: item)
            let issues = blockingIssues(in: text, using: linter)
            XCTAssertTrue(issues.isEmpty, "\(item.id) is a false alarm in \"\(text)\": \(describe(issues))")
        }
    }
}
