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

/// Checks Explain against the 61 sentences in `ExplainCases.json`, each picked because
/// it's easy to explain wrongly.
///
/// Every sentence is correct French, so the checker must leave Explain unlocked and
/// should say nothing at all. Those checks always run.
///
/// The model part and the system spellchecker check run only in the
/// quiver-demo-coquilleEvaluationTests test plan, which sets `COQUILLE_EXPLAIN_EVAL=1`,
/// since the model takes minutes and needs Apple Intelligence. The plan's other
/// variables choose what to run:
///
/// - `COQUILLE_EXPLAIN_MODE`: `smoke` is the first sentence of each category once,
///   `coverage` is every sentence once, and `release` is every sentence three times.
/// - `COQUILLE_EXPLAIN_CASES` (such as `E01,E43`) and `COQUILLE_EXPLAIN_CATEGORY` (such as
///   `tense`) run only those sentences instead, as many times as the mode says.
///
/// Each run is scored with the keyword hints in `ExplainKeywords.json`. A line goes to the
/// console before and after every request, and each sentence's results are written to a
/// checkpoint file in the app's sandbox as soon as it finishes, so a stopped run keeps what
/// it had. At the end, `ExplainReport` is attached as one HTML page, which
/// `Tools/explain-eval.sh` exports and opens in the browser. A request
/// that gets no answer, or none within `requestLimit`, fails the test, and so does a run of
/// the plan on a device without Apple Intelligence; keyword findings only point at runs to
/// read by hand.
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

    /// How much of the key the model evaluation covers.
    private enum Mode: String {
        case smoke, coverage, release

        /// How many times each sentence is explained; only a release run repeats, to
        /// show how much the model's answers vary.
        var runs: Int { self == .release ? 3 : 1 }
    }

    /// What the evaluation plan asked for, read from its environment variables.
    private struct Settings {
        let mode: Mode
        let caseIDs: Set<String>
        let categories: Set<String>

        /// The settings, or `nil` outside the evaluation plan.
        static func current() throws -> Settings? {
            let environment = ProcessInfo.processInfo.environment
            guard environment["COQUILLE_EXPLAIN_EVAL"] == "1" else { return nil }
            let name = environment["COQUILLE_EXPLAIN_MODE"] ?? Mode.release.rawValue
            let mode = try XCTUnwrap(Mode(rawValue: name.lowercased()), "COQUILLE_EXPLAIN_MODE must be smoke, coverage or release, not \(name)")
            return Settings(mode: mode, caseIDs: list(environment["COQUILLE_EXPLAIN_CASES"]), categories: list(environment["COQUILLE_EXPLAIN_CATEGORY"]))
        }

        /// A comma-separated variable as a set, empty when it isn't set.
        private static func list(_ value: String?) -> Set<String> {
            Set((value ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        }

        /// The cases to explain: the chosen ids and categories, or else the mode's share.
        func selection(of cases: [EvaluationCase]) -> [EvaluationCase] {
            if !caseIDs.isEmpty || !categories.isEmpty {
                return cases.filter { caseIDs.contains($0.id) || categories.contains($0.category) }
            }
            guard mode == .smoke else { return cases }
            var seen = Set<String>()
            return cases.filter { seen.insert($0.category).inserted }
        }

        /// "release, every sentence" or "smoke, E01, E43", for the report and the console.
        var summary: String {
            let chosen = (caseIDs.sorted() + categories.sorted()).joined(separator: ", ")
            return chosen.isEmpty ? mode.rawValue : "\(mode.rawValue), \(chosen)"
        }
    }

    /// Words that suggest the model called correct French wrong, a release blocker.
    private static let correctionWords = ["incorrect", "mistake", "typo", "should be", "is wrong", "error", "misspell", "misspelling"]

    /// How long one request may take before the evaluation gives up on it. Answers usually
    /// take one to three seconds.
    private static let requestLimit = Duration.seconds(60)

    /// What came of one request: the model's outcome, or nothing within `requestLimit`.
    private enum Answer {
        case outcome(PassageExplainer.Outcome)
        case timedOut
    }

    /// Whichever of the request and the time limit finishes first has answered.
    @MainActor
    private final class Race {
        var isOver = false
        var timer: Task<Void, Never>?
    }

    /// Explains `french`, but stops waiting after `requestLimit`.
    ///
    /// The time limit cancels the request, but it doesn't wait for the request to stop:
    /// if the model ignores the cancellation, it may keep working in the background
    /// while the evaluation moves on.
    private static func explain(_ french: String) async -> Answer {
        await withCheckedContinuation { continuation in
            let race = Race()
            let request = Task { @MainActor in
                let outcome = await PassageExplainer.explain(french)
                guard !race.isOver else { return }
                race.isOver = true
                race.timer?.cancel()
                continuation.resume(returning: Answer.outcome(outcome))
            }
            race.timer = Task { @MainActor in
                try? await Task.sleep(for: requestLimit)
                guard !race.isOver, !Task.isCancelled else { return }
                race.isOver = true
                request.cancel()
                continuation.resume(returning: Answer.timedOut)
            }
        }
    }

    /// Reports no misspellings, so only grammar decides whether Explain unlocks.
    private struct SilentSpellChecker: SpellChecker {
        func misspellings(in text: String) -> [Misspelling] { [] }
    }

    /// Loads a JSON file from the test bundle.
    private func resource<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let bundle = Bundle(for: ExplainEvaluationTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"), "\(name).json isn't in the test bundle")
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    /// Lists issues as "error on "le chèvre" → "la chèvre"".
    private static func describe(_ issues: [Issue]) -> String {
        issues.map { "\($0.severity.rawValue) on \"\($0.original)\" → \"\($0.replacement ?? "no fix")\"" }.joined(separator: "; ")
    }

    /// Writes one line to standard error, which isn't buffered, so the line shows in
    /// Xcode's console and in xcodebuild's output while the test is still running.
    private static func progress(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    /// A duration as minutes and seconds, such as 2:05.
    private static func clock(_ duration: Duration) -> String {
        let seconds = Int(duration.components.seconds)
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    /// A short duration in seconds, such as 2.8s.
    private static func seconds(_ duration: Duration) -> String {
        let parts = duration.components
        return String(format: "%.1fs", Double(parts.seconds) + Double(parts.attoseconds) / 1e18)
    }

    /// Adds `lines` to the end of the file at `url`.
    private static func append(_ lines: [String], to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
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

    /// What the keyword hints and correction words find in one explanation.
    private static func problems(in phrases: [PassageExplainer.Phrase], hints: Keywords) -> (problems: [String], isBlocker: Bool) {
        let text = phrases.map { "\($0.french) means \($0.meaning). \($0.note)" }.joined(separator: "\n")
        let meanings = phrases.map(\.meaning).joined(separator: " | ")
        var problems: [String] = []
        for group in hints.mention where !group.contains(where: { contains($0, in: text) }) {
            problems.append("missing one of: \(group.joined(separator: " / "))")
        }
        for word in hints.notInMeaning where contains(word, in: meanings) {
            problems.append("meaning says \"\(word)\"")
        }
        for phrase in hints.notAnywhere ?? [] where contains(phrase, in: text) {
            problems.append("says \"\(phrase)\"")
        }
        let corrections = correctionWords.filter { contains($0, in: text) }
        if !corrections.isEmpty {
            problems.append("BLOCKER? may call the French wrong: \(corrections.joined(separator: ", "))")
        }
        return (problems, !corrections.isEmpty)
    }

    // MARK: - Tests that always run

    // The key and the keyword hints agree, so a later failure is about the app.
    func testCasesAreWellFormed() throws {
        let set = try resource("ExplainCases", as: EvaluationSet.self)
        let keywords = try resource("ExplainKeywords", as: [String: Keywords].self)
        XCTAssertEqual(set.cases.count, set.count)
        XCTAssertEqual(Set(set.cases.map(\.id)).count, set.cases.count, "Case ids must be unique")
        let isBlank = { (text: String) in text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        for item in set.cases {
            XCTAssertFalse(isBlank(item.id), "A case has no id")
            XCTAssertFalse(isBlank(item.french), "\(item.id): no French")
            XCTAssertFalse(isBlank(item.category), "\(item.id): no category")
            XCTAssertFalse(item.mustMention.isEmpty, "\(item.id): needs something to mention")
            let hints = try XCTUnwrap(keywords[item.id], "\(item.id): no keyword hints")
            XCTAssertFalse(hints.mention.isEmpty, "\(item.id): needs mention keywords")
            // An empty group can never be satisfied, and an empty keyword matches nothing.
            XCTAssertFalse(hints.mention.contains(where: \.isEmpty), "\(item.id): an empty mention group")
            let words = hints.mention.flatMap { $0 } + hints.notInMeaning + (hints.notAnywhere ?? [])
            XCTAssertFalse(words.contains(where: isBlank), "\(item.id): an empty keyword")
        }
        XCTAssertEqual(Set(keywords.keys), Set(set.cases.map(\.id)), "Keyword hints for a case that isn't in the key")
    }

    // Every sentence is correct French, so no error may lock Explain, by the same rule the editor uses.
    func testEveryCaseUnlocksExplain() throws {
        let pack = try LanguagePack.french()
        let linter = Linter(spellChecker: SilentSpellChecker(), grammar: pack.grammar, lexicon: pack.lexicon, explanations: pack.explanations)
        for item in try resource("ExplainCases", as: EvaluationSet.self).cases {
            let issues = linter.lint(item.french).filter { $0.severity.blocksPlayback }
            XCTAssertTrue(issues.isEmpty, "\(item.id) \"\(item.french)\" would lock Explain: \(Self.describe(issues))")
        }
    }

    // Every sentence is correct French, so the checker shouldn't warn about it either.
    func testCheckerDoesNotWarnAboutCorrectFrench() throws {
        let pack = try LanguagePack.french()
        let linter = Linter(spellChecker: SilentSpellChecker(), grammar: pack.grammar, lexicon: pack.lexicon, explanations: pack.explanations)
        for item in try resource("ExplainCases", as: EvaluationSet.self).cases {
            let issues = linter.lint(item.french).filter { $0.severity == .warning }
            XCTAssertTrue(issues.isEmpty, "\(item.id) \"\(item.french)\" gets a warning on correct French: \(Self.describe(issues))")
        }
    }

    // MARK: - Evaluation plan only

    // Every sentence still unlocks Explain with the app's real spellchecker, which can
    // differ between Macs, so this runs only in the evaluation plan.
    func testEveryCaseUnlocksExplainWithSystemSpellChecker() throws {
        guard try Settings.current() != nil else {
            throw XCTSkip("Runs in the quiver-demo-coquilleEvaluationTests test plan.")
        }
        let pack = try LanguagePack.french()
        let spellChecker = SystemSpellChecker(language: pack.spellCheckerLanguage)
        // Without a working French dictionary, a clean result would prove nothing.
        try XCTSkipIf(spellChecker.misspellings(in: "Ahdourdui").isEmpty, "The system's French spellchecker isn't available")
        let linter = Linter(spellChecker: spellChecker, grammar: pack.grammar, lexicon: pack.lexicon, explanations: pack.explanations)
        for item in try resource("ExplainCases", as: EvaluationSet.self).cases {
            let issues = linter.lint(item.french).filter { $0.severity.blocksPlayback }
            XCTAssertTrue(issues.isEmpty, "\(item.id) \"\(item.french)\" would lock Explain with the system spellchecker: \(Self.describe(issues))")
        }
    }

    // Explains the chosen sentences and writes a scored report for review by hand.
    func testExplanationsAgainstTheKey() async throws {
        guard let settings = try Settings.current() else {
            throw XCTSkip("Runs in the quiver-demo-coquilleEvaluationTests test plan.")
        }
        // The evaluation plan asked for the model on purpose, so a missing model fails
        // rather than skips: a skipped evaluation could pass for a clean one.
        guard PassageExplainer.isAvailable else {
            XCTFail("Not evaluated: Explain needs Apple Intelligence with French on this device.")
            return
        }
        let set = try resource("ExplainCases", as: EvaluationSet.self)
        let keywords = try resource("ExplainKeywords", as: [String: Keywords].self)
        let unknown = settings.caseIDs.subtracting(set.cases.map(\.id)).union(settings.categories.subtracting(set.cases.map(\.category)))
        XCTAssertTrue(unknown.isEmpty, "Not in ExplainCases.json: \(unknown.sorted().joined(separator: ", "))")
        let cases = settings.selection(of: set.cases)
        guard !cases.isEmpty else {
            XCTFail("The settings (\(settings.summary)) select no sentences.")
            return
        }
        let runs = settings.mode.runs
        let totalRequests = cases.count * runs
        let width = String(totalRequests).count

        // The checkpoint file lives in the app's sandbox, the only place the test runner can write.
        let folder = URL.cachesDirectory.appending(path: "ExplainEvaluation", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let checkpoint = folder.appending(path: "ExplainEvaluation-\(settings.mode.rawValue)-\(Int(Date().timeIntervalSince1970)).md")
        let title = ["# Explain evaluation", "", "\(settings.summary): \(cases.count) sentences × \(runs) runs. Keyword scores point at runs to read; they aren't the verdict.", ""]
        try Data((title.joined(separator: "\n") + "\n").utf8).write(to: checkpoint)

        var records: [ExplainReport.Run] = []
        var flaggedRuns = 0
        var unanswered: [String] = []
        var request = 0
        let timer = ContinuousClock()
        let start = timer.now
        Self.progress("Explain evaluation (\(settings.summary)): \(cases.count) sentences × \(runs) runs = \(totalRequests) requests")
        Self.progress("Checkpoint file: \(checkpoint.path(percentEncoded: false))")

        for item in cases {
            let hints = try XCTUnwrap(keywords[item.id])
            var section = ["## \(item.id) · \(item.category)", "", "*\(item.french)*  ", "Reference: \(item.referenceEnglish)  ", "Must mention: \(item.mustMention.joined(separator: "; "))  ", "Must not say: \(item.mustNotSay.joined(separator: "; "))", ""]

            for run in 1...runs {
                request += 1
                let label = "[\(String(format: "%0\(width)d", request))/\(totalRequests)] \(item.id) run \(run)/\(runs)"
                Self.progress("\(label) started")
                let requestStart = timer.now
                let answer = await Self.explain(item.french)
                let took = requestStart.duration(to: timer.now)

                let verdict: String
                var status = ExplainReport.Status.passed
                var phrases: [PassageExplainer.Phrase] = []
                var reasons: [String] = []
                switch answer {
                case .timedOut:
                    let limit = Self.seconds(Self.requestLimit)
                    section += ["**Run \(run): timed out** after \(limit); the model may have kept working in the background"]
                    unanswered.append("\(item.id) run \(run): timed out after \(limit)")
                    verdict = "TIMED OUT after \(limit)"
                    status = .noAnswer
                    reasons = ["Timed out after \(limit). The model may have kept working in the background."]
                case .outcome(.explained(let explained)):
                    phrases = explained
                    let (problems, isBlocker) = Self.problems(in: explained, hints: hints)
                    section += ["**Run \(run): \(problems.isEmpty ? "keywords pass" : "check")**", ""]
                    section += explained.map { "- **\($0.french)** means **\($0.meaning)**. \($0.note)" }
                    if !problems.isEmpty {
                        section += [""] + problems.map { "  - ⚠︎ \($0)" }
                        flaggedRuns += 1
                    }
                    verdict = isBlocker ? "BLOCKER?" : problems.isEmpty ? "pass" : "check"
                    status = isBlocker ? .blocker : problems.isEmpty ? .passed : .review
                    reasons = problems
                case .outcome(let outcome):
                    section += ["**Run \(run): no answer** (\(outcome))"]
                    unanswered.append("\(item.id) run \(run): \(outcome)")
                    verdict = "NO ANSWER (\(outcome))"
                    status = .noAnswer
                    reasons = ["No answer: \(outcome)"]
                }
                section.append("")
                records.append(ExplainReport.Run(
                    id: item.id, category: item.category, french: item.french,
                    referenceEnglish: item.referenceEnglish, mustMention: item.mustMention, mustNotSay: item.mustNotSay,
                    run: run, runs: runs, status: status,
                    phrases: phrases.map { ExplainReport.Phrase(french: $0.french, meaning: $0.meaning, note: $0.note) },
                    reasons: reasons, seconds: Self.seconds(took)
                ))

                // "[034/180] E12 run 1/3 pass · 2.8s · 1 flagged so far · about 6:42 left"
                let left = start.duration(to: timer.now) / request * (totalRequests - request)
                Self.progress("\(label) \(verdict) · \(Self.seconds(took)) · \(flaggedRuns) flagged so far · about \(Self.clock(left)) left")
            }

            // Saved straight away, so stopping the test keeps every finished sentence.
            try Self.append(section, to: checkpoint)
        }

        let answered = totalRequests - unanswered.count
        let elapsed = Self.clock(start.duration(to: timer.now))
        let report = ExplainReport(settings: settings.summary, duration: elapsed, finished: Date(), runs: records)
        let attachment = XCTAttachment(data: Data(report.html().utf8), uniformTypeIdentifier: "public.html")
        attachment.name = "ExplainEvaluation.html"
        attachment.lifetime = .keepAlways
        add(attachment)
        Self.progress("Evaluation finished in \(elapsed): \(answered) answered, \(report.needsReview) need review, \(unanswered.count) no answer.")

        // A request that gets no answer is a problem with the model or the device, not a
        // finding about the French, and it means the report is missing that run.
        XCTAssertTrue(unanswered.isEmpty, "\(unanswered.count) of \(totalRequests) requests got no answer: \(unanswered.joined(separator: "; "))")
    }
}
