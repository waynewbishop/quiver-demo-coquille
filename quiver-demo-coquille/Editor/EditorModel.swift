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
    /// The phrasebook, empty until the language pack loads.
    private(set) var phrases: [Phrase] = []
    /// The phrasebook phrase last read aloud, if any.
    private(set) var speakingPhraseID: String?

    let narrator: any Narrator
    /// Reads phrasebook phrases. It's separate from `narrator`, whose word highlight tracks the
    /// editor's text, and each one stops the other so two voices never overlap.
    let phraseNarrator: any Narrator
    let stats: StatsStore
    /// The saved entries, or `nil` in tests that don't need them.
    let journal: Journal?
    /// Where the writing is kept between launches, or `nil` to keep it only in memory.
    let workspace: Workspace?
    /// What the editor has open: unsaved writing, or a saved entry.
    private(set) var document = EditorDocument.unsaved
    /// The text the open entry was last saved with, or what unsaved writing started
    /// from: a new entry's opening lines, or nothing.
    private(set) var savedText = ""

    @ObservationIgnored private var linter: Linter?
    /// Whether the French pack has loaded, so the linter can check text.
    private(set) var isReady = false
    /// The text last kept in `workspace`, so unchanged text isn't written again.
    @ObservationIgnored private var bufferedText: String?
    /// The day a new entry's file is named for, set by New Entry.
    @ObservationIgnored private var entryDate = Date.now
    @ObservationIgnored private var translator: (any Translator)?
    /// The exact text the current `issues` describe.
    @ObservationIgnored private var lintedText = ""
    /// The text last seen by `textDidChange`, to tell typing from styling changes.
    @ObservationIgnored private var observedText = ""
    @ObservationIgnored private var lintTask: Task<Void, Never>?
    /// Whether the editor holds Try an example, whose mistakes aren't the learner's.
    /// It ends once the example's opening sentence is gone: cleared, deleted, or typed over.
    @ObservationIgnored private var isRehearsal = false
    @ObservationIgnored private var translationTask: Task<Void, Never>?

    /// How long typing must pause before the text is linted.
    static let lintDelay = Duration.milliseconds(400)

    /// Creates a model. Without a `linter`, the French pack loads in `load()`; tests
    /// pass their own linter, narrator and in-memory stats instead. The app passes a
    /// `journal` for saved entries and a `workspace` to keep unsaved work between launches.
    init(
        stats: StatsStore = StatsStore(),
        journal: Journal? = nil,
        workspace: Workspace? = nil,
        narrator: any Narrator = SpeechNarrator(language: "fr-FR"),
        phraseNarrator: any Narrator = SpeechNarrator(language: "fr-FR"),
        linter: Linter? = nil,
        translator: (any Translator)? = nil
    ) {
        self.stats = stats
        self.journal = journal
        self.workspace = workspace
        self.narrator = narrator
        self.phraseNarrator = phraseNarrator
        self.linter = linter
        self.translator = translator
    }

    // MARK: - Derived state

    /// The open entry's file, or `nil` for unsaved writing.
    var fileURL: URL? {
        if case .entry(let url) = document { url } else { nil }
    }

    /// Whether the writing has changed since it was last saved, or for unsaved writing,
    /// since it started: a new entry's opening lines alone aren't a change.
    var isEdited: Bool {
        plainText != savedText
    }

    /// Whether moving to other writing would lose work, so the learner should first
    /// choose Save or Don't Save, as in the Notebook. The example isn't the learner's
    /// work, and empty unsaved writing has nothing to lose.
    var needsSaveDecision: Bool {
        canSave && isEdited && (document != .unsaved || hasText)
    }

    /// Whether Save can keep this writing: anything but the example, once there's French.
    var canSave: Bool {
        !isRehearsal && (hasText || fileURL != nil)
    }

    /// Whether any text is selected, for Cut and Copy.
    var hasSelection: Bool {
        guard case .ranges(let ranges) = selection.indices(in: text) else { return false }
        return ranges.ranges.contains { !$0.isEmpty }
    }

    /// Whether Save first asks for a title, as it does for writing not yet in the journal.
    var saveNeedsTitle: Bool {
        fileURL == nil
    }

    /// The learner's text without styling.
    var plainText: String {
        String(text.characters)
    }

    /// The French alone: the text with every note blanked out, each character at the
    /// same offset as in `plainText`.
    var frenchText: String {
        Notes.masked(plainText)
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

    /// Whether there is any writing at all, French or notes, to save, export or start over from.
    var hasText: Bool {
        plainText.contains(where: \.isLetter)
    }

    /// Whether there is any French outside the notes to play or translate.
    var hasFrench: Bool {
        frenchText.contains(where: \.isLetter)
    }

    /// The issue whose card is open.
    var selectedIssue: Issue? {
        visibleIssues.first { $0.id == selectedIssueID }
    }

    // MARK: - Loading

    /// Loads the French pack off the main actor, then wires up the linter and translator.
    func load() async {
        guard linter == nil else { return }
        restore()
        do {
            let pack = try await Task.detached { try LanguagePack.french() }.value
            linter = Linter(
                spellChecker: SystemSpellChecker(language: pack.spellCheckerLanguage),
                grammar: pack.grammar,
                lexicon: pack.lexicon,
                explanations: pack.explanations
            )
            translator = AppleTranslator(source: pack.language, target: Locale.Language(identifier: "en"))
            isReady = true
            phrases = pack.phrases
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
        // Notes turn grey as they're typed, as in an IDE, rather than after the lint.
        styleNotes()
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
    /// Unknown words count too: with no fix to apply, every fix to one is the learner's.
    private func lint(applied: Issue?) {
        guard let linter else { return }
        let plain = plainText
        // A question with choices has no single fix, so changing its words isn't fixing an error.
        let previousErrors = visibleIssues.filter {
            ($0.severity == .error || ($0.replacement == nil && $0.choices.isEmpty)) && $0 != applied
        }
        let previousText = lintedText
        observedText = plain
        issues = linter.lint(plain)
        lintedText = plain
        let wasRehearsal = isRehearsal
        if isRehearsal, !plain.contains(Self.exampleOpening) {
            isRehearsal = false
        }
        if !isRehearsal {
            // The errors before a rehearsal ended were the example's, so none of them count as fixed.
            // Stats see the French alone, so a note is never counted as a sentence or
            // logged as part of one.
            if !wasRehearsal {
                for fix in typedFixes(of: previousErrors, from: previousText, to: plain) {
                    stats.recordFix(byLearner: true, issue: fix, in: Notes.masked(previousText))
                }
            }
            stats.record(text: Notes.masked(plain), issues: visibleIssues, editingAt: caretOffset())
        }
        persist(plain)
        applyStyling()
        refreshEnglish()
    }

    /// Errors from the previous lint that are gone because the learner typed the fix.
    ///
    /// An error counts only when its replacement now stands where the error was, so
    /// deleting a sentence never counts as fixing it.
    private func typedFixes(of errors: [Issue], from old: String, to new: String) -> [Issue] {
        guard old != new else { return [] }
        // Identical mistakes share a key, so compare counts: two "une fromage" before and
        // one after means one was fixed, whichever one now has its correction in place.
        var fixesLeft: [String: Int] = [:]
        for error in errors {
            fixesLeft[error.ignoreKey, default: 0] += 1
        }
        for issue in issues {
            fixesLeft[issue.ignoreKey]? -= 1
        }
        let shift = new.count - old.count
        return errors.filter { error in
            guard fixesLeft[error.ignoreKey, default: 0] > 0 else { return false }
            let isFixed: Bool
            if let replacement = error.replacement {
                // Edits elsewhere move the fix by at most the change in length.
                let start = max(0, error.offset + min(0, shift))
                let length = replacement.count + abs(shift)
                let window = String(new.dropFirst(start).prefix(length))
                isFixed = window.range(of: replacement, options: .caseInsensitive) != nil
            } else {
                isFixed = retypedWord(error, from: old, to: new)
            }
            if isFixed {
                fixesLeft[error.ignoreKey, default: 0] -= 1
            }
            return isFixed
        }
    }

    /// Whether the learner retyped a flagged word into one the linter now accepts.
    ///
    /// With no replacement to look for, the edit itself has to land on the word: the
    /// changed text must sit inside the old word and inside one new word that no issue
    /// flags. Deleting the word leaves no word around the edit, so it never counts.
    private func retypedWord(_ error: Issue, from old: String, to new: String) -> Bool {
        let old = Array(old), new = Array(new)
        let prefix = zip(old, new).prefix(while: { $0 == $1 }).count
        let suffix = zip(old.reversed(), new.reversed())
            .prefix(min(old.count, new.count) - prefix)
            .prefix(while: { $0 == $1 }).count
        let oldEdit = prefix..<(old.count - suffix)
        let newEdit = prefix..<(new.count - suffix)
        guard oldEdit.lowerBound >= error.range.lowerBound,
              oldEdit.upperBound <= error.range.upperBound else { return false }
        let word = FrenchTokenizer.tokens(in: String(new))
            .map { $0.offset..<($0.offset + $0.text.count) }
            .first { $0.lowerBound <= newEdit.lowerBound && newEdit.upperBound <= $0.upperBound }
        guard let word else { return false }
        return !issues.contains { $0.range.overlaps(word) }
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

    /// Opens the card of the issue after or before the open one, wrapping around, as Xcode's
    /// Next Issue does; with no card open it starts from the caret.
    func selectAdjacentIssue(forward: Bool) {
        lintIfStale()
        let ordered = visibleIssues.sorted { $0.range.lowerBound < $1.range.lowerBound }
        guard !ordered.isEmpty else { return }
        let anchor = selectedIssue?.range.lowerBound ?? caretOffset() ?? 0
        let next = forward
            ? ordered.first { $0.range.lowerBound > anchor } ?? ordered.first
            : ordered.last { $0.range.lowerBound < anchor } ?? ordered.last
        if let next { select(next) }
    }

    /// Closes the open card.
    func closeCard() {
        selectedIssueID = nil
        applyStyling()
    }

    /// Replaces the issue's span with its fix, relints, and opens the next blocking issue.
    /// An issue with no replacement has nothing to apply.
    func apply(_ issue: Issue) {
        guard plainText == lintedText, let replacement = issue.replacement,
              let range = attributedRange(for: issue.range) else { return }
        let before = plainText
        text.replaceSubrange(range, with: AttributedString(replacement))
        if issue.severity == .error, !isRehearsal {
            stats.recordFix(byLearner: false, issue: issue, in: before)
        }
        lint(applied: issue)
        selectNext(after: issue.offset)
    }

    /// Answers a "did you mean" card. Keeping the learner's own wording hides the question
    /// wherever it appears; another choice replaces the words and relints.
    func choose(_ choice: Choice, for issue: Issue) {
        guard !issue.isOriginal(choice) else {
            ignore(issue)
            return
        }
        guard plainText == lintedText, let range = attributedRange(for: issue.range) else { return }
        text.replaceSubrange(range, with: AttributedString(choice.text))
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

    /// Opens the first blocking issue, used when the learner taps the locked play button on iPhone and iPad.
    func jumpToFirstError() {
        if let first = blockingIssues.first {
            select(first)
        }
    }

    /// The design's sample paragraph, with one mistake for each kind of check and one
    /// issue at each level: errors, a warning ("elle vient plus", missing its ne), and
    /// a suggestion for an English pattern that's correct but unnatural ("c'était chaud").
    static let example = "Hier, je suis allé au marché avec ma sœur. C'était chaud. Nous avons acheté une fromage et des pommes rouge. Le boulangère était très gentile, et la pain sentait bon. Ma sœur adore ce marché, mais elle vient plus."

    /// The example's first sentence, which has no mistakes, so fixing the others never changes it.
    /// While it's in the text, the editor is still holding the example.
    static let exampleOpening = "Hier, je suis allé au marché avec ma sœur."

    /// Starts the sample paragraph as unsaved writing from a clean slate, so a rehearsal
    /// never changes the next run: ignored issues come back, and playback and English reset.
    func loadExample() {
        show(.unsaved, text: Self.example, savedText: "")
        isRehearsal = true
        lintNow()
        jumpToFirstError()
    }

    /// Opens `contents` from a clean slate like the example, as the saved entry in `url`,
    /// or as unsaved writing without one.
    ///
    /// The old text's errors are dropped before the lint, so none of them count as
    /// fixed by the learner just because the new text happens to hold their fix.
    func open(_ contents: String, from url: URL? = nil) {
        show(url.map(EditorDocument.entry) ?? .unsaved, text: contents, savedText: url == nil ? "" : contents)
        lintNow()
    }

    /// Opens a saved entry, or throws when its file can't be read.
    func openEntry(_ url: URL) throws {
        open(try FrenchTextFile.text(at: url), from: url)
    }

    /// Starts today's journal entry, unsaved, with the date and opening lines for the
    /// weather, the place, clothes and mood, with the caret after "Il fait". Save names
    /// its file for `date`.
    func newEntry(on date: Date = .now) {
        let entry = Self.entryHeader(for: date)
        show(.unsaved, text: entry.text, savedText: entry.text)
        entryDate = date
        let caret = text.characters.index(text.startIndex, offsetBy: entry.caret)
        selection = AttributedTextSelection(insertionPoint: caret)
        lintNow()
    }

    /// Starts over with a blank editor, as the Notebook's New does. Whatever wasn't
    /// saved is let go, since the learner already chose Save or Don't Save.
    func startNew() {
        show(.unsaved, text: "", savedText: "")
        entryDate = .now
        lintNow()
    }

    // MARK: - Saving

    /// Saves the writing. A saved entry is written back to its file; unsaved writing
    /// becomes a new entry named for its date and `title`.
    func save(title: String? = nil) throws {
        guard let journal, canSave else { return }
        let plain = plainText
        if let fileURL {
            try journal.write(plain, to: fileURL)
            didSave(plain, as: fileURL)
        } else {
            try saveAsNewEntry(title: title)
        }
    }

    /// Saves the writing as a new entry named for its date and `title`, leaving any entry
    /// it came from as it was saved.
    func saveAsNewEntry(title: String?) throws {
        guard let journal, canSave else { return }
        let plain = plainText
        let url = try journal.createEntry(text: plain, title: title, on: document == .unsaved ? entryDate : .now)
        didSave(plain, as: url)
    }

    /// The name Save would give new writing, such as "2026-10-31 Une journée au marché".
    func proposedName(title: String?) -> String {
        journal?.proposedName(title: title, on: document == .unsaved ? entryDate : .now) ?? ""
    }

    /// Notes that the editor now shows the saved entry at `url`.
    private func didSave(_ plain: String, as url: URL) {
        document = .entry(url)
        savedText = plain
        bufferedText = plain
        workspace?.clearUnsaved()
        workspace?.setOpenDocument(document)
    }

    // MARK: - Managing entries

    /// Gives a saved entry a new title; the open entry follows its file.
    func renameEntry(_ url: URL, to title: String) throws {
        guard let journal else { return }
        let renamed = try journal.rename(url, to: title)
        if url == fileURL {
            document = .entry(renamed)
            workspace?.setOpenDocument(document)
        }
    }

    /// Copies a saved entry, leaving the editor as it is.
    @discardableResult
    func duplicateEntry(_ url: URL) throws -> URL? {
        try journal?.duplicate(url)
    }

    /// Deletes a saved entry. Deleting the open one keeps its text in the editor as
    /// unsaved writing, so nothing on screen is lost until the learner moves on.
    func deleteEntry(_ url: URL) throws {
        try journal?.delete(url)
        guard url == fileURL else { return }
        document = .unsaved
        savedText = ""
        entryDate = .now
        workspace?.setOpenDocument(document)
        bufferedText = nil
        persist(plainText)
    }

    /// Keeps any typing the last lint hasn't kept yet, as when the app goes to the background.
    func saveNow() {
        persist(plainText)
    }

    /// Replaces the editor's writing with `contents` as `newDocument`. Whatever wasn't
    /// saved is let go, since the learner already chose Save or Don't Save.
    private func show(_ newDocument: EditorDocument, text contents: String, savedText saved: String) {
        workspace?.clearUnsaved()
        replaceText(with: contents)
        document = newDocument
        savedText = saved
        bufferedText = nil
        workspace?.setOpenDocument(newDocument)
    }

    /// The French month names, as a journal writes them.
    private static let frenchMonths = [
        "janvier", "février", "mars", "avril", "mai", "juin",
        "juillet", "août", "septembre", "octobre", "novembre", "décembre"
    ]

    /// The note above a new entry's date, which also shows the learner that notes exist.
    static let entryGuide = "// Finish each sentence in French, then keep going. Grey notes are never checked."

    /// A new entry's sentence starters, each with the note that sits on the line above
    /// it asking what to write about, as a comment sits above the code it describes.
    private static let entryStarters = [
        ("// What's the weather like?", "Il fait "),
        ("// Where are you writing from today?", "Je suis à "),
        ("// What are you wearing?", "Je porte "),
        ("// How do you feel, and why?", "Je me sens ")
    ]

    /// Returns a new entry's opening lines and the caret offset after "Il fait ".
    ///
    /// The date line has no full stop, so it never counts as a checked sentence on its
    /// own, and the first of the month is written "1er", as French dates are. The notes
    /// are never checked, so their full stops count as no sentences either.
    static func entryHeader(for date: Date, calendar: Calendar = .current) -> (text: String, caret: Int) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = parts.day == 1 ? "1er" : "\(parts.day ?? 1)"
        let month = frenchMonths[min(max((parts.month ?? 1) - 1, 0), 11)]
        // The guide sits above the date, as a header comment opens a file, and a blank
        // line sets off each note and its starter.
        let opening = entryGuide + "\nLe \(day) \(month) \(parts.year ?? 2026)\n"
        let pairs = entryStarters.map { note, starter in "\n" + note + "\n" + starter + "\n" }
        let text = opening + pairs.joined()
        let firstStarter = entryStarters[0]
        return (text, opening.count + 1 + firstStarter.0.count + 1 + firstStarter.1.count)
    }

    /// Drops the old text and everything about it: its errors, ignored issues, the card,
    /// playback and English, so nothing carries over into the new text.
    private func replaceText(with contents: String) {
        narrator.stop()
        lintTask?.cancel()
        translationTask?.cancel()
        ignoredKeys = []
        issues = []
        selectedIssueID = nil
        english = .idle
        isRehearsal = false
        text = AttributedString(contents)
        selection = AttributedTextSelection()
    }

    // MARK: - Play

    /// Stops the French and goes back to the start, as Xcode's Stop button does.
    func stopPlaying() {
        narrator.stop()
    }

    /// Pauses, resumes, or starts the French; any edit to the text stops playback.
    func togglePlay() {
        phraseNarrator.stop()
        lintIfStale()
        switch narrator.state {
        case .speaking:
            narrator.pause()
        case .paused:
            narrator.resume()
        case .idle:
            // The notes are spaces here, so only the French is read aloud, and the
            // spoken word's offsets still match the editor.
            guard isLintCurrent, !isLocked, hasFrench else { return }
            narrator.speak(frenchText)
        }
    }

    // MARK: - Phrasebook

    /// Whether this phrase is being read aloud right now.
    func isSpeaking(_ phrase: Phrase) -> Bool {
        speakingPhraseID == phrase.id && phraseNarrator.isSpeaking
    }

    /// Reads a phrase aloud, stopping the French first, or stops it if it's already playing.
    func togglePhrase(_ phrase: Phrase) {
        if isSpeaking(phrase) {
            phraseNarrator.stop()
            return
        }
        narrator.stop()
        speakingPhraseID = phrase.id
        phraseNarrator.speak(phrase.french)
    }

    /// Stops a phrase that's playing, as when the phrasebook closes.
    func stopPhrase() {
        phraseNarrator.stop()
    }

    // MARK: - English

    /// Translates the text when English is on and the French is correct.
    private func refreshEnglish() {
        translationTask?.cancel()
        guard isEnglishOn, !isLocked, hasFrench, let translator else {
            english = .idle
            return
        }
        let current = plainText
        let source = Notes.removed(current)
        english = .translating
        translationTask = Task {
            do {
                let translated = try await translator.translate(source)
                guard !Task.isCancelled, current == plainText else { return }
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
        // The narrator reads `frenchText`, so its UTF-16 offsets are measured there.
        let spoken = frenchText
        guard let range = Range(NSRange(location: utf16.lowerBound, length: utf16.count), in: spoken) else { return nil }
        let lower = spoken.distance(from: spoken.startIndex, to: range.lowerBound)
        return lower..<(lower + spoken[range].count)
    }

    /// Greys the notes, and only the notes, right away, leaving the issue styling for
    /// the next lint.
    ///
    /// It runs on every edit because typed text takes on the color of the text before
    /// it: without it, a line typed after a note would stay grey until the lint.
    private func styleNotes() {
        var styled = text
        Self.greyNotes(in: &styled)
        if styled != text {
            text = styled
        }
    }

    /// Clears every text color in `styled`, then colors each note the secondary grey.
    private static func greyNotes(in styled: inout AttributedString) {
        styled.foregroundColor = nil
        for note in Notes.ranges(in: String(styled.characters)) {
            let characters = styled.characters
            guard note.upperBound <= characters.count else { continue }
            let lower = characters.index(characters.startIndex, offsetBy: note.lowerBound)
            let upper = characters.index(lower, offsetBy: note.count)
            styled[lower..<upper].foregroundColor = noteColor
        }
    }

    /// The grey of a note: darker than the placeholder's, since the learner reads notes again.
    private static let noteColor = Color.secondary

    /// Greys the notes, underlines each visible issue by severity, highlights the open
    /// one, and highlights the word being read aloud.
    private func applyStyling() {
        guard plainText == lintedText else { return }
        var styled = text
        styled.underlineStyle = nil
        styled.backgroundColor = nil
        Self.greyNotes(in: &styled)
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

    // MARK: - Workspace

    /// Puts back the writing from last time, into an empty editor only: unsaved writing,
    /// or an entry with any changes it hadn't saved.
    /// A restored example is still the example, so its mistakes still aren't the learner's.
    func restore() {
        guard let workspace, let journal, !hasText else { return }
        var restored = workspace.openDocument(in: journal)
        var saved = ""
        var contents = workspace.unsavedText() ?? ""
        if case .entry(let url) = restored {
            if let file = try? FrenchTextFile.text(at: url) {
                saved = file
                contents = workspace.unsavedText() ?? file
            } else {
                restored = .unsaved
            }
        }
        document = restored
        savedText = saved
        bufferedText = contents
        observedText = contents
        isRehearsal = restored == .unsaved && contents.contains(Self.exampleOpening)
        text = AttributedString(contents)
    }

    /// Keeps the writing between launches, as the Notebook keeps its editor: unsaved
    /// writing as it stands, or an entry's changes until they're saved or discarded.
    /// Nothing here touches the journal.
    private func persist(_ plain: String) {
        guard plain != bufferedText else { return }
        bufferedText = plain
        if document == .unsaved || isEdited {
            workspace?.writeUnsaved(plain)
        } else {
            workspace?.clearUnsaved()
        }
    }

    /// Whether `text` would still block play: an error the linter finds in it, or `nil`
    /// before the French pack has loaded. Used to mark entries in the journal list.
    func hasErrors(in text: String) -> Bool? {
        guard let linter else { return nil }
        return linter.lint(text).contains { $0.severity.blocksPlayback }
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
