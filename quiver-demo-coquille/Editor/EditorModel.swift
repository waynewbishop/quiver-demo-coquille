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
        didSet {
            // Linting refreshes the English itself; otherwise refresh it here.
            if !lintIfStale() {
                refreshEnglish()
            }
        }
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

    let narrator: any Narrator
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

    /// Creates a model. Without a `linter`, the French pack loads in `load()`; tests
    /// pass their own linter, narrator and in-memory stats instead.
    init(
        stats: StatsStore = StatsStore(),
        narrator: any Narrator = SpeechNarrator(language: "fr-FR"),
        linter: Linter? = nil,
        translator: (any Translator)? = nil
    ) {
        self.stats = stats
        self.narrator = narrator
        self.linter = linter
        self.translator = translator
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

    /// Whether `issues` describe the text as it is now, rather than before the last edit.
    var isLintCurrent: Bool {
        plainText == lintedText
    }

    /// Like a compiler, nothing runs until the French is correct.
    ///
    /// Between an edit and its lint, this still reflects the previous text, so the
    /// lock doesn't flicker while typing. Play and English lint first instead.
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

    /// Lints right away if the text changed since the last lint, so play and English
    /// never act on a stale verdict. Returns whether it linted.
    @discardableResult
    private func lintIfStale() -> Bool {
        guard !isLintCurrent, linter != nil else { return false }
        lintTask?.cancel()
        lintNow()
        return true
    }

    /// Lints the current text immediately and restyles it.
    func lintNow() {
        lint(applied: nil)
    }

    /// Lints the current text, counts the errors the learner fixed by typing, and restyles.
    /// `applied` is the issue whose fix Apply just inserted, which isn't the learner's own.
    private func lint(applied: Issue?) {
        guard let linter else { return }
        let plain = plainText
        let previousErrors = visibleIssues.filter { $0.severity == .error && $0 != applied }
        let previousText = lintedText
        observedText = plain
        issues = linter.lint(plain)
        lintedText = plain
        for _ in typedFixes(of: previousErrors, from: previousText, to: plain) {
            stats.recordFix(byLearner: true)
        }
        stats.record(text: plain, issues: visibleIssues)
        applyStyling()
        refreshEnglish()
    }

    /// Errors from the previous lint that are gone because the learner typed the fix.
    ///
    /// An error counts only when its replacement now stands where the error was, so
    /// deleting a sentence never counts as fixing it.
    private func typedFixes(of errors: [Issue], from old: String, to new: String) -> [Issue] {
        guard old != new else { return [] }
        let remaining = Set(issues.map(\.ignoreKey))
        let shift = new.count - old.count
        return errors.filter { error in
            guard !remaining.contains(error.ignoreKey) else { return false }
            // Edits elsewhere move the fix by at most the change in length.
            let start = max(0, error.offset + min(0, shift))
            let length = error.replacement.count + abs(shift)
            let window = String(new.dropFirst(start).prefix(length))
            return window.range(of: error.replacement, options: .caseInsensitive) != nil
        }
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
            stats.recordFix(byLearner: false)
        }
        lint(applied: issue)
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

    /// Starts the sample paragraph from a clean slate, so a rehearsal never changes
    /// the next run: ignored issues come back, and playback and English reset.
    func loadExample() {
        narrator.stop()
        lintTask?.cancel()
        translationTask?.cancel()
        ignoredKeys = []
        selectedIssueID = nil
        english = .idle
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
        lintIfStale()
        switch narrator.state {
        case .speaking where !slowly:
            narrator.pause()
        case .paused where !slowly:
            narrator.resume()
        default:
            guard isLintCurrent, !isLocked, hasText else { return }
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

    /// Restyles the text when the narrator moves to a new word.
    func spokenWordDidChange() {
        applyStyling()
    }

    /// The word being read aloud, as character offsets into the text, or `nil`.
    private var spokenWordRange: Range<Int>? {
        guard narrator.state != .idle, let utf16 = narrator.spokenRange else { return nil }
        let plain = plainText
        guard let range = Range(NSRange(location: utf16.lowerBound, length: utf16.count), in: plain) else { return nil }
        let lower = plain.distance(from: plain.startIndex, to: range.lowerBound)
        return lower..<(lower + plain[range].count)
    }

    /// Underlines each visible issue by severity, highlights the open one, and
    /// highlights the word being read aloud.
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
        if let spoken = spokenWordRange, let range = attributedRange(for: spoken, in: styled) {
            styled[range].backgroundColor = Self.spokenHighlight
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

    /// The tint behind the word being read aloud.
    private static let spokenHighlight = Color.brand.opacity(0.22)

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
