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

import SwiftUI
import Observation

/// The editor's state: the learner's text, the issues found in it, and the gate
/// that keeps play and English locked until every error is fixed or ignored.
@Observable
final class EditorModel {

    /// What the English area shows.
    enum English: Equatable {
        case idle
        case translating
        case translated(String)
        case unavailable(String)
    }

    // MARK: - State

    /// The learner's text, carrying the underline styling for each issue.
    var text = AttributedString()
    var selection = AttributedTextSelection()
    var isEnglishOn = false {
        didSet { refreshEnglish() }
    }
    /// Whether suggestion-level issues are shown at all.
    var showsSuggestions = true {
        didSet { applyStyling() }
    }

    private(set) var issues: [Issue] = []
    private(set) var ignoredKeys: Set<String> = []
    private(set) var selectedIssueID: String?
    private(set) var english = English.idle
    private(set) var loadFailure: String?

    let narrator: SpeechNarrator
    let stats: StatsStore

    @ObservationIgnored private var linter: Linter?
    @ObservationIgnored private var translator: (any Translator)?
    /// The exact text the current `issues` describe.
    @ObservationIgnored private var lintedText = ""
    /// The text last seen by `textDidChange`, to tell typing from styling changes.
    @ObservationIgnored private var observedText = ""
    @ObservationIgnored private var lintTask: Task<Void, Never>?
    @ObservationIgnored private var translationTask: Task<Void, Never>?

    /// How long typing must pause before the text is linted.
    static let lintDelay = Duration.milliseconds(400)

    /// Creates a model; the language pack loads in `load()`.
    init(stats: StatsStore = StatsStore()) {
        self.stats = stats
        self.narrator = SpeechNarrator(language: "fr-FR")
    }

    // MARK: - Derived state

    /// The learner's text without styling.
    var plainText: String {
        String(text.characters)
    }

    /// Issues not ignored, and not suggestions when suggestions are hidden.
    var visibleIssues: [Issue] {
        issues.filter { !ignoredKeys.contains($0.ignoreKey) && (showsSuggestions || $0.severity != .suggestion) }
    }

    /// Unresolved issues that block play and English.
    var blockingIssues: [Issue] {
        visibleIssues.filter { $0.severity.blocksPlayback }
    }

    /// Unresolved warnings, which never block.
    var warnings: [Issue] {
        visibleIssues.filter { $0.severity == .warning }
    }

    /// Like a compiler, nothing runs until the French is correct.
    var isLocked: Bool {
        !blockingIssues.isEmpty
    }

    /// Whether there is any French to play or translate.
    var hasText: Bool {
        plainText.contains(where: \.isLetter)
    }

    /// The issue whose card is open.
    var selectedIssue: Issue? {
        visibleIssues.first { $0.id == selectedIssueID }
    }

    // MARK: - Loading

    /// Loads the French pack off the main actor, then wires up the linter and translator.
    func load() async {
        guard linter == nil else { return }
        do {
            let pack = try await Task.detached { try LanguagePack.french() }.value
            linter = Linter(
                spellChecker: SystemSpellChecker(language: pack.spellCheckerLanguage),
                grammar: pack.grammar,
                lexicon: pack.lexicon,
                explanations: pack.explanations
            )
            translator = AppleTranslator(source: pack.language, target: Locale.Language(identifier: "en"))
            lintNow()
        } catch {
            loadFailure = "The French language pack couldn't be loaded: \(error.localizedDescription)"
        }
    }

    // MARK: - Editing

    /// Schedules a lint after the learner stops typing. Styling-only changes are ignored.
    func textDidChange() {
        let plain = plainText
        guard plain != observedText else { return }
        observedText = plain
        selectedIssueID = nil
        narrator.stop()
        lintTask?.cancel()
        lintTask = Task {
            try? await Task.sleep(for: Self.lintDelay)
            guard !Task.isCancelled else { return }
            lintNow()
        }
    }

    /// Lints the current text immediately and restyles it.
    func lintNow() {
        guard let linter else { return }
        let plain = plainText
        observedText = plain
        issues = linter.lint(plain)
        lintedText = plain
        stats.record(text: plain, issues: visibleIssues)
        applyStyling()
        refreshEnglish()
    }

    /// Opens the card for the issue under the caret, if any.
    ///
    /// Moving the caret off an issue leaves the open card in place; typing, the close
    /// button, Apply and Ignore close it. The editor also resets its selection on its
    /// own when it isn't focused, which would otherwise close a card just opened.
    func selectionDidChange() {
        guard plainText == lintedText, let offset = caretOffset(),
              let hit = visibleIssues.first(where: { $0.range.contains(offset) || $0.range.upperBound == offset }),
              hit.id != selectedIssueID else { return }
        selectedIssueID = hit.id
        applyStyling()
    }

    /// Opens an issue's card and moves the caret to it.
    func select(_ issue: Issue) {
        guard plainText == lintedText, let range = attributedRange(for: issue.range) else { return }
        selectedIssueID = issue.id
        selection = AttributedTextSelection(insertionPoint: range.lowerBound)
        applyStyling()
    }

    /// Closes the open card.
    func closeCard() {
        selectedIssueID = nil
        applyStyling()
    }

