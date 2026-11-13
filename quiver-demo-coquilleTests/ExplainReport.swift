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

/// The Explain evaluation's results as one HTML page, summary first, for reading in a browser.
///
/// `Tools/explain-eval.sh` exports it from the test result and opens it. Its wording stays
/// neutral: keyword matching only picks the runs a person should read, so a flagged run
/// "needs review" and is never called wrong.
struct ExplainReport {

    /// How one run came out, in the order the report lists them.
    enum Status: String, CaseIterable {
        /// The explanation may call correct French wrong, the most serious finding.
        case blocker
        /// A keyword hint missed, or a word that shouldn't be there appeared.
        case review
        /// The model gave no answer, or none in time.
        case noAnswer
        /// Every keyword check passed.
        case passed

        /// The label on the run's card and in the summary.
        var label: String {
            switch self {
            case .blocker: "May call correct French wrong"
            case .review: "Needs review"
            case .noAnswer: "No answer"
            case .passed: "Passed keyword checks"
            }
        }
    }

    /// One phrase from an explanation.
    struct Phrase {
        let french: String
        let meaning: String
        let note: String
    }

    /// One request: the sentence, what the model said, and why it was flagged.
    struct Run {
        let id: String
        let category: String
        let french: String
        let referenceEnglish: String
        let mustMention: [String]
        let mustNotSay: [String]
        let run: Int
        let runs: Int
        let status: Status
        let phrases: [Phrase]
        /// The keyword findings, or why there was no answer.
        let reasons: [String]
        let seconds: String
    }

    /// The mode and any chosen cases, such as "release" or "smoke, E43".
    let settings: String
    let duration: String
    let finished: Date
    let runs: [Run]

    /// The runs with a status.
    private func runs(_ status: Status) -> [Run] {
        runs.filter { $0.status == status }
    }

    /// How many runs a person should read: possible blockers and keyword findings.
    var needsReview: Int {
        runs(.blocker).count + runs(.review).count
    }

    /// The page, with its styles and filter script inline so it opens from a file.
    func html() -> String {
        let answered = runs.count - runs(.noAnswer).count
        let date = finished.formatted(date: .abbreviated, time: .shortened)
        let summary = """
            <dl class="summary">
              <div><dt>Mode</dt><dd>\(escape(settings))</dd></div>
              <div><dt>Finished</dt><dd>\(escape(date)) · \(escape(duration))</dd></div>
              <div><dt>Answered</dt><dd>\(answered) of \(runs.count)</dd></div>
              <div><dt>No answer</dt><dd>\(runs(.noAnswer).count)</dd></div>
              <div class="accent"><dt>Need review</dt><dd>\(needsReview)</dd></div>
            </dl>
            """
        let filters = [("all", "All"), ("needs-review", "Needs review"), ("noAnswer", "No answer"), ("passed", "Passed")]
            .map { "<button data-filter=\"\($0.0)\"\($0.0 == "all" ? " class=\"on\"" : "")>\($0.1)</button>" }
            .joined()
        let review = runs(.blocker) + runs(.review)
        let body = [
            section("Needs review", review, id: "needs-review", empty: "Every answered run passed the keyword checks."),
            section("No answer", runs(.noAnswer), id: "noAnswer", empty: "Every request got an answer."),
            passedSection()
        ].joined(separator: "\n")

        return """
            <!doctype html>
            <html lang="en">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Explain Evaluation</title>
            <style>\(Self.styles)</style>
            </head>
            <body data-filter="all">
            <main>
            <h1>Explain evaluation</h1>
            <p class="lede">Keyword checks pick the runs to read. They don't measure whether an explanation is right, so a run that needs review isn't necessarily wrong, and a run that passed isn't necessarily right.</p>
            \(summary)
            <nav class="filters">\(filters)</nav>
            \(body)
            </main>
            <script>\(Self.script)</script>
            </body>
            </html>
            """
    }

    /// A titled list of run cards, or a note when there are none.
    private func section(_ title: String, _ runs: [Run], id: String, empty: String) -> String {
        let cards = runs.isEmpty ? "<p class=\"empty\">\(escape(empty))</p>" : runs.map(card).joined(separator: "\n")
        return "<section id=\"\(id)\"><h2>\(escape(title)) <span class=\"count\">\(runs.count)</span></h2>\n\(cards)</section>"
    }

    /// The passed runs, folded away until opened or chosen with the Passed filter.
    private func passedSection() -> String {
        let passed = runs(.passed)
        let cards = passed.map(card).joined(separator: "\n")
        return "<section id=\"passed\"><details><summary><h2>Passed keyword checks <span class=\"count\">\(passed.count)</span></h2></summary>\n\(cards)</details></section>"
    }