    /// Replaces the issue's span with its fix, relints, and opens the next blocking issue.
    func apply(_ issue: Issue) {
        guard plainText == lintedText, let range = attributedRange(for: issue.range) else { return }
        text.replaceSubrange(range, with: AttributedString(issue.replacement))
        if issue.severity == .error {
            stats.recordFix()
        }
        lintNow()
        selectNext(after: issue.offset)
    }

    /// Hides every occurrence of this issue, so a false positive never traps the learner.
    func ignore(_ issue: Issue) {
        ignoredKeys.insert(issue.ignoreKey)
        applyStyling()
        refreshEnglish()
        selectNext(after: issue.offset)
    }

    /// Opens the first blocking issue, used when the learner taps the locked play button.
    func jumpToFirstError() {
        if let first = blockingIssues.first {
            select(first)
        }
    }

    /// The design's sample paragraph, with one mistake for each kind of check.
    static let example = "Hier, je suis allé au marché avec ma sœur. Nous avons acheté une fromage et des pommes rouge. Le boulangère était très gentile, et la pain sentait bon."

    /// Fills the editor with the sample paragraph and lints it right away.
    func loadExample() {
        text = AttributedString(Self.example)
        selection = AttributedTextSelection()
        lintNow()
        jumpToFirstError()
    }

    /// Empties the editor.
    func clear() {
        narrator.stop()
        text = AttributedString()
        selection = AttributedTextSelection()
        lintNow()
    }

    // MARK: - Play

    /// Pauses, resumes, or starts the French. A slow request always starts over at
    /// about half speed; any edit to the text stops playback.
    func togglePlay(slowly: Bool = false) {
        switch narrator.state {
        case .speaking where !slowly:
            narrator.pause()
        case .paused where !slowly:
            narrator.resume()
        default:
            guard !isLocked, hasText else { return }
            narrator.speak(plainText, rate: slowly ? SpeechNarrator.slowRate : SpeechNarrator.normalRate)
        }
    }

    // MARK: - English

    /// Translates the text when English is on and the French is correct.
    private func refreshEnglish() {
        translationTask?.cancel()
        guard isEnglishOn, !isLocked, hasText, let translator else {
            english = .idle
            return
        }
        let source = plainText
        english = .translating
        translationTask = Task {
            do {
                let translated = try await translator.translate(source)
                guard !Task.isCancelled, source == plainText else { return }
                english = .translated(translated)
            } catch TranslationUnavailable.notInstalled {
                english = .unavailable("To see English, download French for on-device translation in Settings.")
            } catch TranslationUnavailable.unsupported {
                english = .unavailable("On-device translation from French isn't available on this device.")
            } catch {
                guard !Task.isCancelled else { return }
                english = .unavailable("The translation couldn't be made: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Styling

    /// Underlines each visible issue by severity and highlights the open one.
    private func applyStyling() {
        guard plainText == lintedText else { return }
        var styled = text
        styled.underlineStyle = nil
        styled.backgroundColor = nil
        for issue in visibleIssues {
            guard let range = attributedRange(for: issue.range, in: styled) else { continue }
            styled[range].underlineStyle = Self.underline(for: issue.severity)
            if issue.id == selectedIssueID {
                styled[range].backgroundColor = Self.highlight(for: issue.severity)
            }
        }
        if styled != text {
            text = styled
        }
    }

    /// Red solid for errors, orange dots for warnings, muted dashes for suggestions.
    private static func underline(for severity: Severity) -> Text.LineStyle {
        switch severity {
        case .error: Text.LineStyle(pattern: .solid, color: .red)
        case .warning: Text.LineStyle(pattern: .dot, color: .orange)
        case .suggestion: Text.LineStyle(pattern: .dash, color: .secondary)
        }
    }

    /// A soft tint behind the open issue, in its severity's color.
    private static func highlight(for severity: Severity) -> Color {
        switch severity {
        case .error: .red.opacity(0.14)
        case .warning: .orange.opacity(0.16)
        case .suggestion: .gray.opacity(0.16)
        }
    }

    // MARK: - Helpers

    /// Opens the next blocking issue after `offset`, wrapping to the first, or closes the card.
    private func selectNext(after offset: Int) {
        let candidates = blockingIssues.isEmpty ? visibleIssues : blockingIssues
        if let next = candidates.first(where: { $0.offset > offset }) ?? candidates.first {
            select(next)
        } else {
            closeCard()
        }
    }

    /// The caret's character offset, or the start of the selection.
    private func caretOffset() -> Int? {
        let index: AttributedString.Index
        switch selection.indices(in: text) {
        case .insertionPoint(let point):
            index = point
        case .ranges(let ranges):
            guard let first = ranges.ranges.first else { return nil }
            index = first.lowerBound
        }
        return text.characters.distance(from: text.startIndex, to: index)
    }

    /// Converts character offsets to a range in the current text.
    private func attributedRange(for range: Range<Int>) -> Range<AttributedString.Index>? {
        attributedRange(for: range, in: text)
    }

    /// Converts character offsets to a range in `string`, or `nil` if out of bounds.
    private func attributedRange(for range: Range<Int>, in string: AttributedString) -> Range<AttributedString.Index>? {
        let characters = string.characters
        guard range.lowerBound >= 0, range.upperBound <= characters.count else { return nil }
        let lower = characters.index(characters.startIndex, offsetBy: range.lowerBound)
        let upper = characters.index(lower, offsetBy: range.count)
        return lower..<upper
    }
}