    /// One run: the sentence, its reference, the model's phrases and the findings.
    private func card(_ run: Run) -> String {
        let phrases = run.phrases.isEmpty ? "" : "<ul class=\"phrases\">" + run.phrases.map {
            "<li><b class=\"fr\">\(escape($0.french))</b> means <b>\(escape($0.meaning))</b>. \(escape($0.note))</li>"
        }.joined() + "</ul>"
        let reasons = run.reasons.isEmpty ? "" : "<ul class=\"reasons\">" + run.reasons.map { "<li>\(escape($0))</li>" }.joined() + "</ul>"
        return """
            <article class="run \(run.status.rawValue)">
              <header><span class="tag">\(escape(run.status.label))</span><span class="meta">\(escape(run.id)) · \(escape(run.category)) · run \(run.run) of \(run.runs) · \(escape(run.seconds))</span></header>
              <p class="sentence">\(escape(run.french))</p>
              <p class="reference">Reference: \(escape(run.referenceEnglish))</p>
              \(reasons)
              \(phrases)
              <p class="key">Must mention: \(escape(run.mustMention.joined(separator: "; "))) · Must not say: \(escape(run.mustNotSay.joined(separator: "; ")))</p>
            </article>
            """
    }

    /// `text` with the characters HTML treats as markup replaced.
    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let styles = """
        :root { --bg: #fbfaf7; --card: #ffffff; --text: #1d1d1f; --muted: #6e6e73; --line: #e3e1db; --accent: #0a66c2; --blocker: #c4271b; --review: #a35d00; --none: #6e6e73; --pass: #2e7d32; }
        @media (prefers-color-scheme: dark) { :root { --bg: #1c1c1e; --card: #2c2c2e; --text: #f2f2f7; --muted: #a1a1a6; --line: #3a3a3c; --accent: #5aa9ff; --blocker: #ff6b5e; --review: #f0a73c; --none: #a1a1a6; --pass: #6ccf72; } }
        * { box-sizing: border-box; }
        body { margin: 0; background: var(--bg); color: var(--text); font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; }
        main { max-width: 860px; margin: 0 auto; padding: 32px 16px 64px; }
        h1 { font-size: 26px; margin: 0 0 6px; }
        h2 { font-size: 18px; margin: 32px 0 12px; display: inline-block; }
        .lede { color: var(--muted); margin: 0 0 20px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 10px; margin: 0 0 20px; }
        .summary div { background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 10px 14px; }
        .summary dt { color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .04em; }
        .summary dd { margin: 2px 0 0; font-size: 18px; font-weight: 600; }
        .summary .accent dd { color: var(--accent); }
        .filters { display: flex; flex-wrap: wrap; gap: 8px; }
        .filters button { font: inherit; padding: 6px 14px; border-radius: 999px; border: 1px solid var(--line); background: var(--card); color: var(--text); cursor: pointer; }
        .filters button.on { background: var(--accent); border-color: var(--accent); color: #fff; }
        .count { color: var(--muted); font-weight: 400; margin-left: 4px; }
        summary { cursor: pointer; }
        .run { background: var(--card); border: 1px solid var(--line); border-left: 4px solid var(--none); border-radius: 10px; padding: 14px 16px; margin: 0 0 12px; }
        .run.blocker { border-left-color: var(--blocker); }
        .run.review { border-left-color: var(--review); }
        .run.passed { border-left-color: var(--pass); }
        .run header { display: flex; flex-wrap: wrap; gap: 8px 12px; align-items: baseline; }
        .tag { font-size: 12px; font-weight: 600; text-transform: uppercase; letter-spacing: .04em; }
        .blocker .tag { color: var(--blocker); } .review .tag { color: var(--review); } .noAnswer .tag { color: var(--none); } .passed .tag { color: var(--pass); }
        .meta, .reference, .key { color: var(--muted); font-size: 13px; }
        .sentence { font-size: 17px; font-style: italic; margin: 8px 0 2px; }
        .reference { margin: 0 0 8px; }
        .reasons { margin: 8px 0; padding-left: 20px; color: var(--review); }
        .blocker .reasons { color: var(--blocker); }
        .phrases { margin: 8px 0; padding-left: 20px; }
        .phrases .fr { color: var(--accent); }
        .key { margin: 8px 0 0; }
        .empty { color: var(--muted); }
        body[data-filter="needs-review"] #noAnswer, body[data-filter="needs-review"] #passed,
        body[data-filter="noAnswer"] #needs-review, body[data-filter="noAnswer"] #passed,
        body[data-filter="passed"] #needs-review, body[data-filter="passed"] #noAnswer { display: none; }
        """

    private static let script = """
        document.querySelectorAll('.filters button').forEach(function (button) {
          button.addEventListener('click', function () {
            var filter = button.dataset.filter;
            document.body.dataset.filter = filter;
            document.querySelectorAll('.filters button').forEach(function (b) { b.classList.toggle('on', b === button); });
            var passed = document.querySelector('#passed details');
            if (passed) { passed.open = filter === 'passed'; }
          });
        });
        """
}
